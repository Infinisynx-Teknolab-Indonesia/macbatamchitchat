import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';

const _apiBase = AppConfig.apiBaseUrl;

/// Profil orang yang BELUM berteman — dikenali hanya lewat `uid`.
///
/// Dari server, tampilan ini tidak pernah menerima username atau nomor
/// WhatsApp orang tersebut; itu baru terbuka setelah berteman (saat itu
/// aplikasi memakai UserProfileDialog biasa). Dari sini kamu bisa
/// mengirim permintaan pertemanan.
class PublicProfileDialog extends StatefulWidget {
  final int uid;
  final String viewerUsername;
  const PublicProfileDialog({super.key, required this.uid, required this.viewerUsername});

  @override
  State<PublicProfileDialog> createState() => _PublicProfileDialogState();
}

class _PublicProfileDialogState extends State<PublicProfileDialog> {
  Map<String, dynamic>? _profile;
  String? _error;
  bool _sending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/users/by-id/${widget.uid}/public-profile')
            .replace(queryParameters: {'viewer': widget.viewerUsername}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _profile = jsonDecode(res.body) as Map<String, dynamic>);
      } else {
        setState(() => _error = 'Profil tidak bisa dimuat.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Tidak bisa terhubung ke server.');
    }
  }

  Future<void> _sendRequest() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/friends/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'from_username': widget.viewerUsername, 'to_uid': widget.uid}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _sending = false;
          _profile?['relationship'] = 'request_sent';
        });
      } else {
        String message = 'Gagal mengirim permintaan.';
        try {
          message = jsonDecode(res.body)['detail']?.toString() ?? message;
        } catch (_) {}
        setState(() {
          _sending = false;
          _message = message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _message = 'Tidak bisa terhubung ke server.';
        });
      }
    }
  }

  Widget _action(String relationship) {
    switch (relationship) {
      case 'none':
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
          onPressed: _sending ? null : _sendRequest,
          icon: const Icon(Icons.person_add_alt_1, size: 16),
          label: Text(_sending ? 'Mengirim...' : 'Tambah Teman'),
        );
      case 'request_sent':
        return Text('Permintaan pertemanan sudah dikirim.', style: YmTextStyles.statusMessage);
      case 'request_received':
        return Text('Dia sudah mengirim permintaan ke kamu. Terima lewat menu Home.', style: YmTextStyles.statusMessage);
      case 'self':
        return Text('Ini kamu.', style: YmTextStyles.statusMessage);
      default:
        return Text('Tidak tersedia.', style: YmTextStyles.statusMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final name = ((p?['full_name'] as String?) ?? '').trim();
    final gender = p?['gender'];
    return AlertDialog(
      content: SizedBox(
        width: 300,
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.red))
            : p == null
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(photoUrl: p['photo_url'] as String?, radius: 36),
                      const SizedBox(height: 10),
                      Text(name.isEmpty ? 'Tanpa nama' : name, style: YmTextStyles.username.copyWith(fontSize: 16)),
                      if (gender == 'male' || gender == 'female')
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(gender == 'male' ? 'Pria' : 'Wanita', style: YmTextStyles.statusMessage),
                        ),
                      const SizedBox(height: 16),
                      _action((p['relationship'] as String?) ?? 'none'),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_message!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                    ],
                  ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup'))],
    );
  }
}
