import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Mirrors the HTML source's per-dot randomized animation parameters
/// (`dots = dotsData.map(d=>({...}))` in the splash `<script>` block).
/// Position/radius/color come from the real extracted `dotsData` array
/// (assets/data/splash_dots.json, 1237 entries); the rest are randomized
/// once per dot at load time exactly like the original — this was never
/// frame-deterministic in the HTML either, so this is a faithful port of
/// the algorithm, not an attempt to freeze one specific random draw.
class SplashDot {
  SplashDot({required this.ax, required this.ay, required this.r, required this.color, required math.Random rng})
      : phase = rng.nextDouble() * 2 * math.pi,
        speed = 0.6 + rng.nextDouble() * 1.1,
        windSpeed = 8 + rng.nextDouble() * 20,
        tX1 = 0.15 + rng.nextDouble() * 0.25,
        tX2 = 0.35 + rng.nextDouble() * 0.4,
        tY1 = 0.2 + rng.nextDouble() * 0.3,
        tY2 = 0.4 + rng.nextDouble() * 0.5,
        ampX = 6 + rng.nextDouble() * 14,
        ampY = 4 + rng.nextDouble() * 10,
        pX1 = rng.nextDouble() * 2 * math.pi,
        pX2 = rng.nextDouble() * 2 * math.pi,
        pY1 = rng.nextDouble() * 2 * math.pi,
        pY2 = rng.nextDouble() * 2 * math.pi,
        baseAlpha = 0.55 + rng.nextDouble() * 0.45,
        laneOff = (rng.nextDouble() - 0.5) * 40;

  final double ax, ay, r;
  final Color color;
  final double phase, speed, windSpeed, tX1, tX2, tY1, tY2, ampX, ampY, pX1, pX2, pY1, pY2, baseAlpha, laneOff;
}

Future<List<SplashDot>> loadSplashDots() async {
  final raw = await rootBundle.loadString('assets/data/splash_dots.json');
  final list = jsonDecode(raw) as List<dynamic>;
  final rng = math.Random();
  return [
    for (final entry in list)
      SplashDot(
        ax: (entry[0] as num).toDouble(),
        ay: (entry[1] as num).toDouble(),
        r: (entry[2] as num).toDouble(),
        color: Color.fromARGB(255, (entry[3] as num).toInt(), (entry[4] as num).toInt(), (entry[5] as num).toInt()),
        rng: rng,
      ),
  ];
}

/// Natural (unscaled) size of splash_bg.png — matches the HTML's
/// `NATURAL_W = 1536, NATURAL_H = 1024` used to compute the same
/// cover-fit scale/offset for both the image and the particle field.
const Size splashNaturalSize = Size(1536, 1024);

/// Replicates the HTML source's per-frame `draw(t)` loop exactly:
/// sinusoidal alpha pulsing, two-axis turbulence, horizontal wind drift
/// with wraparound, and edge fade-out — see module docstring for why the
/// per-dot random seed isn't (and was never) frame-reproducible.
class SplashParticlesPainter extends CustomPainter {
  SplashParticlesPainter({required this.dots, required this.timeSeconds});

  final List<SplashDot> dots;
  final double timeSeconds;

  static const double _margin = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / splashNaturalSize.width, size.height / splashNaturalSize.height);
    final renderW = splashNaturalSize.width * scale;
    final renderH = splashNaturalSize.height * scale;
    final offX = (size.width - renderW) / 2;
    final offY = (size.height - renderH) / 2;
    final span = size.width + _margin * 2;

    final paint = Paint()..style = PaintingStyle.fill;
    for (final d in dots) {
      final tw = math.sin(timeSeconds * d.speed + d.phase);
      final alpha = math.max(0.0, d.baseAlpha * (0.4 + 0.6 * (tw * 0.5 + 0.5)));
      final turbX = math.sin(timeSeconds * d.tX1 + d.pX1) * d.ampX * 0.5 +
          math.sin(timeSeconds * d.tX2 + d.pX2) * d.ampX * 0.5;
      final turbY = math.sin(timeSeconds * d.tY1 + d.pY1) * d.ampY * 0.5 +
          math.cos(timeSeconds * d.tY2 + d.pY2) * d.ampY * 0.5;
      final anchorSx = offX + d.ax * scale;
      final sy = offY + d.ay * scale + turbY;
      var sx = (anchorSx + d.laneOff + timeSeconds * d.windSpeed + turbX + _margin) % span;
      if (sx < 0) sx += span;
      sx -= _margin;
      final edgeFade = math.min(1.0, math.min(sx, size.width - sx) / 60);
      final a = math.max(0.0, math.min(1.0, alpha * math.max(0.0, edgeFade)));
      if (a <= 0.01) continue;
      final sr = math.max(0.5, d.r * scale * 1.15);
      paint.color = d.color.withValues(alpha: a);
      canvas.drawCircle(Offset(sx, sy), sr, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SplashParticlesPainter oldDelegate) => true;
}
