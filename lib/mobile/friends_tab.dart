import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../screens/add_friend_dialog.dart';
import '../screens/friend_alias_dialog.dart';
import '../screens/user_profile_dialog.dart';
import '../services/friend_directory_service.dart';
import '../theme/ym_theme.dart';
import '../widgets/user_avatar.dart';
import 'chat_hub.dart';
import 'mobile_chat_screen.dart';

/// Tab "Friends": permintaan pertemanan masuk, daftar teman (nickname / nama panggilan pribadi), tambah teman.
class FriendsTab extends StatefulWidget {
  final String myUsername;
  const FriendsTab({super.key, required this.myUsername});

  @override
  State<FriendsTab> createState() => FriendsTabState();
}

class FriendsTabState extends State<FriendsTab> {
  final ChatHub _hub = ChatHub.instance;
  List<FriendInfo> _friends = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  int _seenTick = 0;

  @override
  void initState() {
    super.initState();
    _seenTick = _hub.friendRequestTick;
    _hub.addListener(_onHub);
    reload();
  }

  @override
  void dispose() {
    _hub.removeListener(_onHub);
    super.dispose();
  }

  void _onHub() {
    if (_hub.friendRequestTick != _seenTick) {
      _seenTick = _hub.friendRequestTick;
      reload();
    }
  }

  Future<void> reload() async {
    final friends = await FriendDirectoryService().fetchFriends();
    List<Map<String, dynamic>> requests = _requests;
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/friends/requests/${widget.myUsername}'));
      if (res.statusCode == 200) {
        requests = List<Map<String, dynamic>>.from(jsonDecode(res.body)['requests']);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (friends != null) _friends = friends;
      _requests = requests;
      _loading = false;
    });
  }

  Future<void> _respond(int requestId, String action) async {
    try {
      await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/friends/respond'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'request_id': requestId, 'action': action}),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal merespons permintaan.')));
      }
    }
    await reload();
  }

  Future<void> addFriend() async {
    await showDialog<void>(context: context, builder: (_) => AddFriendDialog(myUsername: widget.myUsername));
    reload();
  }

  void _openChat(FriendInfo f) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MobileChatScreen(myUsername: widget.myUsername, peerUsername: f.username)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_requests.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Permintaan Pertemanan',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: YmColors.accentPurple)),
            ),
            for (final r in _requests)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE9E8FA),
                  child: Icon(Icons.person_add_alt_1, color: YmColors.accentPurple),
                ),
                title: Text('${r['from_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('ingin berteman denganmu'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(onPressed: () => _respond(r['request_id'] as int, 'reject'), child: const Text('Tolak')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
                      onPressed: () => _respond(r['request_id'] as int, 'accept'),
                      child: const Text('Terima'),
                    ),
                  ],
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Daftar Teman (${_friends.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: YmColors.accentPurple)),
          ),
          if (_friends.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Text(
                'Belum ada teman. Ketuk ikon tambah teman di kanan atas untuk mencari.',
                textAlign: TextAlign.center,
                style: TextStyle(color: YmColors.textMuted),
              ),
            ),
          for (final f in _friends)
            ListTile(
              onTap: () => _openChat(f),
              onLongPress: () => showDialog<void>(
                context: context,
                builder: (_) => UserProfileDialog(username: f.username, viewerUsername: widget.myUsername),
              ),
              leading: UserAvatar(username: f.username, viewer: widget.myUsername, radius: 22),
              title: Text(f.displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              subtitle: (f.hasAlias && f.hasNickname) ? Text(f.nickname!) : null,
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: YmColors.textMuted),
                tooltip: 'Ubah nama panggilan',
                onPressed: () async {
                  final changed = await showFriendAliasDialog(context, f);
                  if (changed) reload();
                },
              ),
            ),
        ],
      ),
    );
  }
}
