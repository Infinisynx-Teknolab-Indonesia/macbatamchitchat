import 'package:flutter/material.dart';
import 'retro_title_bar.dart' show kWindowCornerRadius;

/// Rounds the visual corners of the ENTIRE app window.
///
/// This works because every window in this app is configured with a
/// transparent OS-level background (see main.dart's WindowOptions) and no
/// native title bar (titleBarStyle: hidden) — so whatever we draw here
/// literally IS the window's visible shape. Clipping our content to a
/// rounded rect means the four corners outside that rect stay fully
/// transparent (showing the desktop through them), which reads as a
/// rounded window rather than a rounded rectangle floating inside a
/// square one.
///
/// Applied via MaterialApp's `builder` parameter so every screen in the
/// app gets it automatically — screens themselves don't need to think
/// about this at all.
class RoundedWindowFrame extends StatelessWidget {
  final Widget child;
  const RoundedWindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kWindowCornerRadius),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kWindowCornerRadius),
          border: Border.all(color: Colors.black.withOpacity(0.15), width: 1),
        ),
        child: child,
      ),
    );
  }
}
