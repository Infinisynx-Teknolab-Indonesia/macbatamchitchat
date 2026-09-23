import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Makes the Home window's close (X) button minimize to the system tray
/// instead of quitting the app.
///
/// IMPORTANT: every stage below is wrapped in its OWN try/catch. An
/// earlier version chained everything with plain `await` and no error
/// handling at all — if ANY single step threw (a bad icon path, a
/// temp-file permission issue, anything), every step after it silently
/// never ran, including registering the click listener — which is
/// exactly why right-clicking the tray icon showed no menu at all. Now a
/// failure in one stage (say, the icon) doesn't prevent the menu and
/// click handling from still being set up.
class TrayService {
  static bool _initialized = false;
  // Callback TERBARU. Layar yang memanggil init() paling akhir (mis. Home setelah login)
  // yang dipakai, bukan hanya layar pertama (Login). Sebelumnya init() kedua diabaikan,
  // sehingga menu tray "Logout" di Home masih menjalankan callback layar Login
  // (clearSession diam-diam) dan tidak terlihat berfungsi.
  static VoidCallback? _onExit;
  static VoidCallback? _onLogout;

  static Future<void> init({
    required VoidCallback onExitRequested,
    required VoidCallback onLogoutRequested,
  }) async {
    _onExit = onExitRequested;
    _onLogout = onLogoutRequested;
    if (_initialized) return;
    _initialized = true;

    // Register the listener FIRST — even if icon/menu setup below fails
    // partially, right-click/left-click handling still exists.
    trayManager.addListener(_TrayServiceListener());

    bool iconOk = false;
    bool menuOk = false;

    try {
      final bytes = await rootBundle.load('assets/icons/tray_icon.ico');
      final tempDir = await getTemporaryDirectory();
      final iconFile = File('${tempDir.path}/batam_chitchat_tray.ico');
      await iconFile.writeAsBytes(bytes.buffer.asUint8List());
      await trayManager.setIcon(iconFile.path);
      iconOk = true;
    } catch (e) {
      // ignore: avoid_print
      print('[TrayService] setIcon failed: $e');
    }

    try {
      await trayManager.setToolTip('Batam ChitChat');
    } catch (e) {
      // ignore: avoid_print
      print('[TrayService] setToolTip failed: $e');
    }

    try {
      final menu = Menu(items: [
        MenuItem(key: 'show', label: 'Buka Batam ChitChat'),
        MenuItem.separator(),
        MenuItem(key: 'logout', label: 'Logout'),
        MenuItem(key: 'exit', label: 'Keluar'),
      ]);
      await trayManager.setContextMenu(menu);
      menuOk = true;
    } catch (e) {
      // ignore: avoid_print
      print('[TrayService] setContextMenu failed: $e');
    }

    // IMPORTANT SAFETY NET: only intercept the close button (hide-to-tray
    // instead of quitting) if the tray icon AND its menu actually got set
    // up successfully. If either failed, the tray is non-functional —
    // enabling preventClose anyway would leave the user with a window
    // that vanishes on close with NO way to bring it back (no working
    // tray icon to click, no working menu to choose "Keluar" from). In
    // that failure case, the X button just behaves like a normal window
    // close (quits the app) instead of stranding the user.
    if (iconOk && menuOk) {
      try {
        await windowManager.setPreventClose(true);
        windowManager.addListener(_WindowCloseListener());
      } catch (e) {
        // ignore: avoid_print
        print('[TrayService] setPreventClose failed: $e');
      }
    } else {
      // ignore: avoid_print
      print('[TrayService] Tray setup incomplete (icon=$iconOk, menu=$menuOk) — '
          'close button will quit normally instead of minimizing to tray.');
    }
  }
}

typedef VoidCallback = void Function();

class _TrayServiceListener with TrayListener {

  @override
  void onTrayIconMouseDown() {
    // Left-click the tray icon — bring the window back.
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Right-click — show the context menu. tray_manager needs this
    // called explicitly on Windows; the menu does NOT pop up
    // automatically from setContextMenu() alone.
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'logout') {
      // Bring the window to front first — the logout confirmation dialog
      // needs to actually be visible, not fire silently behind a hidden
      // window (the window is likely hidden/minimized-to-tray right now,
      // that's the whole point of this menu existing).
      windowManager.show();
      windowManager.focus();
      TrayService._onLogout?.call();
    } else if (menuItem.key == 'exit') {
      TrayService._onExit?.call();
    }
  }
}

class _WindowCloseListener with WindowListener {
  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }
}