import 'package:flutter/material.dart';
import '../services/friend_directory_service.dart';
import '../theme/ym_theme.dart';

/// Dialog "Nama panggilan" untuk seorang teman. Mengembalikan true kalau ada yang berubah
/// (disimpan atau dihapus), supaya pemanggil memuat ulang daftar teman.
Future<bool> showFriendAliasDialog(BuildContext context, FriendInfo friend) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FriendAliasDialog(friend: friend),
  );
  return changed ?? false;
}

class _FriendAliasDialog extends StatefulWidget {
  final FriendInfo friend;
  const _FriendAliasDialog({required this.friend});

  @override
  State<_FriendAliasDialog> createState() => _FriendAliasDialogState();
}

class _FriendAliasDialogState extends State<_FriendAliasDialog> {
  final _service = FriendDirectoryService();
  late final TextEditingController _ctrl = TextEditingController(text: widget.friend.alias ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await _service.setAlias(widget.friend.username, remove ? '' : _ctrl.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    return AlertDialog(
      title: const Text('Nama panggilan'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(friend.hasNickname ? 'Nama asli: ${friend.nickname}' : friend.displayName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'Nama ini hanya terlihat olehmu. Temanmu tidak diberi tahu dan akunnya tidak berubah.',
                style: TextStyle(fontSize: 12, color: YmColors.textMuted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                autofocus: true,
                enabled: !_busy,
                maxLength: 24,
                onSubmitted: (_) => _busy ? null : _save(),
                decoration: const InputDecoration(
                  labelText: 'Nama panggilan',
                  hintText: 'Kosongkan untuk memakai nama asli',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!, style: const TextStyle(color: YmColors.buzzRed, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (friend.hasAlias)
          TextButton(onPressed: _busy ? null : () => _save(remove: true), child: const Text('Hapus')),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Batal')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
