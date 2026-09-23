import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import '../screens/complete_profile_screen.dart';
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';
import 'mobile_session.dart';
import 'push_service.dart';

/// Tab "Profile": identitas, lengkapi profil (nickname), info aplikasi, logout.
class ProfileTab extends StatefulWidget {
  final String myUsername;
  const ProfileTab({super.key, required this.myUsername});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String? _nickname;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/users/${widget.myUsername}/profile')
            .replace(queryParameters: {'viewer': widget.myUsername}),
      );
      if (!mounted) return;
      setState(() {
        _version = '${info.version}+${info.buildNumber}';
        if (res.statusCode == 200) {
          final name = ((jsonDecode(res.body)['full_name'] as String?) ?? '').trim();
          _nickname = name.isEmpty ? null : name;
        }
      });
    } catch (_) {}
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
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
    if (ok == true && mounted) await MobileSession.logout(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: UserAvatar(username: widget.myUsername, viewer: widget.myUsername, radius: 44)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _nickname ?? 'Belum ada nickname',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: YmColors.textDark),
          ),
        ),
        Center(
          child: Text('@${widget.myUsername}', style: const TextStyle(fontSize: 13, color: YmColors.textMuted)),
        ),
        const SizedBox(height: 20),
        if (_nickname == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined, color: YmColors.accentPurple),
              title: const Text('Buat nickname'),
              subtitle: const Text('Diperlukan untuk masuk ke room.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CompleteProfileScreen(username: widget.myUsername)),
              ),
            ),
          ),
        Card(
          child: ValueListenableBuilder<String>(
            valueListenable: PushService.status,
            builder: (context, status, _) => ListTile(
              leading: const Icon(Icons.notifications_active_outlined, color: YmColors.accentPurple),
              title: const Text('Notifikasi'),
              subtitle: Text('Pesan dan Buzz muncul sebagai banner dari atas layar, lengkap dengan suara dan getar.\n'
                  '$status'),
              isThreeLine: true,
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline, color: YmColors.accentPurple),
            title: const Text('Batam ChitChat'),
            subtitle: Text('Versi $_version\nServer: ${AppConfig.serverBaseUrl}'),
            isThreeLine: true,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: YmColors.buzzRed,
            side: const BorderSide(color: YmColors.buzzRed),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
        ),
      ],
    );
  }
}
