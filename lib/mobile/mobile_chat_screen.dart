import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/friend_directory_service.dart';
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';
import 'ad_slot.dart';
import 'chat_hub.dart';
import 'message_bubble.dart';
import 'mobile_api.dart';
import 'models.dart';

/// Layar chat privat 1-lawan-1 (gaya WhatsApp).
class MobileChatScreen extends StatefulWidget {
  final String myUsername;
  final String peerUsername;
  const MobileChatScreen({super.key, required this.myUsername, required this.peerUsername});

  @override
  State<MobileChatScreen> createState() => _MobileChatScreenState();
}

class _MobileChatScreenState extends State<MobileChatScreen> with SingleTickerProviderStateMixin {
  final ChatHub _hub = ChatHub.instance;
  final List<ChatEntry> _entries = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  StreamSubscription<HubMessage>? _messageSub;
  StreamSubscription<String>? _buzzSub;
  StreamSubscription<String>? _errorSub;

  String? _peerDisplay;
  String? _historyNote;
  bool _loading = true;
  bool _sendingLocation = false;

  String get _peerLabel => _peerDisplay ?? '@${widget.peerUsername}';

  @override
  void initState() {
    super.initState();
    _hub.activePeer = widget.peerUsername;
    _peerDisplay = _hub.displayNameFor(widget.peerUsername);
    _messageSub = _hub.messages.listen(_onHubMessage);
    _buzzSub = _hub.buzzes.listen((peer) {
      if (peer == widget.peerUsername) _shakeNow();
    });
    _errorSub = _hub.errors.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    _hub.markRead(widget.peerUsername);
    _loadHistory();
    _loadPeerName();
  }

  @override
  void dispose() {
    if (_hub.activePeer == widget.peerUsername) _hub.activePeer = null;
    _messageSub?.cancel();
    _buzzSub?.cancel();
    _errorSub?.cancel();
    _shake.dispose();
    _input.dispose();
    _scroll.dispose();
    _hub.refresh();
    super.dispose();
  }

  Future<void> _loadPeerName() async {
    if (_peerDisplay != null) return;
    final name = await FriendDirectoryService().fetchDisplayName(widget.peerUsername);
    if (name != null && mounted) setState(() => _peerDisplay = name);
  }

  Future<void> _loadHistory() async {
    final history = await MobileApi.history(widget.peerUsername, widget.myUsername);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (history == null) {
        _historyNote = 'Riwayat chat tidak bisa dimuat. Periksa koneksi lalu buka ulang chat ini.';
        return;
      }
      // Pesan realtime yang masuk selagi riwayat dimuat jangan sampai tampil dua kali.
      final live = List<ChatEntry>.from(_entries);
      bool isDuplicate(ChatEntry h) => live.any(
          (l) => l.sender == h.sender && l.text == h.text && l.time.difference(h.time).inSeconds.abs() <= 2);
      _entries.insertAll(0, history.where((h) => !isDuplicate(h)));
    });
    _jumpToBottom();
  }

  void _onHubMessage(HubMessage m) {
    if (m.peer != widget.peerUsername) return;
    setState(() => _entries.add(ChatEntry(sender: m.sender, text: m.text, time: m.time, isMine: m.isMine)));
    _scrollToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 60), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _shakeNow() {
    if (mounted) _shake.forward(from: 0);
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _hub.sendMessage(widget.peerUsername, text);
    _input.clear();
  }

  void _sendBuzz() {
    HapticFeedback.mediumImpact();
    _hub.sendBuzz(widget.peerUsername);
  }

  Future<void> _sendLocation() async {
    setState(() => _sendingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _snack('Izin lokasi ditolak. Aktifkan di pengaturan HP.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      _hub.sendMessage(widget.peerUsername, '$locationPrefix${position.latitude},${position.longitude}');
    } catch (_) {
      _snack('Tidak bisa mengambil lokasi. Pastikan GPS aktif.');
    } finally {
      if (mounted) setState(() => _sendingLocation = false);
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEAF9),
      appBar: AppBar(
        backgroundColor: YmColors.titleBarStart,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(username: widget.peerUsername, viewer: widget.myUsername, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _peerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.bolt), tooltip: 'Kirim Buzz', onPressed: _sendBuzz),
        ],
      ),
      body: Column(
        children: [
          const AdSlot(placement: 'private_chat'),
          if (_historyNote != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF4E5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(_historyNote!, style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00))),
            ),
          Expanded(
            child: AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                final t = _shake.value;
                final dx = math.sin(t * math.pi * 14) * 12 * (1 - t);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length,
                      itemBuilder: (context, i) => MessageBubble(entry: _entries[i], peerName: _peerLabel),
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.bolt, color: YmColors.buzzRed),
                    tooltip: 'Buzz',
                    onPressed: _sendBuzz,
                  ),
                  IconButton(
                    icon: _sendingLocation
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.location_on_outlined, color: YmColors.accentPurple),
                    tooltip: 'Kirim lokasi',
                    onPressed: _sendingLocation ? null : _sendLocation,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ketik pesan',
                        filled: true,
                        fillColor: const Color(0xFFF1F0FB),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    backgroundColor: YmColors.accentPurple,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
