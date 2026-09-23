import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import '../config/app_config.dart';
import '../theme/ym_theme.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/user_avatar.dart';
import '../services/window_launcher.dart';
import '../services/tray_service.dart';
import '../services/logout_helper.dart';
import '../services/socket_service.dart';
import '../services/friend_directory_service.dart';
import '../services/block_service.dart';
import '../services/recent_chats_service.dart';
import '../services/my_rooms_service.dart';
import 'user_profile_dialog.dart';
import 'profile_edit_screen.dart';
import 'add_friend_dialog.dart';
import 'friend_alias_dialog.dart';

const _apiBase = AppConfig.apiBaseUrl;

class _RecentChat {
  final String username;
  final String displayName;
  final String lastMessage;
  final String time;
  final int unread;
  const _RecentChat(this.username, this.displayName, this.lastMessage, this.time, {this.unread = 0});
}

/// Main landing window after login. Deliberately shows ONLY
/// friend-related content — pending friend requests, the friends list,
/// and recent chats. Public room browsing lives entirely in the separate
/// Rooms window (see AppSidebar), not duplicated here.
class HomeScreen extends StatefulWidget {
  final String myUsername;
  const HomeScreen({super.key, required this.myUsername});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  // Own profile, shown in the header. Refreshed on open, after returning
  // from the profile screen, and whenever this window regains focus (a
  // photo/nickname changed in the separate Settings window shows up here
  // as soon as you switch back).
  String? _myFullName;
  String _myStatus = 'online'; // 'online' | 'busy' | 'invisible' | 'offline'
  String? _myPhotoUrl;
  int? _myPhotoStamp;
  bool _myProfileLoaded = false;

  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _sentRequests = [];
  List<FriendInfo> _friends = [];
  bool _loadingFriends = true;
  late final SocketService _socket;

  // Diisi dari GET /api/dm/recent (app/mobile_chat.py) — endpoint yang
  // sama dipakai aplikasi mobile untuk badge unread + preview pesan
  // terakhir, dipakai ulang di sini alih-alih data contoh yang statis.
  List<_RecentChat> _recentChats = [];
  bool _loadingRecentChats = true;

  // Room yang user ini buat sendiri (0 atau 1, lihat batas 1 room per
  // orang) dan room yang pernah dia masuki — dari GET /users/{u}/my-rooms.
  MyRoomInfo? _myCreatedRoom;
  List<MyRoomInfo> _myJoinedRooms = [];
  bool _loadingMyRooms = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadMyProfile();
    _loadIncomingRequests();
    _loadSentRequests();
    _loadFriends();
    _loadRecentChats();
    _loadMyRooms();
    // The close (X) button minimizes to tray instead of quitting — the
    // app keeps running (socket connected, notifications still work)
    // until "Keluar" is chosen from the tray icon's menu.
    TrayService.init(
      onExitRequested: () => exit(0),
      onLogoutRequested: () => performLogout(context),
    );

    // Home previously had NO socket connection at all — meaning it could
    // only ever know about friend requests etc. from a one-time REST
    // fetch at open time. This is what makes a request that arrives
    // WHILE Home is already open show up live, instead of only after
    // manually reopening/refreshing.
    _socket = SocketService(
      // Buzz dari teman: buka jendela private chat-nya langsung (walau aplikasi sedang di tray).
      onBuzzReceived: (from) => _onBuzzFromFriend(from),
      onFriendRequestReceived: (requestId, fromName) {
        _loadIncomingRequests();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$fromName ingin berteman denganmu.')),
          );
        }
      },
      // Pesan pribadi masuk SAAT Home terbuka (window private chat-nya belum
      // tentu terbuka) -> ini yang membuat badge unread langsung muncul
      // tanpa perlu menutup-buka Home. Kalau window chat-nya sedang
      // terbuka/fokus, dia sendiri yang menandai sudah dibaca lewat
      // RecentChatsService.markRead, dan refresh berikutnya akan
      // menunjukkan unread 0 lagi.
      onDirectMessageReceived: (sender, message, ts) => _loadRecentChats(),
    )..connect(AppConfig.socketUrl);
    _socket.registerPresence(widget.myUsername);
  }

  /// Buzz masuk. Home selalu hidup (juga saat window disembunyikan ke tray) dan menerima event ini.
  ///  - Belum ada jendela chat dengan pengirim  -> dibuka sekarang, tampil di atas semua window,
  ///    bergetar + bunyi (buzzOnOpen).
  ///  - Jendelanya sudah ada -> ia menerima event buzz-nya sendiri: dimunculkan ke depan, bergetar + bunyi;
  ///    di sini WindowLauncher hanya memastikan jendela itu ditampilkan (tidak membuat duplikat).
  Future<void> _onBuzzFromFriend(String from) async {
    if (from.isEmpty || from == widget.myUsername) return;
    try {
      await WindowLauncher.openPrivateChat(
        myUsername: widget.myUsername,
        peerUsername: from,
        city: 'Batam',
        buzzOnOpen: true,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[home] gagal membuka chat untuk buzz dari $from: $e');
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _socket.dispose();
    super.dispose();
  }

  @override
  void onWindowFocus() {
    _loadMyProfile();
    _loadRecentChats();
    _loadMyRooms();
  }

  Future<void> _loadMyProfile() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/users/${widget.myUsername}/profile').replace(
        queryParameters: {'viewer': widget.myUsername},
      ));
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body);
      final name = ((data['full_name'] as String?) ?? '').trim();
      final photo = data['photo_url'];
      setState(() {
        _myFullName = name.isEmpty ? null : name;
        _myStatus = (data['manual_status'] as String?) ?? 'online';
        _myPhotoUrl = (photo is String && photo.isNotEmpty) ? photo : null;
        _myPhotoStamp = DateTime.now().millisecondsSinceEpoch;
        _myProfileLoaded = true;
      });
    } catch (_) {
      // best-effort — header just keeps showing what it had
    }
  }

  static const _statusLabels = {'online': 'Online', 'busy': 'Sibuk', 'invisible': 'Invisible'};
  static const _statusColors = {
    'online': YmColors.statusOnline,
    'busy': YmColors.statusBusy,
    'invisible': YmColors.statusOffline,
  };

  Future<void> _changeMyStatus(String status) async {
    final previous = _myStatus;
    setState(() => _myStatus = status); // langsung terasa responsif, dikoreksi lagi kalau server menolak
    try {
      final res = await http.patch(
        Uri.parse('$_apiBase/users/${widget.myUsername}/privacy'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'manual_status': status}),
      );
      if (res.statusCode != 200 && mounted) setState(() => _myStatus = previous);
    } catch (_) {
      if (mounted) setState(() => _myStatus = previous);
    }
  }

  void _showStatusMenu(BuildContext context, Offset globalPosition) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx, globalPosition.dy),
      items: _statusLabels.entries
          .map((e) => PopupMenuItem<String>(
                value: e.key,
                child: Row(children: [
                  Icon(Icons.circle, size: 10, color: _statusColors[e.key]),
                  const SizedBox(width: 8),
                  Text(e.value),
                ]),
              ))
          .toList(),
    ).then((chosen) {
      if (chosen != null) _changeMyStatus(chosen);
    });
  }

  void _openProfile() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProfileEditScreen(username: widget.myUsername)))
        .then((_) => _loadMyProfile());
  }

  Future<void> _loadIncomingRequests() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/friends/requests/${widget.myUsername}'));
      if (res.statusCode == 200) {
        setState(() => _incomingRequests = List<Map<String, dynamic>>.from(jsonDecode(res.body)['requests']));
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _loadSentRequests() async {
    try {
      final res = await http.get(Uri.parse('$_apiBase/friends/sent/${widget.myUsername}'));
      if (res.statusCode == 200) {
        setState(() => _sentRequests = List<Map<String, dynamic>>.from(jsonDecode(res.body)['requests']));
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _cancelSentRequest(int requestId, String toName) async {
    try {
      final res = await http.delete(
        Uri.parse('$_apiBase/friends/sent/$requestId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'requesting_username': widget.myUsername}),
      );
      if (res.statusCode == 200) {
        await _loadSentRequests();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permintaan ke $toName dibatalkan.')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal membatalkan permintaan.')));
      }
    }
  }

  Future<void> _confirmUnfriend(FriendInfo friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus pertemanan?'),
        content: Text('${friend.displayName} akan hilang dari daftar teman kamu (dan kamu dari daftarnya).'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await http.delete(Uri.parse('$_apiBase/friends/${widget.myUsername}/${friend.username}'));
      if (res.statusCode == 200) {
        await _loadFriends();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pertemanan dengan ${friend.displayName} dihapus.')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menghapus pertemanan.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa terhubung ke server.')));
      }
    }
  }

  Future<void> _deleteRecentChat(_RecentChat chat) async {
    setState(() => _recentChats.removeWhere((c) => c.username == chat.username));
    final ok = await RecentChatsService.hideConversation(widget.myUsername, chat.username);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyimpan penghapusan ke server (akan muncul lagi nanti).')),
      );
    }
  }

  Future<void> _loadRecentChats() async {
    final result = await RecentChatsService.fetchRecent(widget.myUsername);
    if (!mounted || result == null) {
      if (mounted) setState(() => _loadingRecentChats = false);
      return;
    }
    setState(() {
      _recentChats = result.conversations
          .map((c) => _RecentChat(
                c.peerUsername,
                c.displayName ?? '@${c.peerUsername}',
                c.lastIsMine ? 'Kamu: ${c.lastMessage}' : c.lastMessage,
                c.timeLabel,
                unread: c.unread,
              ))
          .toList();
      _loadingRecentChats = false;
    });
  }

  Future<void> _loadMyRooms() async {
    final result = await MyRoomsService.fetch(widget.myUsername);
    if (!mounted) return;
    setState(() {
      _myCreatedRoom = result?.created;
      _myJoinedRooms = result?.joined ?? [];
      _loadingMyRooms = false;
    });
  }

  Future<void> _loadFriends() async {
    setState(() => _loadingFriends = true);
    // Cara baru: nickname + nama panggilan pribadi dari backend (app/friend_alias.py).
    // Kalau gagal (mis. backend belum diperbarui), pakai daftar @username yang lama.
    final detailed = await FriendDirectoryService().fetchFriends();
    if (detailed != null) {
      if (!mounted) return;
      setState(() {
        _friends = detailed;
        _loadingFriends = false;
      });
      return;
    }
    try {
      final res = await http.get(Uri.parse('$_apiBase/friends/${widget.myUsername}'));
      if (res.statusCode == 200) {
        setState(() {
          _friends = List<String>.from(jsonDecode(res.body)['friends'])
              .map((f) => FriendInfo(username: f.replaceFirst('@', '')))
              .toList();
          _loadingFriends = false;
        });
      } else {
        setState(() => _loadingFriends = false);
      }
    } catch (_) {
      setState(() => _loadingFriends = false);
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
      if (action == 'accept') await _loadFriends();
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
        title: const Text('Permintaan Pertemanan'),
        content: Text('${request['from_name']} ingin berteman dengan kamu.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppSidebar(myUsername: widget.myUsername, activeItem: 'home'),
      body: Column(
        children: [
          RetroTitleBar(title: 'Batam ChitChat — ${_myFullName ?? widget.myUsername}', showMenuButton: true),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildProfileHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (_incomingRequests.isNotEmpty) ...[
                        _SectionHeader(title: 'Permintaan Pertemanan (${_incomingRequests.length})'),
                        for (final req in _incomingRequests)
                          InkWell(
                            onTap: () => _showFriendRequestPopup(req),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.person_add_alt_1, size: 15, color: YmColors.accentPurple),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('${req['from_name']} ingin berteman', style: YmTextStyles.chatText)),
                                ],
                              ),
                            ),
                          ),
                      ],

                      if (_sentRequests.isNotEmpty) ...[
                        _SectionHeader(title: 'Permintaan Terkirim (${_sentRequests.length})'),
                        for (final req in _sentRequests)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.hourglass_empty, size: 15, color: YmColors.textMuted),
                                const SizedBox(width: 8),
                                Expanded(child: Text('Menunggu ${req['to_name']}', style: YmTextStyles.chatText)),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 15, color: YmColors.buzzRed),
                                  tooltip: 'Batalkan',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _cancelSentRequest(req['request_id'], req['to_name']),
                                ),
                              ],
                            ),
                          ),
                      ],

                      _SectionHeader(title: 'Recent Chats'),
                      if (_loadingRecentChats)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_recentChats.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text('Belum ada percakapan.', style: YmTextStyles.statusMessage),
                        )
                      else
                        for (final chat in _recentChats)
                          _RecentChatTile(
                            chat: chat,
                            viewer: widget.myUsername,
                            onTap: () async {
                              // Tandai sudah dibaca DULU (mengosongkan badge di sini seketika),
                              // baru buka jendela chat-nya.
                              setState(() {
                                final i = _recentChats.indexWhere((c) => c.username == chat.username);
                                if (i != -1) {
                                  _recentChats[i] = _RecentChat(
                                    chat.username, chat.displayName, chat.lastMessage, chat.time,
                                  );
                                }
                              });
                              unawaited(RecentChatsService.markRead(widget.myUsername, chat.username));
                              await WindowLauncher.openPrivateChat(
                                myUsername: widget.myUsername,
                                peerUsername: chat.username,
                                city: 'Batam',
                              );
                            },
                            onDelete: () => _deleteRecentChat(chat),
                          ),

                      _SectionHeader(title: 'Room Saya'),
                      if (_loadingMyRooms)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_myCreatedRoom == null && _myJoinedRooms.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text('Belum ada room. Buka Rooms untuk membuat atau bergabung.', style: YmTextStyles.statusMessage),
                        )
                      else ...[
                        if (_myCreatedRoom != null)
                          _MyRoomTile(
                            room: _myCreatedRoom!,
                            onTap: () => WindowLauncher.openRoomChat(myUsername: widget.myUsername, roomName: _myCreatedRoom!.name),
                          ),
                        for (final room in _myJoinedRooms)
                          _MyRoomTile(
                            room: room,
                            onTap: () => WindowLauncher.openRoomChat(myUsername: widget.myUsername, roomName: room.name),
                          ),
                      ],

                      _SectionHeader(title: 'Daftar Teman (${_friends.length})'),
                      if (_loadingFriends)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_friends.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text('Belum ada teman. Tekan tombol + di atas untuk cari.', style: YmTextStyles.statusMessage),
                        )
                      else
                        for (final friend in _friends)
                          _FriendTile(
                            friend: friend,
                            viewer: widget.myUsername,
                            onOpenChat: () => WindowLauncher.openPrivateChat(
                              myUsername: widget.myUsername,
                              peerUsername: friend.username,
                              city: 'Batam',
                            ),
                            onViewProfile: () => showDialog(
                              context: context,
                              builder: (_) => UserProfileDialog(
                                username: friend.username,
                                viewerUsername: widget.myUsername,
                              ),
                            ),
                            onEditAlias: () async {
                              final changed = await showFriendAliasDialog(context, friend);
                              if (changed) _loadFriends();
                            },
                            onBlock: () => BlockService.confirmAndBlock(
                              context,
                              myUsername: widget.myUsername,
                              targetUsername: friend.username,
                              onBlocked: _loadFriends,
                            ),
                            onUnfriend: () => _confirmUnfriend(friend),
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

  Widget _buildProfileHeader() {
    return Container(
      color: YmColors.accentPurple.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          InkWell(
            onTap: _openProfile,
            child: UserAvatar(photoUrl: _myPhotoUrl, radius: 15, version: _myPhotoStamp),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_myFullName ?? widget.myUsername, style: YmTextStyles.username),
                GestureDetector(
                  onTapDown: (details) => _showStatusMenu(context, details.globalPosition),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 7, color: _statusColors[_myStatus] ?? YmColors.statusOnline),
                      const SizedBox(width: 4),
                      Text(_statusLabels[_myStatus] ?? 'Online', style: YmTextStyles.statusMessage),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down, size: 14, color: YmColors.textMuted),
                    ],
                  ),
                ),
                // First-time nudge: no nickname yet -> can't enter rooms.
                if (_myProfileLoaded && _myFullName == null)
                  InkWell(
                    onTap: _openProfile,
                    child: Text(
                      'Buat nickname dulu untuk masuk room  ›',
                      style: YmTextStyles.statusMessage.copyWith(color: YmColors.accentPurple),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, size: 16, color: YmColors.textMuted),
            tooltip: 'Tambah Teman',
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => AddFriendDialog(myUsername: widget.myUsername),
              );
              // Refresh in case a request was just sent from the dialog —
              // it should show up in "Permintaan Terkirim" immediately.
              _loadSentRequests();
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
      child: Text(title, style: YmTextStyles.label.copyWith(fontWeight: FontWeight.w700, fontSize: 10)),
    );
  }
}

class _RecentChatTile extends StatelessWidget {
  final _RecentChat chat;
  final String viewer;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _RecentChatTile({required this.chat, required this.viewer, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('recent_chat_${chat.username}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: YmColors.buzzRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              UserAvatar(username: chat.username, viewer: viewer, radius: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.displayName, style: YmTextStyles.buddyName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(chat.lastMessage, style: YmTextStyles.statusMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(chat.time, style: YmTextStyles.label),
                  if (chat.unread > 0) ...[
                    const SizedBox(height: 3),
                    CircleAvatar(radius: 7, backgroundColor: YmColors.accentPurple,
                        child: Text('${chat.unread}', style: const TextStyle(color: Colors.white, fontSize: 8))),
                  ],
                ],
              ),
              // Titik tiga: cara lain menghapus selain gesture swipe (dan
              // satu-satunya cara di perangkat tanpa layar sentuh/mouse-drag).
              PopupMenuButton<void>(
                tooltip: 'Opsi lainnya',
                icon: const Icon(Icons.more_vert, size: 15, color: YmColors.textMuted),
                padding: EdgeInsets.zero,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    onTap: onDelete,
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Hapus dari Recent Chats', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final FriendInfo friend;
  final String viewer;
  final VoidCallback onOpenChat;
  final VoidCallback onViewProfile;
  final VoidCallback onEditAlias;
  final VoidCallback onBlock;
  final VoidCallback onUnfriend;
  const _FriendTile({
    required this.friend,
    required this.viewer,
    required this.onOpenChat,
    required this.onViewProfile,
    required this.onEditAlias,
    required this.onBlock,
    required this.onUnfriend,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenChat,
      onLongPress: onViewProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(username: friend.username, viewer: viewer, radius: 15),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 9, height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _friendStatusColor(friend.status),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // nama panggilan pribadi > nickname > @username
                  Text(friend.displayName, style: YmTextStyles.buddyName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  // kalau saya memberi nama panggilan, nickname aslinya tampil kecil di bawahnya
                  if (friend.hasAlias && friend.hasNickname)
                    Text(friend.nickname!, style: YmTextStyles.statusMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 13, color: YmColors.textMuted),
              tooltip: 'Ubah nama panggilan',
              onPressed: onEditAlias,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 13, color: YmColors.textMuted),
              tooltip: 'Lihat Profil',
              onPressed: onViewProfile,
            ),
            PopupMenuButton<void>(
              tooltip: 'Opsi lainnya',
              icon: const Icon(Icons.more_vert, size: 15, color: YmColors.textMuted),
              padding: EdgeInsets.zero,
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: onUnfriend,
                  child: const Row(
                    children: [
                      Icon(Icons.person_remove_outlined, size: 16, color: YmColors.textMuted),
                      SizedBox(width: 8),
                      Text('Hapus Pertemanan'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  onTap: onBlock,
                  child: const Row(
                    children: [
                      Icon(Icons.block, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Blokir', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MyRoomTile extends StatelessWidget {
  final MyRoomInfo room;
  final VoidCallback onTap;
  const _MyRoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(
              room.isCreator ? Icons.workspace_premium_outlined : Icons.forum_outlined,
              size: 22,
              color: YmColors.accentPurple,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: YmTextStyles.buddyName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    room.isCreator ? 'Room buatanmu' : (room.isDefault ? 'Room default' : 'Sedang kamu masuki'),
                    style: YmTextStyles.statusMessage,
                  ),
                ],
              ),
            ),
            Text('${room.onlineCount} online', style: YmTextStyles.label),
          ],
        ),
      ),
    );
  }
}

Color _friendStatusColor(String status) {
  switch (status) {
    case 'online': return YmColors.statusOnline;
    case 'busy': return YmColors.statusBusy;
    default: return YmColors.statusOffline; // 'offline' (termasuk yang invisible, sengaja terlihat sama)
  }
}
