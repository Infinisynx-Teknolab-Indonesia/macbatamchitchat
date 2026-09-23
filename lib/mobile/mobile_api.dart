import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/secure_storage_service.dart';
import 'models.dart';

class RecentData {
  final List<Conversation> conversations;
  final int totalUnread;
  const RecentData(this.conversations, this.totalUnread);
}

/// Panggilan REST yang butuh login (header Authorization: Bearer <token sesi>).
class MobileApi {
  static Future<Map<String, String>?> _headers() async {
    final token = await SecureStorageService().getSessionToken();
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// Percakapan terbaru + jumlah belum dibaca. null = gagal (offline / server lama).
  static Future<RecentData?> recent() async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final res = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/dm/recent'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final list = (data['conversations'] as List)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
      return RecentData(list, (data['total_unread'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// Tandai percakapan dengan [peer] sudah dibaca.
  static Future<void> markRead(String peer) async {
    try {
      final headers = await _headers();
      if (headers == null) return;
      await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/dm/read'),
            headers: headers,
            body: jsonEncode({'peer': peer}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Daftarkan token FCM perangkat ini ke server (untuk notifikasi push).
  static Future<bool> registerDevice(String token) async {
    try {
      final headers = await _headers();
      if (headers == null) return false;
      final res = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/devices/register'),
            headers: headers,
            body: jsonEncode({
              'token': token,
              'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
            }),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<void> unregisterDevice(String token) async {
    try {
      final headers = await _headers();
      if (headers == null) return;
      await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/devices/unregister'),
            headers: headers,
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Riwayat chat dengan [peer]. null = gagal.
  static Future<List<ChatEntry>?> history(String peer, String myUsername, {int limit = 100}) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;
      final res = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/dm/history')
                .replace(queryParameters: {'peer': peer, 'limit': '$limit'}),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body)['messages'] as List;
      return list.map((m) {
        final sender = m['sender'] as String;
        return ChatEntry(
          sender: sender,
          text: m['message'] as String,
          isMine: sender == myUsername,
          time: timeFromTs((m['ts'] as num).toDouble()),
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }
}
