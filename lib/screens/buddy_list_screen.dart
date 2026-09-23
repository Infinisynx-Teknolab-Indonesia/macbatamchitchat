import 'dart:convert';
import '../config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/app_sidebar.dart';
import '../models/buddy.dart';
import '../services/window_launcher.dart';
import 'user_profile_dialog.dart';

const _apiBase = AppConfig.apiBaseUrl;

/// The "Contacts" window — opened as its own top-level window via the
/// sidebar, not embedded inside Home. Friends are added via SEARCH first
/// (never a blind "type any username and add"), and clicking a friend
/// opens a private chat as a brand-new window rather than navigating
/// within this one.
class BuddyListScreen extends StatefulWidget {
  final String username;
  const BuddyListScreen({super.key, required this.username});

  @override
  State<BuddyListScreen> createState() => _BuddyListScreenState();
}

class _BuddyListScreenState extends State<BuddyListScreen> {
  // TODO: replace with a real GET /api/friends/{username} call
  final List<Buddy> _buddies = [
    const Buddy(username: 'wati99', statusMessage: 'Lagi nugas nih...', status: BuddyStatus.online, group: 'Teman Dekat'),
    const Buddy(username: 'budi_santoso', statusMessage: 'Sibuk banget', status: BuddyStatus.busy, group: 'Teman Dekat'),
    const Buddy(username: 'anto_gaming', statusMessage: 'Push rank malam ini', status: BuddyStatus.online, group: 'Teman Dekat'),
    const Buddy(username: 'pak_rudi', status: BuddyStatus.online, group: 'Kerja'),
    const Buddy(username: 'bu_sinta', status: BuddyStatus.offline, group: 'Kerja'),
    const Buddy(username: 'rara_cantik', status: BuddyStatus.offline, group: 'Keluarga'),
  ];

  BuddyStatus _myStatus = BuddyStatus.online;
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<Map<String, dynamic>> _incomingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadIncomingRequests();
    _configureWindowSize();
  }

  Future<void> _configureWindowSize() async {
    try {
      await windowManager.setMinimumSize(const Size(420, 680));
      await windowManager.setResizable(true);
    } catch (e) {
      // ignore: avoid_print
      print('[Contacts] window_manager unavailable (native patch from NATIVE_SETUP.md not applied?): $e');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIncomingRequests() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/friends/requests/${widget.username}'));
      if (res.statusCode == 200) {
        setState(() => _incomingRequests = List<Map<String, dynamic>>.from(jsonDecode(res.body)['requests']));
      }
    } catch (_) {
      // best-effort
    }
  }

  /// EXACT match only, triggered on Enter — never a live "type and see a
  /// list of other people" dropdown. If the exact @username doesn't
  /// exist, shows a "user not found" popup; the friend-request popup
  /// only appears for a confirmed exact match.
  Future<void> _searchAndRequest(String rawQuery) async {
    final username = rawQuery.trim().replaceFirst('@', '');
    if (username.isEmpty) return;

    setState(() => _searching = true);
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/check/$username'));
      final data = jsonDecode(res.body);
      setState(() => _searching = false);

      if (data['exists'] != true) {
        _showUserNotFoundPopup(username);
        return;
      }

      if (username == widget.username) {
        _showUserNotFoundPopup(username); // can't friend yourself — treat the same as not-found
        return;
      }

      _showSendRequestConfirmPopup(username);
    } catch (_) {
      setState(() => _searching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  void _showUserNotFoundPopup(String username) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('User Tidak Ditemukan'),
        content: Text('Tidak ada user dengan username @$username.'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Oke'))],
      ),
    );
  }

  void _showSendRequestConfirmPopup(String username) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kirim Permintaan Pertemanan'),
        content: Text('Kirim permintaan pertemanan ke @$username?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _sendFriendRequest(username);
              _searchCtrl.clear();
            },
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFriendRequest(String username) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/friends/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'from_username': widget.username, 'to_username': username}),
      );
      if (mounted) {
        final data = jsonDecode(res.body);
        final message = res.statusCode == 200
            ? (data['already_sent'] == true ? 'Permintaan sudah pernah dikirim.' : 'Permintaan pertemanan terkirim ke @$username!')
            : (data['detail'] ?? 'Gagal mengirim permintaan.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  Future<void> _respondToRequest(int requestId, String action) async {
    try {
      await http.post(
        Uri.parse('$_apiBase/friends/respond'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'request_id': requestId, 'action': action}),
      );
      await _loadIncomingRequests();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal merespons permintaan.')));
      }
    }
  }

  void _showFriendRequestPopup(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Permintaan Pertemanan'),
        content: Text('@${request['from_username']} ingin berteman dengan kamu.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _respondToRequest(request['request_id'], 'blacklist');
            },
            child: const Text('Blacklist', style: TextStyle(color: YmColors.buzzRed)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _respondToRequest(request['request_id'], 'reject');
            },
            child: const Text('Tolak'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(context).pop();
              _respondToRequest(request['request_id'], 'accept');
            },
            child: const Text('Terima'),
          ),
        ],
      ),
    );
  }

  Map<String, List<Buddy>> get _groupedBuddies {
    final grouped = <String, List<Buddy>>{};
    for (final b in _buddies) {
      grouped.putIfAbsent(b.group, () => []).add(b);
    }
    return grouped;
  }

  Color _statusColor(BuddyStatus s) {
    switch (s) {
      case BuddyStatus.online: return YmColors.statusOnline;
      case BuddyStatus.busy: return YmColors.statusBusy;
      case BuddyStatus.invisible:
      case BuddyStatus.offline: return YmColors.statusOffline;
    }
  }

  String _statusLabel(BuddyStatus s) {
    switch (s) {
      case BuddyStatus.online: return 'Online';
      case BuddyStatus.busy: return 'Sibuk';
      case BuddyStatus.invisible: return 'Invisible';
      case BuddyStatus.offline: return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedBuddies;

    return Scaffold(
      body: Column(
        children: [
          RetroTitleBar(title: 'Batam ChitChat — ${widget.username}'),
          Expanded(
            child: Row(
              children: [
                AppSidebar(myUsername: widget.username, activeItem: 'contacts'),
                Container(width: 1, color: YmColors.borderLavender.withOpacity(0.5)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Profile header + status dropdown
                      Container(
                        color: YmColors.accentPurple.withOpacity(0.06),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => showDialog(context: context, builder: (_) => UserProfileDialog(username: widget.username, viewerUsername: widget.username)),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: YmColors.accentPurple,
                                child: Text(
                                  widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('@${widget.username}', style: YmTextStyles.username),
                                  DropdownButton<BuddyStatus>(
                                    value: _myStatus,
                                    isDense: true,
                                    underline: const SizedBox(),
                                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                                    items: BuddyStatus.values.map((s) {
                                      return DropdownMenuItem(
                                        value: s,
                                        child: Row(
                                          children: [
                                            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor(s))),
                                            const SizedBox(width: 6),
                                            Text(_statusLabel(s), style: YmTextStyles.statusMessage),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (v) => setState(() => _myStatus = v!),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Search box — EXACT match only, triggered on Enter.
                      // No live dropdown of "other people" while typing;
                      // pressing Enter either shows a confirm-request
                      // popup (exact match found) or a not-found popup.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: TextField(
                          controller: _searchCtrl,
                          style: YmTextStyles.chatText,
                          onSubmitted: _searchAndRequest,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Cari username persis, lalu Enter (contoh: @wati99)',
                            hintStyle: YmTextStyles.label,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _searching
                                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                                : IconButton(
                                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                                    tooltip: 'Cari & Tambah Teman',
                                    onPressed: () => _searchAndRequest(_searchCtrl.text),
                                  ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            filled: true,
                            fillColor: YmColors.panelBackground,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                          ),
                        ),
                      ),

                      // Banner placeholder — 300x150, per spec
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                        child: Container(
                          width: 300,
                          height: 150,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: YmColors.panelBackground,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: YmColors.borderLavender.withOpacity(0.5)),
                          ),
                          child: Text('Banner 300x150', style: YmTextStyles.label),
                        ),
                      ),

                      // Incoming friend requests — tap to open Accept/Reject/Blacklist popup
                      if (_incomingRequests.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Permintaan Pertemanan (${_incomingRequests.length})', style: YmTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                              for (final req in _incomingRequests)
                                InkWell(
                                  onTap: () => _showFriendRequestPopup(req),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person_add_alt_1, size: 16, color: YmColors.accentPurple),
                                        const SizedBox(width: 6),
                                        Text('@${req['from_username']} ingin berteman', style: YmTextStyles.chatText),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                      // Friend list — grouped, thin dividers between groups
                      Expanded(
                        child: Container(
                          color: YmColors.contentBackground,
                          child: ListView(
                            children: [
                              for (final entry in grouped.entries) ...[
                                ExpansionTile(
                                  title: Text(
                                    '${entry.key} (${entry.value.length})',
                                    style: YmTextStyles.label.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  initiallyExpanded: true,
                                  children: [
                                    for (final buddy in entry.value)
                                      _BuddyTile(
                                        buddy: buddy,
                                        onOpenChat: () => WindowLauncher.openPrivateChat(
                                          myUsername: widget.username,
                                          peerUsername: buddy.username,
                                          city: 'Batam',
                                        ),
                                        onViewProfile: () => showDialog(
                                          context: context,
                                          builder: (_) => UserProfileDialog(username: buddy.username, viewerUsername: widget.username),
                                        ),
                                      ),
                                  ],
                                ),
                                // Thin divider between groups (was a full Divider before — too heavy)
                                Container(height: 0.5, color: YmColors.borderLavender.withOpacity(0.4)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuddyTile extends StatelessWidget {
  final Buddy buddy;
  final VoidCallback onOpenChat;
  final VoidCallback onViewProfile;

  const _BuddyTile({required this.buddy, required this.onOpenChat, required this.onViewProfile});

  Color get _statusColor {
    switch (buddy.status) {
      case BuddyStatus.online: return YmColors.statusOnline;
      case BuddyStatus.busy: return YmColors.statusBusy;
      case BuddyStatus.invisible:
      case BuddyStatus.offline: return YmColors.statusOffline;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Clicking a friend opens PRIVATE CHAT AS ITS OWN NEW WINDOW — never
    // embedded/navigated within this Contacts window.
    return InkWell(
      onTap: buddy.status == BuddyStatus.offline ? null : onOpenChat,
      onLongPress: onViewProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${buddy.username}', style: YmTextStyles.buddyName),
                  if (buddy.statusMessage != null)
                    Text(buddy.statusMessage!, style: YmTextStyles.statusMessage, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 16, color: YmColors.textMuted),
              tooltip: 'Lihat Profil',
              onPressed: onViewProfile,
            ),
          ],
        ),
      ),
    );
  }
}
