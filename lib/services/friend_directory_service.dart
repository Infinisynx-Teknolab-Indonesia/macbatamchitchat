import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'secure_storage_service.dart';

/// Satu teman di daftar teman saya.
class FriendInfo {
  final String username;
  final String? nickname; // nama publik dia (nickname)
  final String? alias; // nama panggilan PRIBADI yang saya beri (hanya saya yang melihat)
  final String? photoUrl;
  final String status; // 'online' | 'busy' | 'invisible-tapi-tampil-offline' | 'offline'
  const FriendInfo({required this.username, this.nickname, this.alias, this.photoUrl, this.status = 'offline'});

  bool get hasAlias => alias != null && alias!.isNotEmpty;
  bool get hasNickname => nickname != null && nickname!.isNotEmpty;

  /// Nama yang tampil: nama panggilan pribadi > nickname > @username.
  String get displayName => hasAlias ? alias! : (hasNickname ? nickname! : '@$username');

  factory FriendInfo.fromJson(Map<String, dynamic> j) => FriendInfo(
        username: j['username'] as String,
        nickname: j['nickname'] as String?,
        alias: j['alias'] as String?,
        photoUrl: j['photo_url'] as String?,
        status: (j['status'] as String?) ?? 'offline',
      );
}

/// Nama teman + nama panggilan pribadi (endpoint backend: app/friend_alias.py).
class FriendDirectoryService {
  Future<Map<String, String>?> _headers() async {
    final token = await SecureStorageService().getSessionToken();
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// Daftar teman lengkap dengan nickname + nama panggilan.
  /// null = gagal (mis. backend belum diperbarui): pemanggil memakai cara lama.
  Future<List<FriendInfo>?> fetchFriends() async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final res = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/friend-list'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body)['friends'] as List;
      return list.map((e) => FriendInfo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Atur nama panggilan; [alias] kosong = hapus. Mengembalikan null jika berhasil, atau pesan error.
  Future<String?> setAlias(String friendUsername, String alias) async {
    try {
      final headers = await _headers();
      if (headers == null) return 'Sesi tidak ditemukan. Silakan login ulang.';
      final res = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/friend-alias'),
            headers: headers,
            body: jsonEncode({'friend_username': friendUsername, 'alias': alias}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return null;
      try {
        final detail = jsonDecode(res.body)['detail'];
        if (detail is String) return detail;
      } catch (_) {}
      return 'Gagal menyimpan (${res.statusCode}).';
    } catch (_) {
      return 'Tidak bisa terhubung ke server.';
    }
  }

  /// Nama yang harus tampil untuk [peer] (nama panggilan jika teman & sudah dinamai, kalau tidak
  /// nickname). null = tidak ada nama: tampilkan @username.
  Future<String?> fetchDisplayName(String peer) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final res = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/display-name/${Uri.encodeComponent(peer)}'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final name = jsonDecode(res.body)['display_name'];
      return (name is String && name.isNotEmpty) ? name : null;
    } catch (_) {
      return null;
    }
  }
}
