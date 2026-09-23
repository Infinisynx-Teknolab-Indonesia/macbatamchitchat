import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/ym_theme.dart';

/// Notifikasi DI DALAM aplikasi (saat aplikasi terbuka): banner yang turun dari atas layar, suara, dan getar.
/// Suara mobile sengaja BERBEDA dari suara Windows (buzz.wav): message_mobile.wav dan buzz_mobile.wav.
/// (Notifikasi saat aplikasi di latar belakang / tertutup = push FCM dari server, tahap berikutnya.)
class MobileNotifier {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final AudioPlayer _messagePlayer = AudioPlayer();
  static final AudioPlayer _buzzPlayer = AudioPlayer();
  static OverlayEntry? _entry;
  static Timer? _timer;

  static Future<void> playMessageSound() async {
    try {
      await _messagePlayer.play(AssetSource('sounds/message_mobile.wav'));
    } catch (_) {}
  }

  static Future<void> playBuzzSound() async {
    try {
      await _buzzPlayer.play(AssetSource('sounds/buzz_mobile.wav'));
    } catch (_) {}
  }

  /// Pola getar khas Buzz: empat getaran kuat beruntun.
  static Future<void> vibrateBuzz() async {
    for (var i = 0; i < 4; i++) {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  /// Banner dari atas layar. Ketuk = buka chatnya; geser ke atas = tutup; hilang sendiri setelah 5 detik.
  static void showBanner({
    required String title,
    required String body,
    required VoidCallback onTap,
    bool buzz = false,
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    dismissBanner();
    final entry = OverlayEntry(
      builder: (context) => _TopBanner(
        title: title,
        body: body,
        buzz: buzz,
        onTap: () {
          dismissBanner();
          onTap();
        },
        onDismiss: dismissBanner,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(seconds: 5), dismissBanner);
    if (buzz) {
      playBuzzSound();
      vibrateBuzz();
    } else {
      playMessageSound();
      HapticFeedback.lightImpact();
    }
  }

  static void dismissBanner() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _TopBanner extends StatefulWidget {
  final String title;
  final String body;
  final bool buzz;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _TopBanner({
    required this.title,
    required this.body,
    required this.buzz,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(begin: const Offset(0, -1.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: slide,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Dismissible(
              key: const ValueKey('top-banner'),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismiss(),
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(16),
                color: widget.buzz ? YmColors.buzzRed : YmColors.titleBarStart,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(widget.buzz ? Icons.bolt : Icons.chat_bubble, color: Colors.white, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
