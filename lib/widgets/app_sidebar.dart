import 'package:flutter/material.dart';
import '../theme/ym_theme.dart';
import '../services/window_launcher.dart';
import '../services/logout_helper.dart';

/// Navigation drawer shown in every top-level window (Home, Rooms,
/// Settings) — HIDDEN by default, slides in from the left when the
/// hamburger button (see RetroTitleBar's showMenuButton) is tapped, using
/// Flutter's standard Drawer/Scaffold.drawer mechanism (so the slide
/// animation, dimmed backdrop, and tap-outside-to-close all come for free).
///
/// NOTE: no "Contacts" item — Home now covers everything Contacts used to
/// (friend requests, friends list, recent chats, AND add-friend via the
/// dialog on Home's header), so a separate Contacts window was redundant.
///
/// NOTE: there is deliberately NO standalone "Create Room" item here —
/// creating a room only makes sense in the context of a subcategory
/// (see chat_categories_screen.dart's "Buat Room Baru" button).
class AppSidebar extends StatelessWidget {
  final String myUsername;
  final String activeItem; // 'home' | 'rooms' | 'settings'

  const AppSidebar({super.key, required this.myUsername, required this.activeItem});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 220,
      backgroundColor: YmColors.titleBarStart,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('@$myUsername', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.home_rounded,
              label: 'Home',
              active: activeItem == 'home',
              onTap: () {
                Navigator.of(context).pop(); // close drawer first
                if (activeItem != 'home') Navigator.of(context).maybePop();
              },
            ),
            _DrawerItem(
              icon: Icons.forum_rounded,
              label: 'Rooms',
              active: activeItem == 'rooms',
              onTap: () {
                Navigator.of(context).pop();
                WindowLauncher.openRoomList(myUsername: myUsername);
              },
            ),
            _DrawerItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              active: activeItem == 'settings',
              onTap: () {
                Navigator.of(context).pop();
                WindowLauncher.openSettings(myUsername: myUsername);
              },
            ),
            const Spacer(),
            const Divider(color: Colors.white24, height: 1),
            _DrawerItem(
              icon: Icons.logout_rounded,
              label: 'Logout',
              active: false,
              // IMPORTANT: do NOT pop the drawer before calling _logout —
              // popping first invalidates this context (the drawer's own
              // route just closed), so the confirmation dialog and the
              // final navigation inside _logout would silently fail on an
              // already-torn-down context. _logout shows its dialog on
              // the drawer's context (still valid, drawer still open
              // underneath) and only navigates once actually confirmed —
              // that pushAndRemoveUntil wipes the whole stack, drawer
              // included, so there's no need to pop it separately.
              onTap: () => performLogout(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DrawerItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        color: active ? Colors.white.withOpacity(0.15) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
