import 'dart:convert';
import '../config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/emoticon_picker.dart';
import '../widgets/buzz_overlay.dart';
import '../services/socket_service.dart';
import '../services/window_launcher.dart';
import '../services/secure_storage_service.dart';
import '../models/buddy.dart';
import 'user_profile_dialog.dart';
import 'public_profile_dialog.dart';

const _apiBase = AppConfig.apiBaseUrl;

const _locationPrefix = '[LOCATION]';

class _RoomMessage {
  final String sender;
  final String text;
  final bool isMine;
  _RoomMessage({required this.sender, required this.text, required this.isMine});
}

class _LatLng {
  final double lat;
  final double lng;
  const _LatLng(this.lat, this.lng);
}

/// Sama seperti chat_window_screen.dart punya sendiri (Dart tidak bisa
/// berbagi anggota berawalan _ antar file) — hanya angka dalam rentang
/// wajar yang lolos, teks mentahnya tidak pernah disalin ke URL.
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

/// Public room chat — many participants, message stream on the left,
/// live user list on the right. Distinct from the 1-on-1 ChatWindowScreen.
///
/// Rooms deliberately have NO image-sharing button anywhere in this file —
/// only private/direct chat (chat_window_screen.dart) supports images.
/// The only media a room supports is shared music, and only the room's
/// creator/operators can start/stop it (enforced server-side too).
/// A room participant EXACTLY as the server exposes them: nickname + uid.
/// Other people's usernames (the login id) are never sent to the room —
/// they only become visible once you're friends (see _friendUsernameByUid).
class _RoomMember {
  final int uid;
  final String nickname;
  final String role; // 'creator' | 'operator' | ''
  final BuddyGender gender;
  final bool hasSpeakerEnabled;
  const _RoomMember({
    required this.uid,
    required this.nickname,
    required this.role,
    required this.gender,
    required this.hasSpeakerEnabled,
  });

  BuddyStatus get status => BuddyStatus.online; // being in the list already means online

  factory _RoomMember.fromJson(Map<String, dynamic> j) => _RoomMember(
        uid: (j['uid'] as num).toInt(),
        nickname: (j['nickname'] as String?) ?? 'Tanpa nama',
        role: (j['role'] as String?) ?? '',
        gender: j['gender'] == 'male'
            ? BuddyGender.male
            : (j['gender'] == 'female' ? BuddyGender.female : BuddyGender.unspecified),
        hasSpeakerEnabled: j['speaker'] == true,
      );
}

class RoomChatScreen extends StatefulWidget {
  final String roomName;
  final String myUsername;
  final String? pin; // for private rooms — passed through to join_city_room
  const RoomChatScreen({super.key, required this.roomName, required this.myUsername, this.pin});

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  final _messages = <_RoomMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final SocketService _socket;
  bool _showEmoticons = false;

  // Live room presence — filled from room_joined / user_left. Each member
  // is nickname + uid + role (creator/operator) + gender + speaker flag,
  // all delivered by the server in one go, so no per-user profile fetches
  // (which needed usernames) are needed anymore.
  List<_RoomMember> _members = [];
  bool _hasJoinedRoom = false; // false until room_joined fires — see onError below

  // Who am I in this room, and who are the creator/operators (uid+nickname).
  int? _myUid;
  String? _myRole; // 'creator' | 'operator' | null
  // Terpisah dari _myRole: true untuk creator/operator BIASA, ATAU untuk
  // admin dinamis room default (siapa yang masuk paling duluan dan masih
  // ada) — lihat app/rooms.py's is_allowed_to_control_music. Sengaja
  // tidak digabung ke _canManageOperators supaya admin dinamis TIDAK
  // ikut bisa mengangkat operator tetap, hanya kontrol musik.
  bool _canControlMusic = false;
  List<Map<String, dynamic>> _operators = []; // [{uid, nickname}]
  int _maxOperators = 5;

  // uid -> username, ONLY for my friends. It's how a room member is
  // recognised as a friend: for them (and only them) the username is
  // known, so private chat / profile-by-username work. Strangers never
  // have a username here.
  Map<int, String> _friendUsernameByUid = {};

  Future<void> _loadFriends() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/friends-detail/${widget.myUsername}'));
      if (res.statusCode == 200 && mounted) {
        final list = List<Map<String, dynamic>>.from(
          (jsonDecode(res.body)['friends'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        setState(() => _friendUsernameByUid = {
              for (final f in list) (f['uid'] as num).toInt(): f['username'] as String,
            });
      }
    } catch (_) {
      // best-effort — without it everyone just looks like a stranger
    }
  }

  bool _isSelf(_RoomMember m) => m.uid == _myUid;
  bool _isFriend(_RoomMember m) => _friendUsernameByUid.containsKey(m.uid);

  void _openPrivateChatWith(_RoomMember m) {
    final username = _friendUsernameByUid[m.uid];
    if (username == null) return;
    WindowLauncher.openPrivateChat(myUsername: widget.myUsername, peerUsername: username, city: widget.roomName);
  }

  void _showProfileOf(_RoomMember m) {
    final friendUsername = _friendUsernameByUid[m.uid];
    showDialog(
      context: context,
      builder: (_) => friendUsername != null
          ? UserProfileDialog(username: friendUsername, viewerUsername: widget.myUsername)
          : PublicProfileDialog(uid: m.uid, viewerUsername: widget.myUsername),
    );
  }

  Future<void> _sendFriendRequestTo(_RoomMember m) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/friends/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'from_username': widget.myUsername, 'to_uid': m.uid}),
      );
      if (!mounted) return;
      String text = 'Permintaan pertemanan dikirim ke ${m.nickname}.';
      if (res.statusCode != 200) {
        text = 'Gagal mengirim permintaan.';
        try {
          text = jsonDecode(res.body)['detail']?.toString() ?? text;
        } catch (_) {}
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  // --- Music playback state ---
  final _audioPlayer = AudioPlayer();
  final _audiblePlayer = AudioPlayer(); // separate instance so an audible's "ding" doesn't interrupt music playback
  // WebView2 controller is created LAZILY, only when a room actually
  // plays a YouTube track (see _ensureYoutubePlayer). It used to be
  // created + initialized in initState for EVERY room, so every Room Chat
  // window carried a live WebView2 browser process even when no music was
  // playing — and tearing that down while the window closed is what
  // crashed the whole app.
  WebViewController? _youtubeController;
  Future<void>? _youtubeInit;
  bool _youtubeInitialized = false; // initialize() finished OK -> must be dispose()d
  bool _youtubeReady = false;       // ...and it's safe to show the Webview widget
  bool _youtubeFailed = false;

  // Shutdown state — see _shutdown().
  bool _closing = false;
  bool _disposed = false;
  Future<void>? _shutdownFuture;
  bool _musicPlaying = false;
  String? _musicSourceType; // "upload" | "youtube"
  String? _musicStartedBy;
  double _volume = 0.7;
  bool _uploadingMusic = false;

  bool get _canManageOperators => _myRole != null;

  @override
  void initState() {
    super.initState();
    // Ordered native cleanup that must finish BEFORE the window is
    // destroyed — see WindowLauncher.beforeCloseHooks.
    WindowLauncher.beforeCloseHooks.add(_shutdown);
    _loadOperators();
    _loadFriends();
    _audioPlayer.setVolume(_volume);
    _configureWindowSize();

    _socket = SocketService(
      onRoomJoined: (city, members) {
        _hasJoinedRoom = true;
        setState(() => _members = members.map(_RoomMember.fromJson).toList());
        // Room default: siapa yang paling lama bertahan bisa berubah setiap
        // ada yang masuk/keluar — muat ulang hak kontrol musik saat ini.
        _loadOperators();
      },
      onUserLeft: (city, members) {
        // This is what makes disconnected/offline members disappear from
        // the list automatically — no manual "leave" action needed, and
        // no lingering "offline" entries.
        setState(() => _members = members.map(_RoomMember.fromJson).toList());
        // Orang yang keluar bisa jadi admin dinamis room default saat ini —
        // muat ulang supaya orang berikutnya yang masuk paling lama langsung
        // mendapat kendali musik, tanpa perlu keluar-masuk room dulu.
        _loadOperators();
      },
      onError: (msg) async {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        // If the join itself was rejected (e.g. hit the max-2-rooms limit)
        // there's nothing useful this window can show — close it rather
        // than leaving an empty, non-functional room chat open.
        if (!_hasJoinedRoom) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).maybePop();
        }
      },
      onSystemMessage: (text) {
        setState(() => _messages.add(_RoomMessage(sender: 'Sistem', text: text, isMine: false)));
        _scrollToBottom();
      },
      onNewMessage: (sender, message, ts) {
        setState(() => _messages.add(_RoomMessage(
              sender: sender,
              text: message,
              // The server echoes my own messages as 'Anda' (message_sent);
              // everyone else arrives as their nickname.
              isMine: sender == 'Anda',
            )));
        _scrollToBottom();
        // Room broadcasts loop back to the sender too (that's how `isMine`
        // above even works), so checking here alone covers both "I picked
        // an audible" and "someone else did" — no separate play-on-pick
        // needed like Private Chat has its own echo path for.
        if (decodeAudibleMessage(message) != null) {
          _audiblePlayer.play(AssetSource('sounds/buzz.wav'));
        }
      },
      onBuzzReceived: (from) {
        BuzzOverlay.show(context, from: from);
      },
      onRoomFull: (city, maxMembers) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Room Penuh'),
            content: Text('Room "$city" sudah mencapai kapasitas maksimal ($maxMembers orang online). Coba lagi nanti.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).maybePop();
                },
                child: const Text('Oke'),
              ),
            ],
          ),
        );
      },
      onForceLogout: (reason) async {
        // The server broadcasts this to EVERY window a username has open
        // when an anti-abuse limit is hit elsewhere (e.g. too many private
        // chat windows) — this window closes too, ending the whole session
        // consistently rather than leaving some windows orphaned.
        await SecureStorageService().clearSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sesi diakhiri.'), backgroundColor: YmColors.buzzRed),
          );
          await Future.delayed(const Duration(seconds: 2));
          await WindowLauncher.closeThisWindow();
        }
      },
    )..connect(AppConfig.socketUrl);

    // The server dropped this window from the room: either the user logged
    // out, or opened the same room in a newer window. Either way this window
    // is now a stale leftover — close it (which runs the normal ordered
    // shutdown) instead of leaving it hanging in a room it's no longer in.
    _socket.onRoomEvicted = (reason) async {
      if (!mounted || _closing) return;
      if (reason == 'replaced') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room ini dibuka di jendela lain.')),
        );
        await Future.delayed(const Duration(milliseconds: 800));
      }
      await WindowLauncher.closeThisWindow();
    };

    _socket.onMusicStarted = (sourceType, sourceValue, playlistId, startedBy) {
      setState(() {
        _musicPlaying = true;
        _musicSourceType = sourceType;
        _musicStartedBy = startedBy;
      });
      if (sourceType == 'upload') {
        final fullUrl = sourceValue.startsWith('http') ? sourceValue : '${AppConfig.serverBaseUrl}$sourceValue';
        _audioPlayer.play(UrlSource(fullUrl));
      } else if (sourceType == 'youtube') {
        // Loads OUR server's proxy page (not YouTube's URL directly) —
        // this is what fixes YouTube's "Error 153": that error happens
        // when YouTube's embed API sees an inconsistent/missing origin,
        // which a bare embed URL loaded with no surrounding page
        // triggers reliably. Our server's page has a real, consistent
        // origin, so YouTube accepts it.
        //
        // Passing playlist_id too (when present) is what makes the
        // player auto-advance through an entire playlist instead of
        // stopping after one video — matches YouTube's own native
        // playlist-autoplay behavior, no extra code needed on our side
        // beyond forwarding this ID into the embed URL.
        final params = <String, String>{'video_id': sourceValue};
        if (playlistId.isNotEmpty) params['playlist_id'] = playlistId;
        final embedUri = Uri.parse('${AppConfig.serverBaseUrl}/media/youtube_embed').replace(queryParameters: params);
        _playYoutube(embedUri.toString());
      }
    };
    _socket.onMusicStopped = () {
      setState(() {
        _musicPlaying = false;
        _musicSourceType = null;
        _musicStartedBy = null;
      });
      _audioPlayer.stop();
      if (_youtubeReady && !_closing) {
        _youtubeController?.loadRequest(Uri.parse('about:blank'));
      }
    };

    _socket.joinRoom(city: widget.roomName, username: widget.myUsername, pin: widget.pin);
  }

  /// webview_windows needs the SAME native plugin-registration patch as
  /// window_manager (see NATIVE_SETUP.md) to work inside this sub-window —
  /// without it, this throws and YouTube playback silently won't show.
  /// Wrapped in try/catch so a missing native patch degrades gracefully
  /// (upload-based music still works fine) instead of crashing this window.
  ///
  /// NOTE: the WebView2 autoplay-with-sound environment variable used to
  /// be set HERE, right before initialize() — moved to main.dart's very
  /// first line instead (see webview2_autoplay_fix.dart), since setting
  /// it this late may have been AFTER WebView2's shared browser
  /// environment was already created elsewhere in this process, at which
  /// point the flag has no effect anymore.
  Future<void> _initYoutubeController() async {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        // WKWebView (macOS) blocks inline/autoplay media by default unless
        // explicitly allowed — this is the macOS equivalent of the
        // WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS trick the Windows build
        // uses (see webview2_autoplay_fix.dart, NOT used in this macOS
        // build at all — that file is Windows-only FFI and isn't part of
        // this project).
        ..setBackgroundColor(const Color(0x00000000));
      // webview_flutter's WebViewController has no async initialize() step
      // (unlike webview_windows) — it's ready to use as soon as it's built.
      _youtubeController = controller;
      _youtubeInitialized = true; // from here on, _shutdown() must clean it up
      if (_closing || _disposed) return; // window is going away — don't show it
      if (mounted) setState(() => _youtubeReady = true);
    } catch (e) {
      _youtubeFailed = true;
      // ignore: avoid_print
      print('[RoomChat] webview_flutter unavailable: $e');
      if (mounted && !_closing && !_disposed) setState(() {});
    }
  }

  /// Creates + initializes the WebView2 player the first time it's needed
  /// (and only once). Safe to call repeatedly / concurrently.
  Future<void> _ensureYoutubePlayer() {
    if (_closing || _disposed) return Future.value();
    return _youtubeInit ??= _initYoutubeController();
  }

  Future<void> _playYoutube(String url) async {
    await _ensureYoutubePlayer();
    // The room may have stopped the music, or this window started
    // closing, while the player was still spinning up.
    if (!_youtubeReady || _closing || _disposed || _musicSourceType != 'youtube') return;
    try {
      await _youtubeController!.loadRequest(Uri.parse(url));
    } catch (e) {
      // ignore: avoid_print
      print('[RoomChat] loadUrl failed: $e');
    }
  }

  /// Ordered, awaited teardown of everything native this window owns.
  /// Idempotent — the close hook AND dispose() both call it, only the
  /// first call does anything.
  ///
  /// Order matters:
  ///   1. take the Webview widget out of the tree (so nothing is painting
  ///      into a texture we're about to free),
  ///   2. leave the room + drop the socket (no more callbacks),
  ///   3. stop/dispose audio,
  ///   4. WAIT for any in-flight WebView2 initialize() to finish, blank the
  ///      page (stops YouTube's iframe), then dispose the controller.
  /// Every step is individually guarded + time-boxed so one failure can't
  /// block the window from closing.
  Future<void> _shutdown() => _shutdownFuture ??= _doShutdown();

  Future<void> _doShutdown() async {
    final sw = Stopwatch()..start();
    void log(String step) {
      // ignore: avoid_print
      print('[RoomChat] shutdown +${sw.elapsedMilliseconds}ms: $step');
    }

    _closing = true;
    if (mounted && !_disposed) setState(() {});
    // Only worth waiting for a frame when a WebView2 is actually alive —
    // it's the Webview widget that has to leave the tree first.
    if (_youtubeInitialized) {
      try {
        await WidgetsBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 300));
      } catch (_) {}
    }

    try {
      _socket.leaveRoom();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 100)); // let the leave packet flush
    try {
      _socket.dispose();
    } catch (_) {}
    log('socket closed');

    // Audio: all players IN PARALLEL, each call capped at 800ms. It used to
    // be four sequential awaits capped at 2s each — if the audio plugin was
    // slow to answer, closing this window (e.g. on Logout) could hang for
    // up to 8 seconds while everything else had already closed.
    Future<void> releasePlayer(AudioPlayer player) async {
      try {
        await player.stop().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
      try {
        await player.dispose().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
    }

    try {
      await Future.wait<void>([
        releasePlayer(_audioPlayer),
        releasePlayer(_audiblePlayer),
      ]).timeout(const Duration(milliseconds: 1800));
    } catch (_) {
      // Timed out — carry on closing; the window must not wait on audio.
    }
    log('audio released');

    // WebView2 — only exists if a YouTube track was ever played here.
    if (_youtubeInit != null) {
      try {
        await _youtubeInit!.timeout(const Duration(seconds: 3));
      } catch (_) {}
      final controller = _youtubeController;
      if (controller != null && _youtubeInitialized) {
        try {
          await controller.loadRequest(Uri.parse('about:blank')).timeout(const Duration(seconds: 1));
        } catch (_) {}
        // webview_flutter's WebViewController has no dispose() to call —
        // its native platform view is torn down automatically once
        // WebViewWidget is removed from the widget tree (which happens
        // right after this, when the window itself closes).
      }
      log('webview released');
    }
    log('done');
  }

  /// Room Chat is resizable, unlike Login/Home — minimum 800x500. A room
  /// with several people needs the wider member-list layout; 400x680
  /// (briefly tried to "unify" with Login/Home) was too narrow and wrapped
  /// badly. No upper limit. Called from THIS window's own isolate
  /// (window_manager is registered here via the NATIVE_SETUP.md patch,
  /// same as the main window), unlike WindowLauncher's setFrame() which
  /// only sets the INITIAL size from the parent window's side.
  Future<void> _configureWindowSize() async {
    try {
      await windowManager.setMinimumSize(const Size(800, 500));
      await windowManager.setResizable(true);
    } catch (e) {
      // ignore: avoid_print
      print('[RoomChat] window_manager unavailable (native patch from NATIVE_SETUP.md not applied?): $e');
    }
  }

  Future<void> _loadOperators() async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/rooms/${widget.roomName}/roles').replace(queryParameters: {'viewer': widget.myUsername}),
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _myUid = (data['my_uid'] as num?)?.toInt();
          _myRole = data['my_role'] as String?;
          _canControlMusic = (data['can_control_music'] as bool?) ?? false;
          _operators = List<Map<String, dynamic>>.from(
            (data['operators'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
          _maxOperators = (data['max_operators'] as num?)?.toInt() ?? 5;
        });
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _assignOperator(int uid, String nickname) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/rooms/${widget.roomName}/operators/by-uid'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'assigned_by_username': widget.myUsername, 'target_uid': uid}),
      );
      if (res.statusCode == 200) {
        await _loadOperators();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$nickname sekarang jadi operator.')));
        }
      } else if (mounted) {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail'] ?? 'Gagal menambah operator.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  Future<void> _removeOperator(int uid, String nickname) async {
    try {
      final res = await http.delete(
        Uri.parse('$_apiBase/rooms/${widget.roomName}/operators/by-uid/$uid'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'removed_by_username': widget.myUsername}),
      );
      if (res.statusCode == 200) {
        await _loadOperators();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$nickname dihapus dari operator.')));
        }
      } else if (mounted) {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail'] ?? 'Gagal menghapus operator.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  /// Fetches the creator/operator's REAL friends list (same endpoint Home
  /// uses) and lets them pick one to invite — the invited friend can join
  /// this private room ONCE without needing the PIN (see backend's
  /// invite_to_room handler / rooms.has_invite).
  Future<void> _showInviteFriendDialog() async {
    List<String> friends = [];
    try {
      final res = await http.get(Uri.parse('$_apiBase/friends/${widget.myUsername}'));
      if (res.statusCode == 200) {
        friends = List<String>.from(jsonDecode(res.body)['friends']).map((f) => f.replaceFirst('@', '')).toList();
      }
    } catch (_) {
      // fall through to empty list — dialog will show "belum ada teman"
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Undang Teman ke Room'),
        content: SizedBox(
          width: 320,
          child: friends.isEmpty
              ? Text('Belum ada teman di daftar kamu. Tambah teman dulu lewat Home.', style: YmTextStyles.statusMessage)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final friend in friends)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 18),
                        title: Text('@$friend', style: YmTextStyles.chatText),
                        trailing: TextButton(
                          onPressed: () {
                            _socket.inviteToRoom(
                              inviterUsername: widget.myUsername,
                              targetUsername: friend,
                              city: widget.roomName,
                            );
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Undangan dikirim ke @$friend.')),
                            );
                          },
                          child: const Text('Undang'),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Tutup'))],
      ),
    );
  }

  void _showOperatorDialog() {
    // Candidates = people currently in the room who aren't already
    // creator/operator. Picked from the list — no typing a username, which
    // is no longer something you can (or should) know for a stranger.
    final candidates = _members.where((m) => m.role.isEmpty && !_isSelf(m)).toList();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kelola Operator Room'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Operator saat ini (${_operators.length}/$_maxOperators):', style: YmTextStyles.label),
              const SizedBox(height: 6),
              if (_operators.isEmpty)
                Text('Belum ada operator.', style: YmTextStyles.statusMessage)
              else
                for (final op in _operators)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.shield, size: 14, color: YmColors.accentPurple),
                      const SizedBox(width: 6),
                      Expanded(child: Text(op['nickname'] as String, style: YmTextStyles.chatText)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: YmColors.buzzRed),
                        tooltip: 'Hapus dari Operator',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _removeOperator((op['uid'] as num).toInt(), op['nickname'] as String);
                        },
                      ),
                    ]),
                  ),
              const SizedBox(height: 16),
              if (_operators.length >= _maxOperators)
                Text('Sudah mencapai batas maksimal $_maxOperators operator.', style: YmTextStyles.statusMessage)
              else ...[
                Text('Jadikan operator (yang sedang online):', style: YmTextStyles.label),
                const SizedBox(height: 6),
                if (candidates.isEmpty)
                  Text('Belum ada anggota lain di room.', style: YmTextStyles.statusMessage)
                else
                  SizedBox(
                    height: 140,
                    child: ListView(
                      children: [
                        for (final m in candidates)
                          Row(children: [
                            Expanded(child: Text(m.nickname, style: YmTextStyles.chatText, overflow: TextOverflow.ellipsis)),
                            TextButton(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                _assignOperator(m.uid, m.nickname);
                              },
                              child: const Text('Jadikan'),
                            ),
                          ]),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Tutup'))],
      ),
    );
  }

  /// Right-click (or long-press on touch) context menu for a member —
  /// "Jadikan Operator" only shows if I'm already creator/operator myself
  /// AND the target isn't already one.
  void _showMemberContextMenu(BuildContext tileContext, Offset position, _RoomMember member) {
    final isSelf = _isSelf(member);
    final isFriend = _isFriend(member);
    final alreadyOperator = member.role.isNotEmpty;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        // Private chat needs the other person's username, which you only
        // have once they're a friend — so it's offered for friends only.
        // Everyone else: add them as a friend first.
        if (!isSelf && isFriend)
          PopupMenuItem(
            child: const Text('Chat Pribadi'),
            onTap: () => _openPrivateChatWith(member),
          ),
        if (!isSelf && !isFriend)
          PopupMenuItem(
            child: const Text('Tambah Teman'),
            onTap: () => _sendFriendRequestTo(member),
          ),
        PopupMenuItem(
          child: const Text('Lihat Profil'),
          onTap: () => _showProfileOf(member),
        ),
        if (!isSelf && _canManageOperators && !alreadyOperator && _operators.length < _maxOperators)
          PopupMenuItem(
            child: const Text('Jadikan Operator'),
            onTap: () => _assignOperator(member.uid, member.nickname),
          ),
      ],
    );
  }

  /// Shows a choice: upload a file from this PC, or paste a YouTube link.
  /// Both are gated to creator/operator only (the button itself is hidden
  /// for everyone else, and the server double-checks on both paths).
  final _musicButtonKey = GlobalKey();

  void _showMusicSourceMenu() {
    // Posisi menu mengikuti tombol musiknya sendiri (bukan titik tetap
    // 100,100 yang lama — itu sebabnya menu muncul jauh di atas, tidak
    // nempel ke ikon musik). Tombolnya ada di toolbar paling bawah, jadi
    // tidak ada ruang di bawahnya — showMenu otomatis membalik menu ke
    // ATAS titik ini begitu ruang di bawah tidak cukup.
    final renderBox = _musicButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
    RelativeRect position = const RelativeRect.fromLTRB(100, 100, 0, 0); // fallback kalau key belum ter-render
    if (renderBox != null && overlayBox != null) {
      final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      position = RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlayBox.size.width - topLeft.dx - renderBox.size.width,
        overlayBox.size.height - topLeft.dy,
      );
    }
    showMenu(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(value: 'upload', child: Row(children: [
          Icon(Icons.upload_file, size: 18), SizedBox(width: 8), Text('Upload File dari PC'),
        ])),
        const PopupMenuItem(value: 'youtube', child: Row(children: [
          Icon(Icons.smart_display_outlined, size: 18), SizedBox(width: 8), Text('Dari Link YouTube'),
        ])),
      ],
    ).then((choice) {
      if (choice == 'upload') _pickAndUploadFile();
      if (choice == 'youtube') _showYoutubeLinkDialog();
    });
  }

  void _showYoutubeLinkDialog() {
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Putar dari YouTube'),
        content: TextField(
          controller: urlCtrl,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Link YouTube (video atau playlist)',
            hintText: 'https://youtube.com/watch?v=... atau .../playlist?list=...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () {
              final url = urlCtrl.text.trim();
              final videoId = _extractYoutubeVideoId(url);
              final playlistId = _extractYoutubePlaylistId(url);
              if (videoId == null && playlistId == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Link YouTube tidak valid.')),
                );
                return;
              }
              Navigator.of(dialogContext).pop();
              _socket.playMusic(
                city: widget.roomName,
                requesterUsername: widget.myUsername,
                sourceType: 'youtube',
                sourceValue: videoId ?? '',
                playlistId: playlistId ?? '',
              );
            },
            child: const Text('Putar'),
          ),
        ],
      ),
    );
  }

  /// Handles youtube.com/watch?v=, youtu.be/, and youtube.com/embed/ links.
  String? _extractYoutubeVideoId(String url) {
    final patterns = [
      RegExp(r'(?:youtube\.com/watch\?v=|youtube\.com/embed/|youtu\.be/)([a-zA-Z0-9_-]{11})'),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Handles both youtube.com/playlist?list=PLxxx AND
  /// youtube.com/watch?v=xxx&list=PLxxx (a video that's PART of a
  /// playlist) — this is what makes "autoplay the whole playlist, don't
  /// make me paste a new link for every song" work: giving either kind
  /// of link is enough to unlock playlist auto-advance.
  String? _extractYoutubePlaylistId(String url) {
    final match = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  Future<void> _pickAndUploadFile() async {
    setState(() => _uploadingMusic = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'ogg', 'm4a', 'flac'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      final uri = Uri.parse('$_apiBase/rooms/${widget.roomName}/music/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['uploader_username'] = widget.myUsername
        ..files.add(await http.MultipartFile.fromPath('file', path));

      final streamedResponse = await request.send();
      final res = await http.Response.fromStream(streamedResponse);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _socket.playMusic(
          city: widget.roomName,
          requesterUsername: widget.myUsername,
          sourceType: 'upload',
          sourceValue: data['file_url'],
        );
      } else {
        final data = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail'] ?? 'Gagal upload musik.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memutar musik: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingMusic = false);
    }
  }

  void _stopMusic() {
    _socket.stopMusic(city: widget.roomName, requesterUsername: widget.myUsername);
  }

  bool _sendingLocation = false;

  /// Bagikan lokasi GPS saat ini sebagai kartu kecil di chat room —
  /// diketuk untuk buka di Google Maps. Sama seperti fitur di private
  /// chat (chat_window_screen.dart), sekarang tersedia juga di room.
  Future<void> _sendLocation() async {
    setState(() => _sendingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Layanan lokasi sedang mati di sistem kamu.')),
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Izin lokasi ditolak.')));
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      _socket.sendMessage('$_locationPrefix${position.latitude},${position.longitude}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengambil lokasi: $e')));
      }
    } finally {
      if (mounted) setState(() => _sendingLocation = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _socket.sendMessage(text);
    _inputCtrl.clear();
    setState(() => _showEmoticons = false);
  }

  @override
  void dispose() {
    _disposed = true;
    WindowLauncher.beforeCloseHooks.remove(_shutdown);
    // Normally _shutdown() already ran (and finished) via the close hook,
    // making this a no-op. If the screen is torn down some other way,
    // the exact same ordered cleanup still happens — but async, since
    // dispose() itself can't await.
    _shutdown();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(BuddyStatus s) {
    switch (s) {
      case BuddyStatus.online: return YmColors.statusOnline;
      case BuddyStatus.busy: return YmColors.statusBusy;
      case BuddyStatus.invisible:
      case BuddyStatus.offline: return YmColors.statusOffline;
    }
  }

  String _statusLabel(BuddyStatus s) {
    switch (s) {
      case BuddyStatus.online: return 'Online';
      case BuddyStatus.busy: return 'Sibuk';
      case BuddyStatus.invisible: return 'Invisible';
      case BuddyStatus.offline: return 'Offline';
    }
  }

  /// "Admin Room" for the creator, "Operator Room" for operators, null for
  /// regular members — the role comes straight from the server's member list.
  String? _roleLabel(_RoomMember m) {
    if (m.role == 'creator') return 'Admin Room';
    if (m.role == 'operator') return 'Operator Room';
    return null;
  }

  IconData? _genderIcon(BuddyGender g) {    switch (g) {
      case BuddyGender.male: return Icons.male;
      case BuddyGender.female: return Icons.female;
      case BuddyGender.unspecified: return null;
    }
  }

  Color _genderColor(BuddyGender g) {
    switch (g) {
      case BuddyGender.male: return const Color(0xFF3B82F6);   // blue, like classic IM gender icons
      case BuddyGender.female: return const Color(0xFFEC4899); // pink
      case BuddyGender.unspecified: return YmColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RetroTitleBar(title: 'Room: ${widget.roomName}', icon: Icons.groups_rounded),

          // Now-playing bar — visible to everyone when music is active
          if (_musicPlaying)
            Column(
              children: [
                Container(
                  color: YmColors.accentPurple.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _musicSourceType == 'youtube' ? Icons.smart_display_outlined : Icons.music_note,
                        size: 16, color: YmColors.accentPurple,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Musik diputar oleh $_musicStartedBy', style: YmTextStyles.statusMessage)),
                      // Volume slider only applies to uploaded-file playback
                      // (audioplayers) — YouTube's embedded player has its
                      // own built-in volume control inside the video itself.
                      if (_musicSourceType == 'upload') ...[
                        const Icon(Icons.volume_down, size: 16, color: YmColors.textMuted),
                        SizedBox(
                          width: 100,
                          child: Slider(
                            value: _volume,
                            onChanged: (v) {
                              setState(() => _volume = v);
                              _audioPlayer.setVolume(v);
                            },
                            activeColor: YmColors.accentPurple,
                          ),
                        ),
                        const Icon(Icons.volume_up, size: 16, color: YmColors.textMuted),
                      ],
                      if (_canControlMusic)
                        IconButton(
                          icon: const Icon(Icons.stop_circle_outlined, size: 20, color: YmColors.buzzRed),
                          tooltip: 'Hentikan Musik',
                          onPressed: _stopMusic,
                        ),
                    ],
                  ),
                ),
                // YouTube playback — now shown VISIBLY with YouTube's own
                // native player chrome (play/pause, seek bar, volume),
                // instead of the earlier "hidden 1x1, audio-only" attempt.
                //
                // WHY THE CHANGE: browsers (and WebView2, which powers
                // this) block audio-with-autoplay unless there's a real
                // user click on that content. A hidden 1x1 player can
                // NEVER receive that click, so autoplay was reliably
                // silent no matter what. A VISIBLE player lets whoever's
                // looking at it just click YouTube's own play button —
                // that click IS the gesture the browser needs, and it
                // gives everyone a real seek bar / pause button for free
                // (YouTube's embed already has these; we don't have to
                // build our own). Needs webview_windows registered via
                // webview_flutter needs no native runner patch at all
                // (unlike webview_windows) — it just works once the
                // package is in pubspec.yaml.
                if (_musicSourceType == 'youtube')
                  SizedBox(
                    height: 220,
                    child: (_youtubeReady && !_closing)
                        ? WebViewWidget(controller: _youtubeController!)
                        : Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: Text(
                              _closing
                                  ? ''
                                  : (_youtubeFailed
                                      ? 'Player YouTube gagal dimuat.'
                                      : 'Menyiapkan player YouTube…'),
                              textAlign: TextAlign.center,
                              style: YmTextStyles.statusMessage,
                            ),
                          ),
                  ),
                if (_musicSourceType == 'youtube' && _youtubeReady)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text(
                      'Kalau belum ada suara, klik tombol play di video di atas sekali — browser butuh 1 klik langsung untuk mengizinkan suara autoplay.',
                      style: YmTextStyles.statusMessage,
                    ),
                  ),
              ],
            ),

          Expanded(
            child: Row(
              children: [
                // Chat stream
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          color: YmColors.panelBackground,
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(10),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final m = _messages[i];
                              if (m.sender == 'Sistem') {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Text(m.text, style: YmTextStyles.statusMessage),
                                );
                              }
                              final audible = decodeAudibleMessage(m.text);
                              if (m.text.startsWith(_locationPrefix)) {
                                final coords = m.text.substring(_locationPrefix.length);
                                final point = _parseCoordinates(coords);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(ymBorderRadius - 2),
                                    onTap: point == null ? null : () => _openInGoogleMaps(context, point),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${m.sender}: ',
                                          style: YmTextStyles.buddyName.copyWith(
                                            color: m.isMine ? YmColors.accentPurple : YmColors.textDark,
                                          ),
                                        ),
                                        const Icon(Icons.location_on, size: 18, color: YmColors.accentPurple),
                                        const SizedBox(width: 4),
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
                                                  style: TextStyle(fontSize: 10, color: YmColors.textMuted),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              if (audible != null) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${m.sender}: ',
                                        style: YmTextStyles.buddyName.copyWith(
                                          color: m.isMine ? YmColors.accentPurple : YmColors.textDark,
                                        ),
                                      ),
                                      Icon(audible.icon, size: 18, color: YmColors.accentPurple),
                                      const SizedBox(width: 6),
                                      Text(audible.label, style: YmTextStyles.chatText.copyWith(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: RichText(
                                  text: TextSpan(children: [
                                    TextSpan(
                                      text: '${m.sender}: ',
                                      style: YmTextStyles.buddyName.copyWith(
                                        color: m.isMine ? YmColors.accentPurple : YmColors.textDark,
                                      ),
                                    ),
                                    TextSpan(text: m.text, style: YmTextStyles.chatText),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Container(height: 1, color: YmColors.borderLavender),
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
                              icon: _sendingLocation
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: YmColors.accentPurple),
                                    )
                                  : const Icon(Icons.location_on_outlined, color: YmColors.accentPurple),
                              tooltip: 'Bagikan Lokasi',
                              onPressed: _sendingLocation ? null : _sendLocation,
                            ),
                            // Music button — visible to creator/operator, ATAU
                            // admin dinamis room default (lihat _canControlMusic).
                            // No image-attach button exists anywhere in this
                            // room screen on purpose — rooms don't support
                            // sharing images, only shared music.
                            if (_canControlMusic)
                              IconButton(
                                key: _musicButtonKey,
                                icon: _uploadingMusic
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Icon(Icons.music_note, color: _musicPlaying ? YmColors.buzzRed : YmColors.accentPurple),
                                tooltip: _musicPlaying ? 'Ganti Musik' : 'Putar Musik',
                                onPressed: _uploadingMusic ? null : _showMusicSourceMenu,
                              ),
                            Expanded(
                              child: Focus(
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                                    if (HardwareKeyboard.instance.isShiftPressed) {
                                      return KeyEventResult.ignored;
                                    }
                                    _sendMessage();
                                    return KeyEventResult.handled;
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
                                  decoration: const InputDecoration(
                                    hintText: 'Ketik pesan ke room... (Shift+Enter untuk baris baru)',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(icon: const Icon(Icons.send, color: YmColors.accentPurple), onPressed: _sendMessage),
                          ],
                        ),
                      ),
                      if (_showEmoticons)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: EmoticonPicker(
                            onPicked: (e) => setState(() => _inputCtrl.text += e),
                            // Sends immediately as its own message, like a
                            // reaction — NOT appended to the composer.
                            onAudiblePicked: (encoded) {
                              _socket.sendMessage(encoded);
                              setState(() => _showEmoticons = false);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Container(width: 1, color: YmColors.borderLavender),
                // Live user list
                SizedBox(
                  width: 200,
                  child: Container(
                    color: YmColors.contentBackground,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(child: Text('${_members.length} Orang Online', style: YmTextStyles.label)),
                              if (_canManageOperators)
                                IconButton(
                                  icon: const Icon(Icons.person_add_alt_1, size: 18, color: YmColors.accentPurple),
                                  tooltip: 'Undang Teman',
                                  onPressed: _showInviteFriendDialog,
                                ),
                              if (_canManageOperators)
                                IconButton(
                                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 18, color: YmColors.accentPurple),
                                  tooltip: 'Kelola Operator',
                                  onPressed: _showOperatorDialog,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _members.length,
                            itemBuilder: (context, i) {
                              final u = _members[i];
                              final genderIcon = _genderIcon(u.gender);
                              final role = _roleLabel(u);
                              return GestureDetector(
                                onSecondaryTapDown: (details) =>
                                    _showMemberContextMenu(context, details.globalPosition, u),
                                onLongPressStart: (details) =>
                                    _showMemberContextMenu(context, details.globalPosition, u),
                                child: InkWell(
                                  // No-op tap for your own row — clicking
                                  // your own name shouldn't open a private
                                  // chat with yourself. Right-click still
                                  // works for "Lihat Profil" (that item
                                  // stays available even for yourself).
                                  // Friend -> private chat. Stranger -> their
                                  // profile (where you can add them).
                                  onTap: _isSelf(u)
                                      ? null
                                      : () => _isFriend(u) ? _openPrivateChatWith(u) : _showProfileOf(u),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Titik status online DIHAPUS di sini: semua orang di
                                            // daftar anggota room ini sudah pasti online (kalau
                                            // tidak, dia tidak akan ada di daftar sama sekali) —
                                            // menampilkan titik "online" jadi berlebihan/mubazir.
                                            // Gender icon, with a small headphone
                                            // overlay badge if this user has
                                            // opted in to hearing room music —
                                            // classic-YM-style combined icon.
                                            if (genderIcon != null)
                                              Tooltip(
                                                message: u.hasSpeakerEnabled
                                                    ? '${u.gender == BuddyGender.male ? "Pria" : "Wanita"} \u2022 Speaker aktif'
                                                    : (u.gender == BuddyGender.male ? 'Pria' : 'Wanita'),
                                                child: SizedBox(
                                                  width: 18, height: 14,
                                                  child: Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      Icon(genderIcon, size: 14, color: _genderColor(u.gender)),
                                                      if (u.hasSpeakerEnabled)
                                                        const Positioned(
                                                          right: -2, bottom: -2,
                                                          child: Icon(Icons.headphones, size: 10, color: YmColors.accentPurple),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 4),
                                            Expanded(child: Text(u.nickname, style: YmTextStyles.buddyName, overflow: TextOverflow.ellipsis)),
                                            IconButton(
                                              icon: const Icon(Icons.info_outline, size: 14, color: YmColors.textMuted),
                                              tooltip: 'Lihat Profil',
                                              onPressed: () => _showProfileOf(u),
                                            ),
                                          ],
                                        ),
                                        // Role badge under the name — only
                                        // shown for the room creator/operators.
                                        if (role != null)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 22, top: 1),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: role == 'Admin Room' ? YmColors.buzzRed.withOpacity(0.12) : YmColors.accentPurple.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                role,
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: role == 'Admin Room' ? YmColors.buzzRed : YmColors.accentPurple,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
