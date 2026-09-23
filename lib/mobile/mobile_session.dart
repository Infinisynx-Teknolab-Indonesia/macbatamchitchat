import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../screens/complete_profile_screen.dart';
import '../services/secure_storage_service.dart';
import 'chat_hub.dart';
import 'mobile_login_screen.dart';
import 'mobile_shell.dart';
import 'push_service.dart';

/// Masuk / keluar akun di aplikasi mobile.
class MobileSession {
  /// Setelah login sukses: ke aplikasi utama, atau ke "lengkapi profil" untuk akun baru (Google / FJB).
  static void enter(BuildContext context, String username, {required bool profileComplete}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => profileComplete
            ? MobileShell(myUsername: username)
            : CompleteProfileScreen(username: username),
      ),
    );
  }

  /// Logout: beri tahu server (keluar dari semua room), hentikan koneksi, hapus sesi, kembali ke layar login.
  static Future<void> logout(BuildContext context) async {
    final storage = SecureStorageService();
    final username = await storage.getUsername();
    try {
      if (username != null && username.isNotEmpty) {
        await http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}/session/logout'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': username}),
            )
            .timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
    await PushService.stop(); // masih butuh token sesi: lepas perangkat ini dari akun
    ChatHub.instance.stop();
    await storage.clearSession();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MobileLoginScreen()),
        (route) => false,
      );
    }
  }
}
