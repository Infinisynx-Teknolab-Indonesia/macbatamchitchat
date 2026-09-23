import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';

const _apiBase = AppConfig.apiBaseUrl;

/// Search-and-add-friend, as a dialog launched from Home.
///
/// Search modes:
///   - "@something" -> exact USERNAME match (for people who know it)
///   - "a@b.c"       -> exact EMAIL match
///   - anything else -> NICKNAME (full_name) search, can return several
///     people since nicknames aren't unique — shown as a pick-list.
class AddFriendDialog extends StatefulWidget {
  final String myUsername;
  const AddFriendDialog({super.key, required this.myUsername});

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<Map<String, dynamic>>? _results; // null = no search performed yet

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _results = null;
    });
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/find').replace(queryParameters: {'query': query, 'exclude_username': widget.myUsername}));
      if (!mounted) return;
      final data = jsonDecode(res.body);
      final results = List<Map<String, dynamic>>.from(data['results'])
          .where((u) => u['username'] != widget.myUsername) // can't friend yourself
          .toList();
      setState(() {
        _searching = false;
        _results = results;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _searching = false;
          _results = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  /// Search results carry `uid` + nickname. `username` is present only when
  /// you searched by an exact "@username" you typed yourself — for everyone
  /// else the request goes out by uid and their username stays hidden.
  String _displayNameOf(Map<String, dynamic> u) {
    final name = ((u['full_name'] as String?) ?? '').trim();
    if (name.isNotEmpty) return name;
    return u['username'] != null ? '@${u['username']}' : 'Tanpa nama';
  }

  void _showSendRequestConfirmPopup(Map<String, dynamic> u) {
    final name = _displayNameOf(u);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kirim Permintaan Pertemanan'),
        content: Text('Kirim permintaan pertemanan ke $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _sendFriendRequest(u, name);
              setState(() {
                _searchCtrl.clear();
                _results = null;
              });
            },
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFriendRequest(Map<String, dynamic> u, String name) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/friends/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from_username': widget.myUsername,
          if (u['username'] != null) 'to_username': u['username'] else 'to_uid': u['uid'],
        }),
      );
      if (mounted) {
        final data = jsonDecode(res.body);
        final message = res.statusCode == 200
            ? (data['already_friends'] == true
                ? 'Kalian sudah berteman.'
                : (data['already_sent'] == true ? 'Permintaan sudah pernah dikirim.' : 'Permintaan pertemanan terkirim ke $name!'))
            : (data['detail'] ?? 'Gagal mengirim permintaan.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ymBorderRadius)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, color: YmColors.accentPurple),
                  const SizedBox(width: 8),
                  const Text('Tambah Teman', style: YmTextStyles.username),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Cari lewat nama/nickname, email, atau @username', style: YmTextStyles.label),
              const SizedBox(height: 4),
              TextField(
                controller: _searchCtrl,
                style: YmTextStyles.chatText,
                autofocus: true,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Nama, email, atau @username',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  filled: true,
                  fillColor: YmColors.panelBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: YmColors.borderLavender)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _searching ? null : _search,
                  style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
                  child: _searching
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Cari'),
                ),
              ),
              if (_results != null) ...[
                const SizedBox(height: 12),
                if (_results!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Tidak ada user yang cocok.', style: YmTextStyles.statusMessage),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final u in _results!)
                          ListTile(
                            dense: true,
                            leading: UserAvatar(
                              photoUrl: u['photo_url'] as String?,
                              username: (u['photo_url'] == null && u['username'] != null) ? u['username'] as String : null,
                              viewer: widget.myUsername,
                              radius: 14,
                            ),
                            title: Text(_displayNameOf(u), style: YmTextStyles.buddyName),
                            subtitle: u['username'] != null ? Text('@${u['username']}', style: YmTextStyles.statusMessage) : null,
                            trailing: TextButton(
                              onPressed: () => _showSendRequestConfirmPopup(u),
                              child: const Text('Tambah'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
