import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:tray_manager/tray_manager.dart';
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import 'window_launcher.dart';
import 'secure_storage_service.dart';
import 'session_signal.dart';
import '../screens/login_screen.dart';

/// Shared by AppSidebar's "Logout" drawer item AND TrayService's tray-menu
/// "Logout" item — one place for the confirm dialog + actual logout
/// sequence (close all spawned windows, clear session, navigate to Login)
/// so both entry points behave identically.
Future<void> performLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Logout'),
      content: const Text('Yakin mau logout?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Batal')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: YmColors.buzzRed, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Logout'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  // Tell the SERVER first, so it drops this user out of every room right
  // away. Otherwise a Room Chat window that is slow (or fails) to close
  // stays counted as online, and the same user can't re-enter that room
  // ("1/100 online" with nobody there). Best-effort: logout must never
  // get stuck on the network, so it's capped at 3 seconds.
  try {
    final username = await SecureStorageService().getUsername();
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

  // Jalur UTAMA: sinyal logout lewat file, dibaca semua window (tidak bergantung pada pesan antar-window).
  // Jalur lama (pesan 'force_close') tetap dijalankan sesudahnya sebagai cadangan.
  // ignore: avoid_print
  print('[logout] window yang terdaftar di window utama: ${WindowLauncher.globalWindowRegistry}');
  // Catat dulu: closeAllSpawnedWindows() mengosongkan daftar ini.
  final spawnedIds = WindowLauncher.globalWindowRegistry.toList();
  await SessionSignal.markLoggedOut();
  await WindowLauncher.closeAllSpawnedWindows();
  await SecureStorageService().clearSession();
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // Jaring pengaman: pastikan window-window itu benar-benar sudah hilang.
  await _pastikanWindowTertutup(spawnedIds);
}

/// Menunggu (maks. 10 detik) sampai semua window anak di [ids] benar-benar hilang. Kalau masih ada
/// yang hidup, penutupan lewat pesan/sinyal gagal -> aplikasi dimulai ulang. Semua window berjalan di
/// SATU proses, jadi keluar dari proses ini pasti menutup semuanya; instance baru langsung tampil di
/// layar Login (sesi sudah dihapus di atas).
Future<void> _pastikanWindowTertutup(List<int> registered) async {
  // Selain yang terdaftar, periksa juga id di sekitarnya (id window anak berurutan mulai dari 1):
  // window yang gagal mendaftar ke window utama tetap ikut terdeteksi.
  final maxId = registered.isEmpty ? 0 : registered.reduce((a, b) => a > b ? a : b);
  final ids = <int>{...registered, for (var i = 1; i <= maxId + 8; i++) i}.toList();
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  var alive = await WindowLauncher.aliveAmong(ids);
  while (alive.isNotEmpty && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 500));
    alive = await WindowLauncher.aliveAmong(alive);
  }
  if (alive.isEmpty) return;
  // ignore: avoid_print
  print('[logout] window ini masih hidup setelah logout: $alive -> aplikasi dimulai ulang');
  await _mulaiUlangAplikasi();
}

Future<void> _mulaiUlangAplikasi() async {
  try {
    await Process.start(Platform.resolvedExecutable, const <String>[], mode: ProcessStartMode.detached);
  } catch (e) {
    // ignore: avoid_print
    print('[logout] gagal memulai ulang aplikasi: $e');
    return; // instance baru gagal dibuat: jangan keluar, biarkan aplikasi tetap hidup
  }
  try {
    await trayManager.destroy(); // supaya ikon tray lama tidak tertinggal
  } catch (_) {}
  exit(0);
}
