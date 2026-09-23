import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'screens/login_screen.dart';
import 'screens/setup_wizard_screen.dart';
import 'services/secure_storage_service.dart';
import 'services/window_launcher.dart';
import 'services/session_signal.dart';
import 'theme/ym_theme.dart';
import 'multi_window_entry.dart';

/// Window sizes for each phase of the app — login/setup AND the main app
/// (Home) are both fixed-size, non-resizable, like classic IM clients.
/// Sub-windows opened from Home (Rooms, Contacts, Room Chat, etc.) can
/// still be resized freely — only these two top-level windows are locked.
class AppWindowSizes {
  static const login = Size(450, 780);
  static const main = Size(450, 780); // same as login (was 400x680, before that 300x700)
}

void main(List<String> args) async {
  // Build khusus macOS: tidak ada panggilan allowWebView2AutoplayWithSound()
  // di sini sama sekali — itu FFI ke kernel32.dll (Windows-only) untuk
  // WebView2's autoplay flag, dan build ini pakai webview_flutter (WKWebView
  // di macOS), jadi fix itu tidak relevan/tidak ada di project ini.
  WidgetsFlutterBinding.ensureInitialized();

  // desktop_multi_window launches sub-windows by re-running this same
  // main() with extra CLI-style args: ["multi_window", "<windowId>", "<jsonArgs>"].
  // Route those straight to MultiWindowEntry instead of the normal
  // login/startup flow — each sub-window is its own independent screen
  // (private chat, rooms list, create room, etc.), not part of the main
  // app's navigation stack.
  if (args.isNotEmpty && args.first == 'multi_window') {
    final argsJson = args.length > 2 ? args[2] : '{}';

    // This ONLY fully works if windows/runner/flutter_window.cpp has been
    // patched to register plugins for new sub-windows too — see
    // NATIVE_SETUP.md in the project root. Without that native-side
    // change, window_manager isn't available in this isolate and throws
    // MissingPluginException.
    //
    // IMPORTANT: wrapped in try/catch so a missing native patch degrades
    // gracefully (native OS title bar shown instead of our custom one)
    // rather than crashing before runApp() ever executes — which is what
    // caused entirely blank/white sub-windows previously. A cosmetic
    // title bar failing should never block the window's actual content.
    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          backgroundColor: Colors.transparent,
          titleBarStyle: TitleBarStyle.hidden,
        ),
        () async {
          await windowManager.show();
        },
      );
    } catch (e) {
      // ignore: avoid_print
      print('[main] window_manager unavailable in this sub-window (native '
          'patch from NATIVE_SETUP.md not applied yet?): $e');
    }

    // Listens for a "force_close" broadcast from the main window (sent on
    // logout — see WindowLauncher.closeAllSpawnedWindows) and closes THIS
    // window in response. Without this, logging out only reset the main
    // Home window; every Room/Contacts/Rooms/Settings/Private Chat window
    // kept running with a session that no longer existed.
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'force_close') {
        await WindowLauncher.closeThisWindow();
        return 'ok';
      } else if (call.method == 'ping') {
        // Liveness check used by WindowLauncher's dedup logic — if a
        // cached window responds to this, it's genuinely still open and
        // safe to reuse (bring to front) instead of spawning a duplicate.
        // If it DOESN'T respond (the window was closed), the caller's
        // invokeMethod call throws/times out, which is how it knows to
        // create a fresh window instead — this replaces an earlier
        // dedup attempt that had no way to detect a closed window and
        // ended up permanently "stuck" trying to show a dead one.
        return 'pong';
      }
      return null;
    });

    // CATATAN: sub-window TIDAK lagi memakai setPreventClose + onWindowClose.
    // window_manager 0.4.x menyimpan channel event-nya (native -> Dart) di
    // SATU variabel global, yang ditimpa setiap kali window baru dibuat —
    // jadi event "close" milik window ini sendiri bisa nyasar ke window lain
    // begitu ada window kedua dibuka, dan window ini tidak akan PERNAH
    // menerima event close-nya sendiri lagi. Itulah sebabnya window bisa
    // "tidak mau close" atau baru tertutup 15 detik kemudian (menunggu
    // fallback timer lama). Penutupan sekarang 100% dipicu dari Dart
    // (tombol X di RetroTitleBar, pesan force_close di atas, dan sinyal
    // logout di bawah) lewat WindowLauncher.closeThisWindow(), yang
    // memanggil windowManager.close() sebagai PERINTAH (bukan menunggu
    // event) — perintah Dart -> native itu tetap sampai ke window yang
    // benar meski event tidak.

    // Jalur kedua penutupan saat Logout, TIDAK bergantung pada pesan antar-window: window utama menulis
    // sinyal "logout" ke satu file di folder temp, dan setiap sub-window memeriksanya tiap detik.
    SessionSignal.watch(() async {
      // ignore: avoid_print
      print('[close] sinyal logout diterima - menutup window ini');
      await WindowLauncher.closeThisWindow();
      // Kalau window ini masih hidup beberapa detik kemudian (closeThisWindow gagal total),
      // logout_helper.dart's _pastikanWindowTertutup di window utama yang akan mendeteksinya
      // lewat ping dan me-restart seluruh aplikasi — jadi tidak perlu fallback destroy() lagi di sini.
    });

    runApp(MultiWindowEntry(argsJson: argsJson));
    return;
  }

  // Configure a borderless window so our RetroTitleBar widget fully
  // replaces the OS chrome (matching the classic client look). Starts at
  // login size and NOT resizable — resized up once login succeeds (see
  // login_screen.dart's _goToBuddyList).
  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    size: AppWindowSizes.login,
    minimumSize: AppWindowSizes.login,
    maximumSize: AppWindowSizes.login,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(false);
    await windowManager.show();
    await windowManager.focus();
  });

  // This window IS the true main window — every other window (however
  // deeply it was spawned/chained) learns this ID and reports itself
  // back here (see WindowLauncher._open()'s 'register_window' call),
  // which is what makes closeAllSpawnedWindows() from Logout/tray "Keluar"
  // actually reach EVERY window, not just ones opened directly from Home.
  //
  // NOTE: hardcoded 0, not looked up dynamically — desktop_multi_window
  // assigns window ID 0 to the main/first-launched window by convention
  // (confirmed against the plugin's own example code), and the
  // WindowController.fromCurrentEngine() lookup API isn't available in
  // the 0.2.x version this project is pinned to.
  WindowLauncher.mainWindowId = 0;
  WindowLauncher.isMainWindow = true;

  DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
    switch (call.method) {
      case 'register_window':
        WindowLauncher.globalWindowRegistry.add(call.arguments['windowId'] as int);
        return null;
      case 'register_keyed_window':
        final key = call.arguments['key'] as String;
        final id = call.arguments['windowId'] as int;
        WindowLauncher.globalKeyedWindows[key] = id;
        WindowLauncher.globalWindowRegistry.add(id);
        return null;
      case 'lookup_keyed_window':
        // Cross-window dedup check — e.g. "is there already a Private
        // Chat window open for @andi_batam, opened from ANYWHERE (Home,
        // a Room Chat window, another Room Chat window)?" Without this
        // centralized lookup, each window only knew about windows IT
        // ITSELF had opened, so clicking the same person's name from two
        // different places could open two separate windows for them.
        final key = call.arguments['key'] as String;
        return WindowLauncher.globalKeyedWindows[key];
      case 'unregister_keyed_window':
        WindowLauncher.globalKeyedWindows.remove(call.arguments['key'] as String);
        return null;
      case 'ping':
        return 'pong';
      default:
        return null;
    }
  });

  runApp(const BatamChitChatApp());
}

class BatamChitChatApp extends StatelessWidget {  const BatamChitChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Batam ChitChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: YmColors.accentPurple,
        scaffoldBackgroundColor: YmColors.panelBackground,
        fontFamily: 'Tahoma',
      ),
      home: const _StartupRouter(),
    );
  }
}

/// Decides whether to show the first-run permission wizard or go straight
/// to sign-in, based on a flag persisted after the wizard completes once.
class _StartupRouter extends StatelessWidget {
  const _StartupRouter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: SecureStorageService().hasCompletedFirstRunSetup(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data! ? const LoginScreen() : const SetupWizardScreen();
      },
    );
  }
}
