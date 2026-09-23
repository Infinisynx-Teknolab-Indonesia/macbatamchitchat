import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../services/friend_directory_service.dart';
import '../services/socket_service.dart';
import 'mobile_api.dart';
import 'mobile_notifier.dart';
import 'models.dart';

/// Satu pesan yang lewat di socket (masuk atau echo dari pesan yang saya kirim).
class HubMessage {
  final String peer; // lawan bicara
  final String sender;
  final String text;
  final DateTime time;
  final bool isMine;
  const HubMessage({
    required this.peer,
    required this.sender,
    required this.text,
    required this.time,
    required this.isMine,
  });
}

/// Pusat chat privat untuk seluruh aplikasi mobile: SATU koneksi socket, daftar percakapan, jumlah belum dibaca
/// (badge), dan notifikasi banner/suara/getar saat pesan atau Buzz masuk. Layar-layar hanya mendengarkan hub ini.
class ChatHub extends ChangeNotifier {
  ChatHub._();
  static final ChatHub instance = ChatHub._();

  SocketService? _socket;
  String? myUsername;
  List<Conversation> conversations = [];
  int totalUnread = 0;

  /// Percakapan yang sedang terbuka di layar (pesan yang masuk di sana langsung dianggap dibaca).
  String? activePeer;
  bool appInForeground = true;

  /// Bertambah setiap ada permintaan pertemanan baru (tab Friends memuat ulang saat berubah).
  int friendRequestTick = 0;

  final StreamController<HubMessage> _messages = StreamController<HubMessage>.broadcast();
  final StreamController<String> _buzzes = StreamController<String>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  Stream<HubMessage> get messages => _messages.stream;

  /// Username pengirim Buzz yang diterima SELAGI chat dengannya terbuka (layar chat menggetarkan diri).
  Stream<String> get buzzes => _buzzes.stream;
  Stream<String> get errors => _errors.stream;

  /// Diisi MobileShell.
  void Function(String reason)? onForceLogout;
  void Function(String peer)? openChat;

  Future<void> start(String username) async {
    if (_socket != null && myUsername == username) return;
    if (_socket != null) stop();
    myUsername = username;
    _socket = SocketService(
      onConnected: () {
        // Daftarkan kehadiran di setiap (re)connect: setelah sinyal hilang, server memberi id koneksi baru.
        _socket?.registerPresence(username);
        refresh();
      },
      onDirectMessageReceived: (sender, message, ts) => _onIncoming(sender, message, ts),
      onDirectMessageSent: (recipient, message, ts) => _onSent(recipient, message, ts),
      onFriendRequestReceived: (requestId, fromName) => _onFriendRequest(fromName),
      onForceLogout: (reason) => onForceLogout?.call(reason),
      onError: (message) => _errors.add(message),
    )..connect(AppConfig.socketUrl);
    _socket!.registerPresence(username);
    await refresh();
  }

  void stop() {
    _socket?.dispose();
    _socket = null;
    myUsername = null;
    conversations = [];
    totalUnread = 0;
    activePeer = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final data = await MobileApi.recent();
    if (data == null) return;
    conversations = data.conversations;
    totalUnread = data.totalUnread;
    notifyListeners();
  }

  // ------------------------------------------------------------------ mengirim
  void sendMessage(String peer, String text) {
    final me = myUsername;
    if (me == null || text.isEmpty) return;
    _socket?.sendDirectMessage(senderUsername: me, recipientUsername: peer, message: text);
  }

  void sendBuzz(String peer) {
    final me = myUsername;
    if (me == null) return;
    _socket?.buzz(requesterUsername: me, targetUsername: peer);
  }

  // ------------------------------------------------------------------ status baca
  void markRead(String peer) {
    final i = conversations.indexWhere((c) => c.peerUsername == peer);
    if (i >= 0 && conversations[i].unread > 0) {
      conversations[i] = conversations[i].copyWith(unread: 0);
      _recount();
      notifyListeners();
    }
    MobileApi.markRead(peer);
  }

  String? displayNameFor(String peer) {
    final i = conversations.indexWhere((c) => c.peerUsername == peer);
    return (i >= 0 && conversations[i].hasRealName) ? conversations[i].displayName : null;
  }

  // ------------------------------------------------------------------ event masuk
  Future<void> _onIncoming(String sender, String message, double ts) async {
    final time = timeFromTs(ts);
    final isBuzz = message == buzzMarker;
    _messages.add(HubMessage(peer: sender, sender: sender, text: message, time: time, isMine: false));

    final viewing = activePeer == sender && appInForeground;
    _touch(sender, previewOf(message), time, isMine: false, unreadDelta: viewing ? 0 : 1);
    if (viewing) {
      MobileApi.markRead(sender);
      if (isBuzz) {
        _buzzes.add(sender);
        MobileNotifier.playBuzzSound();
        MobileNotifier.vibrateBuzz();
      } else {
        MobileNotifier.playMessageSound();
      }
      return;
    }
    // Aplikasi di latar belakang: notifikasi datang dari push FCM (tahap berikutnya), bukan dari sini.
    if (!appInForeground) return;

    final title = await _titleFor(sender);
    MobileNotifier.showBanner(
      title: isBuzz ? '⚡ $title mengirim Buzz!' : title,
      body: isBuzz ? 'Ketuk untuk membalas' : previewOf(message),
      buzz: isBuzz,
      onTap: () => openChat?.call(sender),
    );
  }

  void _onSent(String recipient, String message, double ts) {
    final me = myUsername;
    if (me == null) return;
    final time = timeFromTs(ts);
    _messages.add(HubMessage(peer: recipient, sender: me, text: message, time: time, isMine: true));
    _touch(recipient, previewOf(message), time, isMine: true, unreadDelta: 0, clearUnread: true);
  }

  void _onFriendRequest(String fromName) {
    friendRequestTick++;
    notifyListeners();
    if (appInForeground) {
      MobileNotifier.showBanner(
        title: 'Permintaan pertemanan',
        body: '$fromName ingin berteman denganmu',
        onTap: () {},
      );
    }
  }

  // ------------------------------------------------------------------ util
  Future<String> _titleFor(String peer) async {
    final known = displayNameFor(peer);
    if (known != null) return known;
    final fetched = await FriendDirectoryService().fetchDisplayName(peer);
    return fetched ?? '@$peer';
  }

  void _touch(String peer, String preview, DateTime time,
      {required bool isMine, required int unreadDelta, bool clearUnread = false}) {
    final i = conversations.indexWhere((c) => c.peerUsername == peer);
    if (i >= 0) {
      final old = conversations.removeAt(i);
      conversations.insert(
        0,
        old.copyWith(
          lastMessage: preview,
          lastTime: time,
          lastIsMine: isMine,
          unread: clearUnread ? 0 : old.unread + unreadDelta,
        ),
      );
    } else {
      conversations.insert(
        0,
        Conversation(
          peerUsername: peer,
          lastMessage: preview,
          lastTime: time,
          lastIsMine: isMine,
          unread: clearUnread ? 0 : unreadDelta,
        ),
      );
      refresh(); // percakapan baru: ambil nama/fotonya dari server
    }
    _recount();
    notifyListeners();
  }

  void _recount() {
    totalUnread = conversations.fold<int>(0, (sum, c) => sum + c.unread);
  }
}
