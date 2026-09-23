import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/ym_theme.dart';
import '../services/window_launcher.dart';

/// Custom purple-gradient title bar to replace the native OS chrome,
/// mimicking the classic IM client look — with a subtle 3D bevel (top
/// highlight + bottom shadow line) for a more elegant, raised feel
/// instead of a flat single-tone bar. Draggable via [DragToMoveArea].
///
/// NOTE: square corners, not rounded — an earlier rounded-corner-via-
/// transparent-window trick caused visible white/black rendering
/// artifacts in some Flutter/Windows setups (transparent window
/// compositing isn't fully reliable, especially in debug builds with the
/// Impeller renderer), so this reverted to plain square corners, which
/// render correctly everywhere.
class RetroTitleBar extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool showMenuButton;
  /// Tombol ekstra di antara judul dan tombol minimize/maximize/close —
  /// dipakai mis. oleh chat pribadi untuk tombol Blokir. null = tidak ada.
  final Widget? trailing;

  const RetroTitleBar({
    super.key,
    required this.title,
    this.icon = Icons.chat_bubble_rounded,
    this.showMenuButton = false,
    this.trailing,
  });

  /// If the native patch from NATIVE_SETUP.md hasn't been applied to a
  /// sub-window yet, window_manager isn't registered there and these
  /// calls throw MissingPluginException. Swallow it here so a cosmetic
  /// button failing doesn't crash the whole sub-window — the window is
  /// still closable via its native OS chrome (Alt+F4, taskbar) as a fallback.
  void _safeWindowCall(Future<void> Function() action) {
    action().catchError((e) {
      // ignore: avoid_print
      print('[RetroTitleBar] window_manager call failed (native patch missing?): $e');
    });
  }

  /// Tombol X. TIDAK bisa mengandalkan window_manager punya "onWindowClose"
  /// (dipakai TrayService untuk hide-ke-tray): window_manager 0.4.x memakai
  /// SATU channel native global untuk EVENT (native -> Dart) yang dipindah-
  /// tangankan ke window manapun yang paling terakhir dibuat. Begitu ada
  /// window kedua (Rooms, Room Chat, dst) dibuka, event "close" milik Home
  /// sendiri tidak pernah lagi sampai ke listener-nya sendiri — window
  /// jadi terlihat "tidak mau close": prevent-close berhasil memblokir OS
  /// menutupnya, tapi hide()-nya sendiri tidak pernah terpanggil karena
  /// event yang seharusnya memicunya nyasar ke isolate window lain.
  ///
  /// PERINTAH Dart -> native (isPreventClose, hide, close) tetap terkirim
  /// ke window yang benar — hanya EVENT native -> Dart yang nyasar. Jadi
  /// solusinya: putuskan & jalankan hide-ke-tray di SINI, langsung dari
  /// tombol X-nya sendiri, tanpa menunggu event apa pun.
  Future<void> _closeWindow() async {
    if (WindowLauncher.isMainWindow) {
      try {
        if (await windowManager.isPreventClose()) {
          await windowManager.hide();
          return;
        }
      } catch (e) {
        // ignore: avoid_print
        print('[RetroTitleBar] isPreventClose/hide gagal (tray belum siap?): $e');
      }
    }
    // Sub-window (Rooms, Room Chat, dst): urutan tutup aman lewat WindowLauncher
    // (hook pembersihan -> tutup anak -> tutup diri sendiri), BUKAN
    // windowManager.close() langsung — lihat closeThisWindow()'s docstring.
    await WindowLauncher.closeThisWindow();
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return DragToMoveArea(
      child: Container(
        height: 32,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [YmColors.titleBarStart, YmColors.titleBarEnd],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Stack(
          children: [
            // Top highlight strip — a thin lighter line along the very
            // top edge, like a glossy bevel catching light. This plus
            // the bottom shadow line below is what reads as "3D" rather
            // than a flat single-tone bar.
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withOpacity(0.35), Colors.white.withOpacity(0.0)],
                  ),
                ),
              ),
            ),
            // Bottom shadow line — a thin darker edge separating the
            // title bar from the content below, completing the raised look.
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(height: 1.5, color: Colors.black.withOpacity(0.18)),
            ),
            Row(
              children: [
                // Hamburger — opens the Scaffold's drawer (AppSidebar).
                // Only present when the caller explicitly opts in
                // (showMenuButton: true) — sub-windows without a drawer
                // (Room Chat, Private Chat) don't get a dead button.
                if (showMenuButton)
                  _TitleBarButton(
                    icon: Icons.menu,
                    onTap: () => Scaffold.of(context).openDrawer(),
                  ),
                // Back button — only shown when there's actually a previous
                // screen to return to (Navigator.canPop), so top-level windows
                // (Login, Home) never show a dead-end arrow.
                if (canPop)
                  _TitleBarButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: YmTextStyles.appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
                if (trailing != null) trailing!,
                _TitleBarButton(icon: Icons.remove, onTap: () => _safeWindowCall(() => windowManager.minimize())),
                _TitleBarButton(
                  icon: Icons.crop_square,
                  iconSize: 12,
                  onTap: () => _safeWindowCall(() async {
                    if (await windowManager.isMaximized()) {
                      windowManager.unmaximize();
                    } else {
                      windowManager.maximize();
                    }
                  }),
                ),
                _TitleBarButton(
                  icon: Icons.close,
                  hoverColor: YmColors.buzzRed,
                  onTap: () => _closeWindow(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final Color? hoverColor;

  const _TitleBarButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 14,
    this.hoverColor,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 40,
          height: 32,
          color: _hovering
              ? (widget.hoverColor ?? Colors.white.withOpacity(0.2))
              : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(widget.icon, size: widget.iconSize, color: Colors.white),
        ),
      ),
    );
  }
}
