import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';

/// Call before letting someone create/join a room. Returns true when the
/// user already has a nickname, or just created one in the dialog this
/// shows; false if they cancelled.
///
/// Network problems return true on purpose: this gate is a convenience,
/// not the security boundary — if the server is unreachable the join
/// itself will fail with its own, more accurate error message.
Future<bool> ensureNickname(BuildContext context, String username) async {
  try {
    final res = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/users/$username/profile').replace(
        queryParameters: {'viewer': username},
      ),
    );
    if (res.statusCode != 200) return true;
    final name = ((jsonDecode(res.body)['full_name'] as String?) ?? '').trim();
    if (name.isNotEmpty) return true;
  } catch (_) {
    return true;
  }

  if (!context.mounted) return false;
  final created = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NicknameDialog(username: username),
  );
  return created == true;
}

class _NicknameDialog extends StatefulWidget {
  final String username;
  const _NicknameDialog({required this.username});

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nickname = _ctrl.text.trim();
    if (nickname.length < 2) {
      setState(() => _error = 'Nickname minimal 2 karakter.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await http.patch(
        Uri.parse('${AppConfig.apiBaseUrl}/users/${widget.username}/privacy'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'full_name': nickname}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.of(context).pop(true);
      } else {
        String message = 'Gagal menyimpan nickname.';
        try {
          message = jsonDecode(res.body)['detail']?.toString() ?? message;
        } catch (_) {}
        setState(() {
          _saving = false;
          _error = message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Tidak bisa terhubung ke server.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buat Nickname Dulu'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kamu perlu punya nickname sebelum masuk room chat. '
              'Nickname hanya bisa dibuat sekali dan tidak bisa diganti setelahnya.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: 24,
              enabled: !_saving,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Nickname',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Simpan & Lanjut'),
        ),
      ],
    );
  }
}
