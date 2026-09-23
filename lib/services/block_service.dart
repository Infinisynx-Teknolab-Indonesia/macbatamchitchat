import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Wraps the server's POST/DELETE /api/block endpoints (see app/rooms.py).
/// Blocking is one-directional: [blocker] blocking [target] stops [target]'s
/// DMs to [blocker] (enforced server-side in app/sockets.py), independent of
/// whether they're friends.
class BlockService {
  static const _apiBase = AppConfig.apiBaseUrl;

  static Future<bool> block({required String blocker, required String target}) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/block'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'blocker_username': blocker, 'blocked_username': target}),
      );
      return res.statusCode == 200;
    } catch (e) {
      // ignore: avoid_print
      print('[BlockService] block gagal: $e');
      return false;
    }
  }

  static Future<bool> unblock({required String blocker, required String target}) async {
    try {
      final res = await http.delete(
        Uri.parse('$_apiBase/block'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'blocker_username': blocker, 'blocked_username': target}),
      );
      return res.statusCode == 200;
    } catch (e) {
      // ignore: avoid_print
      print('[BlockService] unblock gagal: $e');
      return false;
    }
  }

  /// Konfirmasi lewat dialog, lalu blokir kalau disetujui. Dipakai dari
  /// tempat mana pun tombol "Blokir" muncul (daftar teman, private chat).
  static Future<void> confirmAndBlock(
    BuildContext context, {
    required String myUsername,
    required String targetUsername,
    VoidCallback? onBlocked,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Blokir pengguna?'),
        content: Text(
          '@$targetUsername tidak akan bisa mengirim pesan pribadi ke kamu lagi. '
          'Kamu bisa membuka blokir kapan saja lewat Pengaturan > Daftar Blokir.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Blokir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await block(blocker: myUsername, target: targetUsername);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '@$targetUsername diblokir.' : 'Gagal memblokir, coba lagi.')),
    );
    if (ok) onBlocked?.call();
  }
}
