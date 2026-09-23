import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/ym_theme.dart';
import 'ad_slot.dart';
import 'chat_hub.dart';
import 'chat_tab.dart';
import 'friends_tab.dart';
import 'mobile_chat_screen.dart';
import 'mobile_session.dart';
import 'profile_tab.dart';
import 'push_service.dart';
import 'rooms_tab.dart';

/// Kerangka aplikasi mobile: menu bawah Chat / Rooms / Friends / Profile (gaya WhatsApp).
class MobileShell extends StatefulWidget {
  final String myUsername;
  const MobileShell({super.key, required this.myUsername});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> with WidgetsBindingObserver {
  final ChatHub _hub = ChatHub.instance;
  final GlobalKey<FriendsTabState> _friendsKey = GlobalKey<FriendsTabState>();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hub.onForceLogout = (reason) {
      if (mounted) MobileSession.logout(context);
    };
    _hub.openChat = (peer) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MobileChatScreen(myUsername: widget.myUsername, peerUsername: peer)),
      );
    };
    _hub.start(widget.myUsername);
    // Notifikasi push (Firebase) + konfigurasi iklan dari server; tidak menghalangi tampilan awal.
    unawaited(PushService.start(widget.myUsername));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    _hub.appInForeground = foreground;
    if (foreground) {
      _hub.refresh(); // pesan yang masuk selagi aplikasi di latar belakang
      unawaited(PushService.refresh()); // saklar Firebase + iklan dari admin (memuat konfigurasi terbaru)
      final active = _hub.activePeer;
      if (active != null) _hub.markRead(active);
    }
  }

  static const _titles = ['Batam ChitChat', 'Rooms', 'Friends', 'Profile'];
  static const _adPlacements = ['home', 'room_list', null, null];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: YmColors.titleBarStart,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            if (_index == 0) ...[
              Image.asset('assets/icons/logo_batamchitchat.png', height: 30),
              const SizedBox(width: 10),
            ],
            Text(_titles[_index], style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          if (_index == 0 || _index == 2)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Tambah teman',
              onPressed: () {
                setState(() => _index = 2);
                WidgetsBinding.instance.addPostFrameCallback((_) => _friendsKey.currentState?.addFriend());
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                ChatTab(myUsername: widget.myUsername),
                RoomsTab(myUsername: widget.myUsername),
                FriendsTab(key: _friendsKey, myUsername: widget.myUsername),
                ProfileTab(myUsername: widget.myUsername),
              ],
            ),
          ),
          if (_adPlacements[_index] != null)
            AdSlot(key: ValueKey(_adPlacements[_index]), placement: _adPlacements[_index]!),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _hub,
        builder: (context, _) {
          final unread = _hub.totalUnread;
          return NavigationBar(
            selectedIndex: _index,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFE2DFFB),
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  backgroundColor: YmColors.buzzRed,
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  backgroundColor: YmColors.buzzRed,
                  child: const Icon(Icons.chat_bubble, color: YmColors.accentPurple),
                ),
                label: 'Chat',
              ),
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: YmColors.accentPurple),
                label: 'Rooms',
              ),
              const NavigationDestination(
                icon: Icon(Icons.group_outlined),
                selectedIcon: Icon(Icons.group, color: YmColors.accentPurple),
                label: 'Friends',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: YmColors.accentPurple),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }
}
