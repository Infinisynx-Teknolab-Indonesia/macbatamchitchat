import 'dart:convert';
import '../config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';

const _apiBase = AppConfig.apiBaseUrl;

/// Contact details popup — a SEPARATE action from opening a chat (see the
/// dedicated info icon in room_chat_screen.dart / home_screen.dart;
/// tapping a name itself opens a private chat window instead).
///
/// Fetches real data from the backend's privacy-aware profile endpoint:
/// email/birth_date only show up if [viewerUsername] is friends with
/// [username] AND the profile owner has that field's visibility turned on
/// in their own Settings — being friends alone isn't enough. Designed to
/// grow more fields later (avatar, buddy list, etc.) without changing this
/// contract.
class UserProfileDialog extends StatefulWidget {
  final String username;
  final String viewerUsername;
  const UserProfileDialog({super.key, required this.username, required this.viewerUsername});

  @override
  State<UserProfileDialog> createState() => _UserProfileDialogState();
}

class _UserProfileDialogState extends State<UserProfileDialog> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/${widget.username}/profile').replace(
        queryParameters: {'viewer': widget.viewerUsername},
      ));
      if (res.statusCode == 200) {
        setState(() {
          _profile = jsonDecode(res.body);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat profil.';
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Tidak bisa terhubung ke server.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ymBorderRadius)),
      child: SizedBox(
        width: 360,
        height: 380,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [YmColors.titleBarStart, YmColors.titleBarEnd]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(ymBorderRadius)),
              ),
              child: Row(
                children: [
                  // Real photo once the profile has loaded; the default
                  // "no photo" person icon before that / if they have none.
                  UserAvatar(
                    photoUrl: _profile?['photo_url'] as String?,
                    radius: 26,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${widget.username}', style: YmTextStyles.appTitle.copyWith(fontSize: 12)),
                        if (_profile != null)
                          Text(
                            _profile!['is_friend'] == true ? 'Teman' : 'Bukan teman',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: YmTextStyles.statusMessage))
                      : _buildInfo(),
            ),
          ],
        ),
      ),
    );
  }

  String _genderLabel(dynamic gender) {
    switch (gender) {
      case 'male': return 'Pria';
      case 'female': return 'Wanita';
      default: return '-';
    }
  }

  Widget _buildInfo() {
    final profile = _profile!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoRow(label: 'Nama Lengkap', value: profile['full_name'] ?? '-'),
        _InfoRow(label: 'Gender', value: _genderLabel(profile['gender'])),
        _InfoRow(
          label: 'Email',
          value: profile['email'] ?? '',
          hidden: profile['email_hidden'] == true,
        ),
        _InfoRow(
          label: 'Tanggal Lahir',
          value: profile['birth_date'] ?? '',
          hidden: profile['birthdate_hidden'] == true,
        ),
        _InfoRow(
          label: 'No. WhatsApp',
          value: profile['whatsapp_number'] ?? '',
          hidden: profile['whatsapp_hidden'] == true,
        ),
        _InfoRow(
          label: 'Alamat',
          value: profile['address'] ?? '',
          hidden: profile['address_hidden'] == true,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool hidden;
  const _InfoRow({required this.label, required this.value, this.hidden = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: YmTextStyles.label)),
          Expanded(
            child: hidden
                ? Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 14, color: YmColors.textMuted),
                      const SizedBox(width: 4),
                      Text('Disembunyikan', style: YmTextStyles.statusMessage),
                    ],
                  )
                : Text(value.isEmpty ? '-' : value, style: YmTextStyles.chatText),
          ),
        ],
      ),
    );
  }
}
