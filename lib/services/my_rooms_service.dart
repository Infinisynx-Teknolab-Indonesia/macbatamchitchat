import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class MyRoomInfo {
  final String name;
  final int onlineCount;
  final bool isDefault;
  final bool isCreator;
  MyRoomInfo({required this.name, required this.onlineCount, required this.isDefault, required this.isCreator});

  factory MyRoomInfo.fromJson(Map<String, dynamic> j) => MyRoomInfo(
        name: j['name'] as String,
        onlineCount: (j['online_count'] as num?)?.toInt() ?? 0,
        isDefault: (j['is_default'] as bool?) ?? false,
        isCreator: (j['is_creator'] as bool?) ?? false,
      );
}

/// Wraps GET /api/users/{username}/my-rooms (app/rooms.py) — room yang
/// user buat sendiri, dan room yang pernah dia masuki (RoomMembership,
/// dicatat sekali saat join, bukan status online sekarang).
class MyRoomsService {
  static const _apiBase = AppConfig.apiBaseUrl;

  static Future<({MyRoomInfo? created, List<MyRoomInfo> joined})?> fetch(String myUsername) async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/$myUsername/my-rooms'));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (
        created: data['created'] != null ? MyRoomInfo.fromJson(data['created'] as Map<String, dynamic>) : null,
        joined: (data['joined'] as List).map((e) => MyRoomInfo.fromJson(e as Map<String, dynamic>)).toList(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[MyRoomsService] fetch gagal: $e');
      return null;
    }
  }
}
