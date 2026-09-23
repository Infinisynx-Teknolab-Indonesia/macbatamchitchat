import 'package:flutter/material.dart';
import '../widgets/retro_title_bar.dart';
import '../widgets/profile_panel.dart';

/// Full-window version of the profile editor, opened by tapping your own
/// avatar on Home. The actual editor lives in ProfilePanel — the exact
/// same widget is also the "Profil" tab in the Settings window, so the
/// two can never drift apart.
///
/// Uses RetroTitleBar (not a Material AppBar): this window has no native
/// title bar, so without our own there'd be nothing to drag, and RetroTitleBar
/// automatically shows a back arrow here since this is a pushed route.
class ProfileEditScreen extends StatelessWidget {
  final String username;
  const ProfileEditScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const RetroTitleBar(title: 'Profil Saya', icon: Icons.person_outline),
          Expanded(child: ProfilePanel(username: username)),
        ],
      ),
    );
  }
}
