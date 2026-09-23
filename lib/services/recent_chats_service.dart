import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class RecentChatInfo {
  final String peerUsername;
  final String? displayName; // alias atau nickname; null -> tampilkan @username
  final String? photoUrl;
  final String lastMessage;
  final double lastTs;
  final bool lastIsMine;
  final int unread;

  RecentChatInfo({
    required this.peerUsername,
    required this.displayName,
    required this.photoUrl,
    required this.lastMessage,
    required this.lastTs,
    required this.lastIsMine,
    required this.unread,
  });

  factory RecentChatInfo.fromJson(Map<String, dynamic> j) => RecentChatInfo(
        peerUsername: j['peer_username'] as String,
        displayName: j['display_name'] as String?,
        photoUrl: j['photo_url'] as String?,
        lastMessage: (j['last_message'] as String?) ?? '',
        lastTs: (j['last_ts'] as num?)?.toDouble() ?? 0,
        lastIsMine: (j['last_is_mine'] as bool?) ?? false,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );

  String get timeLabel {
    final dt = DateTime.fromMillisecondsSinceEpoch((lastTs * 1000).round());
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
}

/// Wraps GET/POST /api/dm/recent dan /api/dm/read (app/mobile_chat.py) —
/// endpoint YANG SAMA dipakai aplikasi mobile untuk badge unread & preview
/// pesan terakhir, dipakai ulang di sini untuk Recent Chats di Home.
///
/// Endpoint itu memakai skema auth "Authorization: Bearer
/// demo-session-token-for-<username>" (bukan username biasa di body/query
/// seperti endpoint lain di app ini) — server belum punya token
/// sungguhan, jadi ini sekadar mengikuti skema yang sudah dipakai mobile,
/// bukan keamanan nyata (sama seperti sisa app ini pre-JWT).
class RecentChatsService {
  static const _apiBase = AppConfig.apiBaseUrl;

  static Map<String, String> _authHeaders(String myUsername) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer demo-session-token-for-$myUsername',
      };

  static Future<({List<RecentChatInfo> conversations, int totalUnread})?> fetchRecent(String myUsername) async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/dm/recent'),
        headers: _authHeaders(myUsername),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['conversations'] as List)
          .map((e) => RecentChatInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      return (conversations: list, totalUnread: (data['total_unread'] as num?)?.toInt() ?? 0);
    } catch (e) {
      // ignore: avoid_print
      print('[RecentChatsService] fetchRecent gagal: $e');
      return null;
    }
  }

  /// Panggil saat jendela private chat dengan [peer] dibuka/difokuskan,
  /// supaya badge unread-nya hilang.
  static Future<void> markRead(String myUsername, String peer) async {
    try {
      await http.post(
        Uri.parse('$_apiBase/dm/read'),
        headers: _authHeaders(myUsername),
        body: jsonEncode({'peer': peer}),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[RecentChatsService] markRead gagal: $e');
    }
  }

  /// Hapus percakapan dengan [peer] dari Recent Chats MILIK SENDIRI (lihat
  /// app/mobile_chat.py's DmHidden) — riwayat pesan aslinya tidak
  /// terhapus, dan percakapan otomatis muncul lagi begitu ada pesan baru.
  static Future<bool> hideConversation(String myUsername, String peer) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/dm/hide'),
        headers: _authHeaders(myUsername),
        body: jsonEncode({'peer': peer}),
      );
      return res.statusCode == 200;
    } catch (e) {
      // ignore: avoid_print
      print('[RecentChatsService] hideConversation gagal: $e');
      return false;
    }
  }
}
