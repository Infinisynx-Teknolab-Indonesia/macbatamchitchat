import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

/// Spawns genuinely separate native OS windows — not just Navigator
/// push/pop within one window. This is what makes "every private chat
/// opens its own window" (and Rooms, Contacts, Settings) actually true.
///
/// DEDUPLICATION — CENTRALIZED, not per-isolate: an EARLIER version kept
/// a per-isolate `_windowsByKey` map, so clicking the SAME person's name
/// from TWO DIFFERENT origin windows (e.g. from inside Room Chat, then
/// later from Home) each had their OWN empty map and neither knew the
/// other had already opened a window for that person — resulting in
/// duplicate windows for the same key. The fix: every window asks the
/// TRUE MAIN window (see mainWindowId/isMainWindow below, same mechanism
/// as closeAllSpawnedWindows' registry) whether a window for this key
/// already exists, ping-checks it for liveness, and only creates a new
/// one if there's truly nothing alive — so "same person, same window"
/// holds regardless of which window you clicked their name from.
class WindowLauncher {
  /// The ACTUAL main (first-launched) window's ID — every window learns
  /// this via its own spawn args (see multi_window_entry.dart) and
  /// re-propagates it to whatever IT spawns, so the chain never breaks
  /// no matter how many levels deep a window was opened from.
  static int? mainWindowId;

  /// True ONLY in the TRUE main window's own isolate (set once in
  /// main.dart's primary startup path) — lets this class read/write the
  /// registries below DIRECTLY instead of round-tripping through
  /// invokeMethod to itself, which desktop_multi_window may not support
  /// cleanly for a window targeting its own ID.
  static bool isMainWindow = false;

  /// Every window ID ever spawned, for closeAllSpawnedWindows(). Only
  /// meaningful in the main window's isolate (isMainWindow == true) —
  /// every other window reports here via 'register_window'.
  static final Set<int> globalWindowRegistry = {};

  /// Windows THIS specific window directly opened (isolate-local, no
  /// central registry needed) — used so that closing THIS window (e.g.
  /// the Rooms window) also force-closes whatever it spawned (e.g. a
  /// Room Chat window opened from inside it), even outside of a full
  /// Logout. See main.dart's per-sub-window close listener.
  static final Set<int> localChildWindowIds = {};

  /// Cleanup callbacks a screen registers so they run BEFORE this window
  /// is actually destroyed (see main.dart's _SubWindowCloseListener).
  ///
  /// WHY THIS EXISTS: every window of this app lives in ONE OS process
  /// (desktop_multi_window just spawns extra Flutter engines inside it).
  /// If a native plugin — WebView2, audioplayers — is still alive and busy
  /// while its window is being destroyed, the resulting native crash
  /// takes down the WHOLE process, i.e. every other window with it. That
  /// is exactly what "close Room Chat -> everything force-closes" was.
  /// Doing the teardown from State.dispose() was too late: dispose runs
  /// DURING native window destruction, and didn't await anything.
  static final List<Future<void> Function()> beforeCloseHooks = [];

  /// Runs every registered [beforeCloseHooks] entry, one at a time, each
  /// with its own timeout — a hook that hangs or throws must never be
  /// able to stop the window from closing.
  static Future<void> runBeforeCloseHooks() async {
    for (final hook in List<Future<void> Function()>.from(beforeCloseHooks)) {
      try {
        await hook().timeout(const Duration(seconds: 8));
      } catch (e) {
        // ignore: avoid_print
        print('[WindowLauncher] before-close hook failed: $e');
      }
    }
  }

  /// Broadcasts "close yourself" to every window THIS window directly
  /// opened. Called right before this window itself actually closes
  /// (see main.dart's onWindowClose handler for sub-windows) — this is
  /// what makes "close the Rooms window" also close any Room Chat
  /// windows it spawned, distinct from closeAllSpawnedWindows() below
  /// (which is for Logout/tray "Keluar" closing literally everything).
  static Future<void> closeMyChildren() async {
    final ids = localChildWindowIds.toList();
    await Future.wait(ids.map((id) async {
      // invokeMethod ke window yang SUDAH tertutup bisa menggantung sampai timeout — inilah yang
      // membuat Rooms baru tertutup belasan detik setelah Room Chat-nya. Cek dulu dengan ping singkat.
      if (!await _isAliveById(id)) return;
      try {
        await DesktopMultiWindow.invokeMethod(id, 'force_close').timeout(const Duration(seconds: 2));
      } catch (_) {}
      // Tunggu anak benar-benar hilang (maks. 10 detik) — bukan menunggu jawaban pesan.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline) && await _isAliveById(id)) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }));
    localChildWindowIds.clear();
  }

  static bool _closingThisWindow = false;

  /// Menutup window INI dengan urutan aman: hook pembersihan -> tutup window anak -> tutup window.
  ///
  /// KENAPA TIDAK LAGI MEMAKAI setPreventClose + onWindowClose: window_manager 0.4.x menyimpan channel
  /// event-nya di SATU variabel global native. Setiap window baru menimpanya, jadi event "close" dari
  /// window mana pun dikirim ke window yang dibuat PALING AKHIR (dan hilang total begitu satu window
  /// tertutup). Akibatnya window Rooms tidak pernah menerima onWindowClose-nya sendiri dan tidak mau
  /// tertutup. Panggilan Dart -> native (close, setPreventClose, ...) tetap masuk ke window yang
  /// benar, jadi seluruh urutan penutupan dijalankan dari sisi Dart, tanpa menunggu event.
  ///
  /// JANGAN memakai windowManager.destroy() di sub-window: itu PostQuitMessage(0) dan mematikan
  /// SELURUH aplikasi, bukan hanya window ini.
  static Future<void> closeThisWindow() async {
    if (_closingThisWindow) return;
    _closingThisWindow = true;
    // ignore: avoid_print
    print('[close] menutup window ini (hook -> anak -> close)');
    await runBeforeCloseHooks();
    await closeMyChildren();
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (e) {
      // ignore: avoid_print
      print('[close] windowManager.close() gagal: $e');
      _closingThisWindow = false; // boleh dicoba lagi
    }
  }

  /// key -> windowId, for cross-window deduplication. Same "only
  /// meaningful in the main window's isolate" rule as above — every other
  /// window reads/writes this via 'lookup_keyed_window' /
  /// 'register_keyed_window' / 'unregister_keyed_window'.
  static final Map<String, int> globalKeyedWindows = {};

  static Future<void> _open({
    required String key,
    required String screen,
    required Map<String, dynamic> args,
    required String title,
    required Size size,
  }) async {
    // ignore: avoid_print
    print('[WindowLauncher] _open(key: $key) — isMainWindow=$isMainWindow, mainWindowId=$mainWindowId');

    final existingId = await _lookupKeyedWindow(key);
    // ignore: avoid_print
    print('[WindowLauncher] lookup for "$key" -> existingId=$existingId');

    if (existingId != null) {
      final alive = await _isAliveById(existingId);
      // ignore: avoid_print
      print('[WindowLauncher] ping windowId=$existingId -> alive=$alive');

      if (alive) {
        try {
          final existingController = WindowController.fromWindowId(existingId);
          await existingController.show();
          // ignore: avoid_print
          print('[WindowLauncher] Reused existing window $existingId for key "$key" — NOT creating a new one.');
          return; // reused — no duplicate window created
        } catch (e) {
          // ignore: avoid_print
          print('[WindowLauncher] existingController.show() threw even though ping succeeded: $e');
        }
      }
      await _unregisterKeyedWindow(key); // stale entry — window is gone
    }

    // ignore: avoid_print
    print('[WindowLauncher] Creating a NEW window for key "$key".');

    final window = await DesktopMultiWindow.createWindow(
      // mainWindowId rides along with EVERY window's args, however deep
      // the spawn chain — this is what lets a window opened from inside
      // another spawned window still report back to the TRUE main window.
      jsonEncode({'screen': screen, 'mainWindowId': mainWindowId, ...args}),
    );
    await window.setFrame(const Offset(120, 100) & size);
    await window.center();
    await window.setTitle(title);
    await window.show();

    await _registerKeyedWindow(key, window.windowId);
    await _registerWindow(window.windowId);
    localChildWindowIds.add(window.windowId);
  }

  /// True only if the window responds to a 'ping' within a short timeout.
  /// A closed window's invokeMethod call throws or hangs — either way,
  /// this returns false and the caller creates a fresh window instead.
  static Future<bool> _isAliveById(int windowId) async {
    try {
      final result = await DesktopMultiWindow.invokeMethod(windowId, 'ping')
          .timeout(const Duration(milliseconds: 600));
      return result == 'pong';
    } catch (_) {
      return false;
    }
  }

  /// Dari [ids], kembalikan yang MASIH hidup (menjawab 'ping'). Dipakai Logout untuk memastikan
  /// semua window anak benar-benar sudah hilang.
  static Future<List<int>> aliveAmong(Iterable<int> ids) async {
    final alive = <int>[];
    await Future.wait(ids.map((id) async {
      if (await _isAliveById(id)) alive.add(id);
    }));
    return alive;
  }

  static Future<int?> _lookupKeyedWindow(String key) async {
    if (isMainWindow) return globalKeyedWindows[key];
    if (mainWindowId == null) return null;
    try {
      return await DesktopMultiWindow.invokeMethod(mainWindowId!, 'lookup_keyed_window', {'key': key})
          .timeout(const Duration(milliseconds: 600)) as int?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _registerKeyedWindow(String key, int windowId) async {
    if (isMainWindow) {
      globalKeyedWindows[key] = windowId;
      return;
    }
    if (mainWindowId == null) return;
    try {
      await DesktopMultiWindow.invokeMethod(mainWindowId!, 'register_keyed_window', {'key': key, 'windowId': windowId});
    } catch (_) {}
  }

  static Future<void> _unregisterKeyedWindow(String key) async {
    if (isMainWindow) {
      globalKeyedWindows.remove(key);
      return;
    }
    if (mainWindowId == null) return;
    try {
      await DesktopMultiWindow.invokeMethod(mainWindowId!, 'unregister_keyed_window', {'key': key});
    } catch (_) {}
  }

  static Future<void> _registerWindow(int windowId) async {
    if (isMainWindow) {
      globalWindowRegistry.add(windowId);
      return;
    }
    if (mainWindowId == null) return;
    try {
      await DesktopMultiWindow.invokeMethod(mainWindowId!, 'register_window', {'windowId': windowId});
    } catch (_) {}
  }

  /// Broadcasts a "close yourself" message to EVERY window this app has
  /// ever spawned, no matter which window opened it or how deep the
  /// chain. Only meaningful when called from the TRUE main window
  /// (Home/tray) — that's the only place Logout and "Keluar" run from,
  /// which is also the only isolate where globalWindowRegistry is kept
  /// up to date.
  static Future<void> closeAllSpawnedWindows() async {
    final ids = globalWindowRegistry.toList();
    await Future.wait(ids.map((id) async {
      // Daftar ini tidak pernah dikurangi saat window ditutup sendiri, jadi lewati yang sudah mati
      // (invokeMethod ke window mati bisa menggantung sampai timeout).
      if (!await _isAliveById(id)) return;
      try {
        await DesktopMultiWindow.invokeMethod(id, 'force_close').timeout(const Duration(seconds: 2));
      } catch (_) {
        // Tidak menjawab dalam 2 detik: penutupannya tetap berjalan di window itu sendiri.
      }
    }));
    globalWindowRegistry.clear();
    globalKeyedWindows.clear();
  }

  static Future<void> openPrivateChat({
    required String myUsername,
    required String peerUsername,
    required String city,
    // true = jendela ini dibuka karena peer mengirim BUZZ: begitu terbuka ia tampil di atas semua window,
    // bergetar, dan berbunyi (dipakai Home saat aplikasi sedang di tray).
    bool buzzOnOpen = false,
  }) {
    return _open(
      key: 'private_chat:$peerUsername',
      screen: 'private_chat',
      args: {'myUsername': myUsername, 'peerUsername': peerUsername, 'city': city, if (buzzOnOpen) 'buzzOnOpen': true},
      title: '$peerUsername — Batam ChitChat',
      size: const Size(400, 680), // resizable, min 400x680 — matches Login/Home, see ChatWindowScreen's initState
    );
  }

  static Future<void> openRoomChat({
    required String myUsername,
    required String roomName,
    String? pin,
  }) {
    return _open(
      key: 'room_chat:$roomName',
      screen: 'room_chat',
      args: {'myUsername': myUsername, 'roomName': roomName, if (pin != null) 'pin': pin},
      title: 'Room: $roomName',
      // A room with many people needs the wider member-list layout —
      // 400x680 (Login/Home/Private Chat's size) was too narrow and
      // wrapped badly. Back to 800x500, per feedback on the "rame-rame"
      // room chat screen specifically.
      size: const Size(800, 500),
    );
  }

  static Future<void> openRoomList({required String myUsername}) {
    return _open(
      key: 'room_list',
      screen: 'room_list',
      args: {'myUsername': myUsername},
      title: 'Batam ChitChat — Rooms',
      size: const Size(950, 620),
    );
  }

  // NOTE: no standalone openCreateRoom() — creating a room only makes
  // sense inside a subcategory context (see chat_categories_screen.dart's
  // "Buat Room Baru" dialog), so there's no global create-room window.

  // NOTE: no openContacts() — Home now covers everything Contacts used
  // to (friend requests, friends list, recent chats, add-friend dialog),
  // so a separate Contacts window is gone.

  static Future<void> openSettings({required String myUsername}) {
    return _open(
      key: 'settings',
      screen: 'settings',
      args: {'myUsername': myUsername},
      title: 'Batam ChitChat — Settings',
      size: const Size(760, 560),
    );
  }
}
