import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/ym_theme.dart';
import 'services/window_launcher.dart';
import 'screens/chat_window_screen.dart';
import 'screens/room_chat_screen.dart';
import 'screens/chat_categories_screen.dart';
import 'screens/settings_screen.dart';

/// Renders the correct screen for a sub-window spawned via WindowLauncher.
/// [argsJson] is the JSON string passed to DesktopMultiWindow.createWindow —
/// its "screen" field picks which widget to show; everything else in it
/// is that screen's own parameters (myUsername, peerUsername, etc.).
class MultiWindowEntry extends StatelessWidget {
  final String argsJson;
  const MultiWindowEntry({super.key, required this.argsJson});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> args = argsJson.isNotEmpty ? jsonDecode(argsJson) : {};
    final screen = args['screen'] as String?;

    // Every window learns the TRUE main window's ID from its OWN spawn
    // args and keeps it for itself — this is what lets a window opened
    // from INSIDE another spawned window (e.g. Room Chat opened from
    // inside the Rooms window, not directly from Home) still correctly
    // report back to Home when IT spawns something further (a Private
    // Chat opened by clicking a member in Room Chat, say). Without this
    // propagation, only windows opened directly from Home would ever be
    // known to Home, and Logout/tray "Keluar" would leave the rest open.
    if (args['mainWindowId'] != null) {
      WindowLauncher.mainWindowId = args['mainWindowId'] as int;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: YmColors.accentPurple,
        scaffoldBackgroundColor: YmColors.panelBackground,
        fontFamily: 'Tahoma',
      ),
      home: _screenFor(screen, args),
    );
  }

  Widget _screenFor(String? screen, Map<String, dynamic> args) {
    switch (screen) {
      case 'private_chat':
        return ChatWindowScreen(
          myUsername: args['myUsername'],
          peerUsername: args['peerUsername'],
          city: args['city'],
          buzzOnOpen: args['buzzOnOpen'] == true,
        );
      case 'room_chat':
        return RoomChatScreen(
          myUsername: args['myUsername'],
          roomName: args['roomName'],
          pin: args['pin'],
        );
      case 'room_list':
        return ChatCategoriesScreen(myUsername: args['myUsername']);
      case 'settings':
        return SettingsScreen(username: args['myUsername']);
      default:
        return Scaffold(
          body: Center(child: Text('Unknown sub-window screen: $screen')),
        );
    }
  }
}
