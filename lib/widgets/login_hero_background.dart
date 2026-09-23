import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/ym_theme.dart';

/// Full-bleed background for the login screen: a deep navy-to-violet sky,
/// a simple drawn city skyline with lit windows, a suspension bridge
/// silhouette, and water with light reflections. Entirely original vector
/// art (no stock photography), evoking Batam's coastal/bridge character.
class LoginHeroBackground extends StatelessWidget {
  const LoginHeroBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [YmColors.heroGradientTop, YmColors.heroGradientBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CustomPaint(painter: _SkylinePainter(), size: Size.infinite),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rnd = Random(7); // fixed seed so the skyline is stable, not re-randomized per frame

    // Water band at the bottom
    final waterTop = h * 0.72;
    final waterPaint = Paint()
      ..shader = LinearGradient(
        colors: [YmColors.heroGradientBottom.withOpacity(0.9), YmColors.heroGradientTop],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, waterTop, w, h - waterTop));
    canvas.drawRect(Rect.fromLTWH(0, waterTop, w, h - waterTop), waterPaint);

    // Distant building silhouettes
    final buildingPaint = Paint()..color = Colors.black.withOpacity(0.28);
    double x = -20;
    while (x < w + 20) {
      final bw = 30 + rnd.nextDouble() * 50;
      final bh = 60 + rnd.nextDouble() * 140;
      final rect = Rect.fromLTWH(x, waterTop - bh, bw, bh);
      canvas.drawRect(rect, buildingPaint);

      // A few lit windows per building
      final windowPaint = Paint()..color = const Color(0xFFFFD873).withOpacity(0.7);
      for (int i = 0; i < 6; i++) {
        final wx = rect.left + 6 + rnd.nextDouble() * (bw - 14);
        final wy = rect.top + 8 + rnd.nextDouble() * (bh - 16);
        if (rnd.nextBool()) {
          canvas.drawRect(Rect.fromLTWH(wx, wy, 3, 5), windowPaint);
        }
      }
      x += bw + 6;
    }

    // Suspension bridge silhouette, foreground, spanning the width
    final bridgePaint = Paint()
      ..color = Colors.black.withOpacity(0.45)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final pylon1X = w * 0.28;
    final pylon2X = w * 0.72;
    final pylonTop = h * 0.38;
    final deckY = h * 0.62;

    canvas.drawLine(Offset(pylon1X, pylonTop), Offset(pylon1X, deckY + 10), bridgePaint..strokeWidth = 6);
    canvas.drawLine(Offset(pylon2X, pylonTop), Offset(pylon2X, deckY + 10), bridgePaint);
    canvas.drawLine(Offset(-10, deckY), Offset(w + 10, deckY), bridgePaint..strokeWidth = 4);

    final cablePaint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..strokeWidth = 2;
    for (double t = 0; t <= 1; t += 0.12) {
      canvas.drawLine(
        Offset(pylon1X - (pylon1X * t), pylonTop + (deckY - pylonTop) * (1 - (1 - t) * (1 - t))),
        Offset(pylon1X - (pylon1X * t), deckY),
        cablePaint,
      );
      canvas.drawLine(
        Offset(pylon2X + ((w - pylon2X) * t), pylonTop + (deckY - pylonTop) * (1 - (1 - t) * (1 - t))),
        Offset(pylon2X + ((w - pylon2X) * t), deckY),
        cablePaint,
      );
    }

    // Water reflections (soft vertical light streaks)
    final reflectionPaint = Paint()..color = const Color(0xFFFFD873).withOpacity(0.15);
    for (double rx = 40; rx < w; rx += 90) {
      canvas.drawRect(Rect.fromLTWH(rx, waterTop, 3, h - waterTop), reflectionPaint);
    }

    // Soft moon/glow top-right
    final glowPaint = Paint()
      ..shader = RadialGradient(colors: [Colors.white.withOpacity(0.25), Colors.transparent])
          .createShader(Rect.fromCircle(center: Offset(w * 0.82, h * 0.16), radius: 90));
    canvas.drawCircle(Offset(w * 0.82, h * 0.16), 90, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
