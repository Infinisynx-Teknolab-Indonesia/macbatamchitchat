import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../theme/ym_theme.dart';

/// Full-screen "you got buzzed!" flash, matching the classic IM client
/// buzz effect — NOT a quiet SnackBar. Shown on the RECIPIENT's screen
/// when they receive a buzz, with sound. Can also be shown briefly to the
/// sender as confirmation their buzz landed.
///
/// Usage: call BuzzOverlay.show(context, from: 'wati99') from anywhere —
/// it inserts itself as a full-screen overlay and removes itself when done.
class BuzzOverlay {
  static final _player = AudioPlayer();

  static Future<void> show(BuildContext context, {required String from, bool playSound = true}) async {
    if (playSound) {
      try {
        await _player.play(AssetSource('sounds/buzz.wav'));
      } catch (_) {
        // best-effort — a missing/broken audio backend shouldn't block the visual buzz
      }
    }

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _BuzzFlash(from: from, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }
}

class _BuzzFlash extends StatefulWidget {
  final String from;
  final VoidCallback onDone;
  const _BuzzFlash({required this.from, required this.onDone});

  @override
  State<_BuzzFlash> createState() => _BuzzFlashState();
}

class _BuzzFlashState extends State<_BuzzFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Shake offset: fast back-and-forth for the first ~600ms, settle after.
        final t = _controller.value;
        final shakeProgress = (t < 0.7) ? (1 - t / 0.7) : 0.0;
        final dx = shakeProgress * 14 * ((t * 40).floor().isEven ? 1 : -1);

        // Flash opacity: pops in fast, fades out at the end.
        final opacity = t < 0.15 ? (t / 0.15) : (t > 0.75 ? (1 - (t - 0.75) / 0.25) : 1.0);

        return IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Container(
                color: YmColors.buzzRed.withOpacity(0.15),
                width: double.infinity,
                height: double.infinity,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    decoration: BoxDecoration(
                      color: YmColors.buzzRed,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: Colors.white, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          'BUZZ!',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'dari @${widget.from}',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
