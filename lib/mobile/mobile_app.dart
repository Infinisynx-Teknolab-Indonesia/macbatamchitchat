import 'package:flutter/material.dart';
import '../services/secure_storage_service.dart';
import '../theme/ym_theme.dart';
import 'mobile_login_screen.dart';
import 'mobile_notifier.dart';
import 'mobile_shell.dart';

class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Batam ChitChat',
      debugShowCheckedModeBanner: false,
      navigatorKey: MobileNotifier.navigatorKey, // dipakai banner notifikasi dari atas layar
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: YmColors.accentPurple,
        scaffoldBackgroundColor: YmColors.panelBackground,
      ),
      home: const _Startup(),
    );
  }
}

/// Sudah punya sesi tersimpan -> langsung ke aplikasi; kalau belum -> layar login.
class _Startup extends StatelessWidget {
  const _Startup();

  Future<String?> _savedUsername() async {
    final storage = SecureStorageService();
    final token = await storage.getSessionToken();
    final username = await storage.getUsername();
    if (token == null || token.isEmpty || username == null || username.isEmpty) return null;
    return username;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _savedUsername(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final username = snapshot.data;
        return username == null ? const MobileLoginScreen() : MobileShell(myUsername: username);
      },
    );
  }
}
