import 'dart:async';
import '../config/app_config.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/emoticon_picker.dart';
import '../widgets/buzz_overlay.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/socket_service.dart';
import '../services/window_launcher.dart';
import '../services/secure_storage_service.dart';
import '../services/friend_directory_service.dart';
import '../services/block_service.dart';
import 'call_screen.dart';

// Simple inline content-type markers so image/location messages can be
// told apart from plain text without needing a backend schema change —
// the backend just stores/relays these as opaque strings either way.
const _locationPrefix = '[LOCATION]';
const _imagePrefix = '[IMAGE_BASE64]';
// Buzz disimpan sebagai pesan chat biasa dengan isi persis ini (harus sama dengan BUZZ_MARKER di
// backend app/sockets.py) — sehingga tampil di riwayat chat, termasuk untuk penerima yang offline.
const _buzzMarker = '[BUZZ]';

enum _MessageKind { text, location, image, audible, buzz }

class _ChatMessage {
  final String sender;
  final String text; // raw content, possibly with a marker prefix
  final bool isMine;
  final DateTime time; // waktu pesan dikirim (dari server), ditampilkan kecil di bawah bubble
  _ChatMessage({required this.sender, required this.text, required this.isMine, DateTime? time})
      : time = time ?? DateTime.now();

  _MessageKind get kind {
    if (text == _buzzMarker) return _MessageKind.buzz;
    if (text.startsWith(_locationPrefix)) return _MessageKind.location;
    if (text.startsWith(_imagePrefix)) return _MessageKind.image;
    if (decodeAudibleMessage(text) != null) return _MessageKind.audible;
    return _MessageKind.text;
  }
}

/// Epoch detik dari server -> waktu lokal pengguna.
DateTime _timeFromTs(double ts) => DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());

class _LatLng {
  final double lat;
  final double lng;
  const _LatLng(this.lat, this.lng);
}

/// Membaca "lat,lng" dari isi pesan lokasi. Isi pesan berasal dari orang lain, jadi HANYA angka yang lolos
/// validasi (dalam rentang wajar) yang dipakai membentuk URL — teks mentahnya tidak pernah disalin ke URL.
_LatLng? _parseCoordinates(String raw) {
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return _LatLng(lat, lng);
}

Future<void> _openInGoogleMaps(BuildContext context, _LatLng point) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${point.lat.toStringAsFixed(6)},${point.lng.toStringAsFixed(6)}',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa membuka Google Maps.')));
  }
}

/// A genuine private 1-on-1 chat — uses send_direct_message (NOT
/// join_city_room/send_message), so it's truly isolated between exactly
/// these two people, independent of any room. Each private chat opens as
/// its own OS window (see WindowLauncher), so a user can have many of
/// these open with different people simultaneously.
class ChatWindowScreen extends StatefulWidget {
  final String city; // kept for display context ("last seen in Batam"), not used for routing anymore
  final String myUsername;
  final String peerUsername;
  // true = jendela dibuka oleh Home karena peer mengirim Buzz -> langsung muncul di depan + bergetar + bunyi.
  final bool buzzOnOpen;

  const ChatWindowScreen({
    super.key,
    required this.city,
    required this.myUsername,
    required this.peerUsername,
    this.buzzOnOpen = false,
  });

  @override
  State<ChatWindowScreen> createState() => _ChatWindowScreenState();
}

class _ChatWindowScreenState extends State<ChatWindowScreen> with SingleTickerProviderStateMixin {
  final _messages = <_ChatMessage>[];
  final _audiblePlayer = AudioPlayer();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final SocketService _socket;

  // Nama lawan bicara di layar SAYA: nama panggilan pribadi > nickname (null = pakai @username).
  String? _peerDisplay;
  // Alasan riwayat chat gagal dimuat (ditampilkan kecil di atas chat supaya penyebabnya kelihatan).
  String? _historyNote;
  String get _peerLabel => _peerDisplay ?? '@${widget.peerUsername}';

  bool _showEmoticons = false;
  bool _isShaking = false;
  bool _sendingAttachment = false;
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _configureWindowSize();

    // NOTE: pass your real backend URL. Use wss:// (TLS) in production.
    _socket = SocketService(
      onDirectMessageReceived: (sender, message, ts) {
        // Server mengirim pesan ke SEMUA jendela chat milik penerima; jendela ini hanya
        // menampilkan pesan dari lawan bicaranya sendiri.
        if (sender != widget.peerUsername) return;
        setState(() => _messages.add(_ChatMessage(sender: sender, text: message, isMine: false, time: _timeFromTs(ts))));
        _scrollToBottom();
        // Audibles need actual sound when RECEIVED, not just an icon —
        // reuses the same synthesized buzz.wav asset (no licensed
        // per-audible sound files shipped), better than the previous
        // silent "just plain text" behavior.
        if (decodeAudibleMessage(message) != null) {
          _audiblePlayer.play(AssetSource('sounds/buzz.wav'));
        }
      },
      onDirectMessageSent: (recipient, message, ts) {
        setState(() => _messages.add(_ChatMessage(sender: widget.myUsername, text: message, isMine: true, time: _timeFromTs(ts))));
        _scrollToBottom();
        // Kilatan buzz untuk pengirim baru muncul SETELAH server menerima buzz-nya
        // (kalau ditolak, mis. cooldown, hanya pesan error yang tampil).
        if (mounted && message == _buzzMarker) {
          BuzzOverlay.show(context, from: 'Kamu \u2192 $_peerLabel', playSound: false);
        }
      },
      // Hanya buzz dari lawan bicara jendela INI yang menggetarkan jendela ini. Buzz dari orang lain
      // ditangani Home (membuka jendela chat orang itu), bukan jendela chat yang kebetulan sedang terbuka.
      onBuzzReceived: (from) {
        if (from == widget.peerUsername) _receiveBuzz(from);
      },
      onError: (msg) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
      onForceLogout: (reason) => _handleForceLogout(reason),
      onCallIncoming: (callerUsername, callType, callRoom) {
        // Only relevant if it's from the peer THIS specific window is
        // chatting with — a call from someone else should surface via
        // their own chat window, not this one.
        if (callerUsername == widget.peerUsername) {
          _showIncomingCallDialog(callType, callRoom);
        }
      },
    )..connect(AppConfig.socketUrl);
    _socket.registerPrivateChat(widget.myUsername);
    _loadHistory();
    _loadPeerDisplay();
    // Dibuka oleh Home karena Buzz: tunggu jendela selesai dibuat/dipusatkan, lalu munculkan + getarkan.
    if (widget.buzzOnOpen) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _receiveBuzz(widget.peerUsername);
      });
    }
  }

  Future<void> _loadPeerDisplay() async {
    final name = await FriendDirectoryService().fetchDisplayName(widget.peerUsername);
    if (name != null && mounted) setState(() => _peerDisplay = name);
  }

  /// Memuat riwayat chat dengan lawan bicara ini (termasuk Buzz yang datang saat kita offline).
  Future<void> _loadHistory() async {
    try {
      final token = await SecureStorageService().getSessionToken();
      if (token == null) {
        _setHistoryNote('Riwayat tidak dimuat: sesi login tidak ditemukan. Coba login ulang.');
        return;
      }
      final res = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/dm/history')
                .replace(queryParameters: {'peer': widget.peerUsername, 'limit': '100'}),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode != 200) {
        _setHistoryNote(res.statusCode == 404
            ? 'Riwayat tidak dimuat (404): backend belum diperbarui atau belum di-restart.'
            : 'Riwayat tidak dimuat (kode ${res.statusCode}).');
        return;
      }

      final list = jsonDecode(res.body)['messages'] as List;
      final history = list.map((m) {
        final sender = m['sender'] as String;
        return _ChatMessage(
          sender: sender,
          text: m['message'] as String,
          isMine: sender == widget.myUsername,
          time: _timeFromTs((m['ts'] as num).toDouble()),
        );
      }).toList();

      setState(() {
        // Pesan realtime yang masuk selagi riwayat dimuat jangan sampai tampil dua kali.
        final live = List<_ChatMessage>.from(_messages);
        bool isDuplicate(_ChatMessage h) => live.any((l) =>
            l.sender == h.sender && l.text == h.text && l.time.difference(h.time).inSeconds.abs() <= 2);
        _messages.insertAll(0, history.where((h) => !isDuplicate(h)));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
    } catch (e) {
      // Riwayat gagal dimuat (server mati / offline): chat tetap bisa dipakai tanpa riwayat.
      _setHistoryNote('Riwayat tidak dimuat: ${e.runtimeType}');
    }
  }

  void _setHistoryNote(String note) {
    debugPrint('[chat] $note');
    if (mounted) setState(() => _historyNote = note);
  }

  /// Server-enforced anti-abuse limit hit (e.g. more than 10 private chat
  /// windows open at once) — ends the session hard rather than a gentle
  /// inline error, matching the deliberately harsh "immediately logout"
  /// requirement. Clears the saved session and closes this window; other
  /// windows independently receive the same 'force_logout' event since
  /// the server broadcasts it to every sid this username has open.
  Future<void> _handleForceLogout(String reason) async {
    await SecureStorageService().clearSession();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi diakhiri: terlalu banyak jendela chat terbuka.'), backgroundColor: YmColors.buzzRed),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        await WindowLauncher.closeThisWindow();
      }
    }
  }

  /// Private Chat is resizable, unlike Login/Home — minimum 400x680,
  /// matching Login/Home/Room Chat (was 300x600, unified per feedback).
  /// No upper limit. Same pattern as RoomChatScreen's _configureWindowSize.
  Future<void> _configureWindowSize() async {
    try {
      await windowManager.setMinimumSize(const Size(400, 680));
      await windowManager.setResizable(true);
    } catch (e) {
      // ignore: avoid_print
      print('[ChatWindow] window_manager unavailable (native patch from NATIVE_SETUP.md not applied?): $e');
    }
  }

  /// Buzz diterima dari lawan bicara: munculkan jendela ke depan (walau aplikasi di tray / jendela
  /// tertutup window lain), getarkan isi + jendelanya, dan bunyikan suara buzz.
  Future<void> _receiveBuzz(String from) async {
    _triggerBuzz(from); // getar isi + kilatan merah + SUARA buzz (buzz.wav)
    await _bringToFront();
    await _shakeWindow();
  }

  Future<void> _bringToFront() async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      // "Selalu di atas" sebentar: Windows melarang aplikasi di latar belakang mencuri fokus, tetapi jendela
      // tetap bisa ditampilkan di atas semua window lain.
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await windowManager.setAlwaysOnTop(false);
        } catch (_) {}
      });
    } catch (_) {
      // window_manager tidak tersedia / jendela sedang ditutup: abaikan
    }
  }

  bool _windowShaking = false;

  /// Menggetarkan JENDELA-nya sendiri (bukan hanya isinya), seperti Buzz di messenger klasik.
  Future<void> _shakeWindow() async {
    if (_windowShaking) return;
    _windowShaking = true;
    try {
      if (await windowManager.isMaximized()) return;
      final origin = await windowManager.getPosition();
      for (var i = 0; i < 14; i++) {
        final dx = i.isEven ? 10.0 : -10.0;
        final dy = i % 3 == 0 ? 5.0 : 0.0;
        await windowManager.setPosition(Offset(origin.dx + dx, origin.dy + dy));
        await Future.delayed(const Duration(milliseconds: 35));
      }
      await windowManager.setPosition(origin);
    } catch (_) {
      // gagal menggetarkan jendela: efek di isi jendela tetap jalan
    } finally {
      _windowShaking = false;
    }
  }

  void _triggerBuzz(String from) {
    setState(() => _isShaking = true);
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isShaking = false);
    });
    // Full-screen flash + sound, like classic IM clients — not a quiet SnackBar.
    BuzzOverlay.show(context, from: from == widget.peerUsername ? _peerLabel : from);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send(String content) {
    _socket.sendDirectMessage(
      senderUsername: widget.myUsername,
      recipientUsername: widget.peerUsername,
      message: content,
    );
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _send(text);
    _inputCtrl.clear();
    setState(() => _showEmoticons = false);
  }

  void _sendBuzz() {
    // Server menyimpan Buzz sebagai pesan chat lalu membalas 'direct_message_sent'; kilatan layar
    // untuk pengirim ditampilkan di handler onDirectMessageSent di atas (tanpa suara — suara
    // adalah tanda "kamu di-buzz" untuk PENERIMA).
    _socket.buzz(requesterUsername: widget.myUsername, targetUsername: widget.peerUsername);
  }

  /// Shares the sender's current GPS location as a small card the
  /// recipient can tap to open in their maps app.
  Future<void> _sendLocation() async {
    setState(() => _sendingAttachment = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Layanan lokasi sedang mati di sistem kamu.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showError('Izin lokasi ditolak.');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      _send('$_locationPrefix${position.latitude},${position.longitude}');
    } catch (e) {
      _showError('Gagal mengambil lokasi: $e');
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  /// Picks and sends an IMAGE only — deliberately restricted to image
  /// extensions (FileType.image), never general file sharing, per spec.
  Future<void> _sendImage() async {
    setState(() => _sendingAttachment = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();
      // NOTE: base64-in-a-chat-message is simple but not efficient for
      // large images or high message volume — fine for a first version,
      // but consider a dedicated upload endpoint + URL-only messages if
      // image sharing gets heavy use.
      final base64Data = base64Encode(bytes);
      _send('$_imagePrefix$base64Data');
    } catch (e) {
      _showError('Gagal mengirim gambar: $e');
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  /// Starts a call — generates a unique call_room, opens CallScreen which
  /// handles the invite/ringing/connect flow. A stable, sorted room name
  /// (not a random UUID) means both sides independently compute the SAME
  /// room name without needing a round-trip first.
  void _startCall(String callType) {
    final names = [widget.myUsername, widget.peerUsername]..sort();
    final callRoom = 'call-${names.join("-")}-${DateTime.now().millisecondsSinceEpoch}';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        myUsername: widget.myUsername,
        peerUsername: widget.peerUsername,
        callType: callType,
        callRoom: callRoom,
        isIncoming: false,
        socket: _socket,
      ),
    ));
  }

  /// Shows an incoming-call dialog when this peer calls US while we're
  /// looking at their chat window. Accepting opens CallScreen directly
  /// into the "connecting" phase (isIncoming: true) — no second ring.
  void _showIncomingCallDialog(String callType, String callRoom) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(callType == 'video' ? 'Video Call Masuk' : 'Voice Call Masuk'),
        content: Text('$_peerLabel sedang menelepon kamu.'),
        actions: [
          TextButton(
            onPressed: () {
              _socket.callReject(callerUsername: widget.peerUsername);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Tolak', style: TextStyle(color: YmColors.buzzRed)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _socket.callAccept(callerUsername: widget.peerUsername, callRoom: callRoom);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CallScreen(
                  myUsername: widget.myUsername,
                  peerUsername: widget.peerUsername,
                  callType: callType,
                  callRoom: callRoom,
                  isIncoming: true,
                  socket: _socket,
                ),
              ));
            },
            child: const Text('Terima'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _socket.unregisterPrivateChat(widget.myUsername);
    _socket.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _shakeCtrl.dispose();
    _audiblePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final offset = _isShaking ? (8 * (1 - _shakeCtrl.value)) * ((_shakeCtrl.value * 20).floor().isEven ? 1 : -1) : 0.0;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Scaffold(
        body: Column(
          children: [
            RetroTitleBar(
              title: _peerLabel,
              icon: Icons.chat_bubble_outline,
              trailing: _TitleBarBlockButton(
                onTap: () => BlockService.confirmAndBlock(
                  context,
                  myUsername: widget.myUsername,
                  targetUsername: widget.peerUsername,
                ),
              ),
            ),
            // Toolbar: call / video call / location / image
            Container(
              color: YmColors.contentBackground,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.call_outlined, size: 20, color: YmColors.textMuted),
                    tooltip: 'Voice Call',
                    onPressed: () => _startCall('voice'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_outlined, size: 20, color: YmColors.textMuted),
                    tooltip: 'Video Call',
                    onPressed: () => _startCall('video'),
                  ),
                  const Spacer(),
                  Text(_peerLabel, style: YmTextStyles.statusMessage),
                ],
              ),
            ),
            Container(height: 1, color: YmColors.borderLavender.withOpacity(0.5)),
            if (_historyNote != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF4E5),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(_historyNote!, style: const TextStyle(fontSize: 11, color: Color(0xFF8A5A00))),
              ),
            Expanded(
              child: Container(
                color: YmColors.panelBackground,
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) => _MessageBubble(message: _messages[i], peerName: _peerLabel),
                ),
              ),
            ),
            Container(height: 1, color: YmColors.borderLavender.withOpacity(0.5)),
            if (_sendingAttachment) const LinearProgressIndicator(minHeight: 2),
            Container(
              color: YmColors.contentBackground,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, color: YmColors.accentPurple),
                    onPressed: () => setState(() => _showEmoticons = !_showEmoticons),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bolt, color: YmColors.buzzRed),
                    tooltip: 'Buzz',
                    onPressed: _sendBuzz,
                  ),
                  IconButton(
                    icon: const Icon(Icons.location_on_outlined, color: YmColors.accentPurple),
                    tooltip: 'Kirim Lokasi',
                    onPressed: _sendingAttachment ? null : _sendLocation,
                  ),
                  IconButton(
                    icon: const Icon(Icons.image_outlined, color: YmColors.accentPurple),
                    tooltip: 'Kirim Gambar',
                    onPressed: _sendingAttachment ? null : _sendImage,
                  ),
                  // Deliberately NO general file-attach button — images and
                  // location only, per spec.
                  Expanded(
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                          if (HardwareKeyboard.instance.isShiftPressed) {
                            return KeyEventResult.ignored; // let Shift+Enter insert a newline normally
                          }
                          _sendMessage();
                          return KeyEventResult.handled; // plain Enter sends, no newline inserted
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _inputCtrl,
                        style: YmTextStyles.chatText,
                        maxLines: null,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'Ketik pesan... (Shift+Enter untuk baris baru)',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: YmColors.panelBackground,
                          // A visible border/fill matters here — without
                          // it, short content (like 1-2 emoji) rendered
                          // borderless can look indistinguishable from the
                          // toolbar's own icons, making it unclear
                          // there's actually text sitting in an input
                          // field ready to send.
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: YmColors.borderLavender)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: YmColors.borderLavender)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: YmColors.accentPurple, width: 1.5)),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: YmColors.accentPurple),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
            if (_showEmoticons)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: EmoticonPicker(
                  onPicked: (emoji) => setState(() => _inputCtrl.text += emoji),
                  // Sends immediately as its own message, like a reaction —
                  // NOT appended to the composer for the user to send later.
                  onAudiblePicked: (encoded) {
                    _send(encoded);
                    setState(() => _showEmoticons = false);
                    _audiblePlayer.play(AssetSource('sounds/buzz.wav'));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final String peerName; // nama lawan bicara di layar saya (nama panggilan / nickname / @username)
  const _MessageBubble({required this.message, required this.peerName});

  @override
  Widget build(BuildContext context) {
    final align = message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = message.isMine ? YmColors.bubbleOutgoing : YmColors.bubbleIncoming;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!message.isMine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(peerName, style: YmTextStyles.label),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: message.kind == _MessageKind.image
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(ymBorderRadius)),
            child: _buildContent(context),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(
              DateFormat('dd/MM/yyyy HH:mm').format(message.time),
              style: const TextStyle(fontSize: 10, color: YmColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.kind) {
      case _MessageKind.location:
        final coords = message.text.substring(_locationPrefix.length);
        final point = _parseCoordinates(coords);
        // Bisa diketuk: membuka lokasi itu di Google Maps (browser bawaan).
        return InkWell(
          borderRadius: BorderRadius.circular(ymBorderRadius - 2),
          onTap: point == null ? null : () => _openInGoogleMaps(context, point),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, size: 18, color: YmColors.accentPurple),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point == null
                          ? 'Lokasi: $coords'
                          : 'Lokasi: ${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}',
                      style: YmTextStyles.chatText,
                    ),
                    if (point != null)
                      const Text(
                        'Ketuk untuk buka di Google Maps',
                        style: TextStyle(
                          fontSize: 10,
                          color: YmColors.accentPurple,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case _MessageKind.image:
        final base64Data = message.text.substring(_imagePrefix.length);
        try {
          return ClipRRect(
            borderRadius: BorderRadius.circular(ymBorderRadius - 2),
            child: Image.memory(base64Decode(base64Data), width: 220, fit: BoxFit.cover),
          );
        } catch (_) {
          return Text('[Gambar tidak bisa ditampilkan]', style: YmTextStyles.chatText);
        }

      case _MessageKind.audible:
        final audible = decodeAudibleMessage(message.text)!;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(audible.icon, size: 20, color: YmColors.accentPurple),
            const SizedBox(width: 6),
            Text(audible.label, style: YmTextStyles.chatText.copyWith(fontWeight: FontWeight.w600)),
          ],
        );

      case _MessageKind.buzz:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 18, color: YmColors.buzzRed),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message.isMine ? 'Kamu mengirim Buzz!' : '$peerName mengirim Buzz!',
                style: YmTextStyles.chatText.copyWith(fontWeight: FontWeight.w700, color: YmColors.buzzRed),
              ),
            ),
          ],
        );

      case _MessageKind.text:
        return Text(message.text, style: YmTextStyles.chatText);
    }
  }
}

/// Tombol "Blokir" kecil di title bar chat pribadi, gaya senada tombol
/// minimize/maximize/close di RetroTitleBar (lihat _TitleBarButton di sana —
/// tidak dipakai ulang langsung karena class itu private ke file itu).
class _TitleBarBlockButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TitleBarBlockButton({required this.onTap});

  @override
  State<_TitleBarBlockButton> createState() => _TitleBarBlockButtonState();
}

class _TitleBarBlockButtonState extends State<_TitleBarBlockButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: _hovering ? Colors.red.withOpacity(0.35) : Colors.transparent,
          alignment: Alignment.center,
          child: const Icon(Icons.block, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}
