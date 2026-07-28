import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import 'splash_particles.dart';

/// Splash screen built around the branded background image (logo,
/// wordmark, and all credit text are baked into the image itself — see
/// assets/images/splash_bg.png). This screen adds three things on top:
/// a soft glare sweep across the BAKERTILLY wordmark, a floating
/// wind-blown particle field over the image's own decorative sparkle
/// bands, and an Enter button that's the only way to advance (no
/// auto-advance — the screen holds until clicked).
///
/// The "DEVELOPED BY WEB SANCTUM" credit is baked into the image as
/// static pixels, but is still a real, clickable hyperlink here: an
/// invisible tappable region is positioned over that exact text (see
/// _WebSanctumLink) rather than drawing new text — the image's own text
/// is untouched.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// Natural-image region the glare sweeps across (the BAKERTILLY
/// wordmark), measured directly off assets/images/splash_bg.png.
const _glareBox = Rect.fromLTRB(407, 505, 1162, 592);

/// Natural-image region of the "DEVELOPED BY WEB SANCTUM" text, measured
/// directly off assets/images/splash_bg.png — used only to position the
/// invisible tap target, never to draw anything.
const _webSanctumTextBox = Rect.fromLTRB(584, 725, 974, 748);

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _revealController;
  late final AnimationController _glareController;
  late final AnimationController _fadeOutController;
  late final Ticker _particleTicker;

  Duration _elapsed = Duration.zero;
  List<SplashDot> _dots = [];
  bool _dotsReady = false;
  bool _advancing = false;
  bool _enterButtonVisible = false;

  static const _revealDuration = Duration(milliseconds: 1600);
  static const _revealDelay = Duration(milliseconds: 100);
  static const _dotsDelay = Duration(milliseconds: 300);
  static const _glareDuration = Duration(milliseconds: 5500);
  static const _glareDelay = Duration(seconds: 2);
  static const _fadeOutDuration = Duration(milliseconds: 700);
  static const _enterButtonDelay = Duration(milliseconds: 1700);

  @override
  void initState() {
    super.initState();

    _revealController = AnimationController(vsync: this, duration: _revealDuration);
    _glareController = AnimationController(vsync: this, duration: _glareDuration);
    _fadeOutController = AnimationController(vsync: this, duration: _fadeOutDuration);

    _particleTicker = createTicker((elapsed) => setState(() => _elapsed = elapsed));
    _particleTicker.start();

    loadSplashDots().then((dots) {
      if (!mounted) return;
      setState(() {
        _dots = dots;
        _dotsReady = true;
      });
    });

    Future.delayed(_revealDelay, () {
      if (mounted) _revealController.forward();
    });
    Future.delayed(_glareDelay, () {
      if (mounted) _glareController.repeat();
    });
    Future.delayed(_enterButtonDelay, () {
      if (mounted) setState(() => _enterButtonVisible = true);
    });
  }

  void _advance() {
    if (_advancing) return;
    _advancing = true;
    _fadeOutController.forward().whenComplete(() {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _particleTicker.dispose();
    _revealController.dispose();
    _glareController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final revealCurve = CurvedAnimation(parent: _revealController, curve: Curves.ease);
    final dotsOpacity = Duration(milliseconds: _elapsed.inMilliseconds - _dotsDelay.inMilliseconds);

    return Material(
      color: const Color(0xFF05070A),
      child: AnimatedBuilder(
        animation: Listenable.merge([_revealController, _glareController, _fadeOutController]),
        builder: (context, _) {
          final revealOpacity = revealCurve.value;
          final revealScale = ui.lerpDouble(1.04, 1.0, revealCurve.value)!;
          final brightness = ui.lerpDouble(0.7, 1.0, revealCurve.value)!;
          final overallOpacity = 1.0 - _fadeOutController.value;

          return Opacity(
            opacity: overallOpacity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: revealOpacity,
                      child: Transform.scale(
                        scale: revealScale,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(_brightnessMatrix(brightness)),
                          child: Image.asset('assets/images/splash_bg.png', fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    if (_dotsReady)
                      Opacity(
                        opacity: dotsOpacity.inMilliseconds <= 0
                            ? 0
                            : (dotsOpacity.inMilliseconds / _revealDuration.inMilliseconds).clamp(0.0, 1.0),
                        child: CustomPaint(
                          size: size,
                          painter: SplashParticlesPainter(
                            dots: _dots,
                            timeSeconds: _elapsed.inMilliseconds / 1000.0,
                          ),
                        ),
                      ),
                    _GlareSweep(size: size, progress: _glareController.value),
                    _WebSanctumLink(size: size),
                    Align(
                      alignment: const Alignment(0, 0.8),
                      child: AnimatedOpacity(
                        opacity: _enterButtonVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.ease,
                        child: _EnterButton(onPressed: _advance),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  List<double> _brightnessMatrix(double b) {
    return [
      b, 0, 0, 0, 0, //
      0, b, 0, 0, 0,
      0, 0, b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

/// The only way to leave the splash — no auto-advance.
class _EnterButton extends StatelessWidget {
  const _EnterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.accentOn,
        minimumSize: const Size(140, 44),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: const Text('Enter'),
    );
  }
}

/// Maps a natural-image Rect into screen space using the same cover-fit
/// scale/offset the background image itself renders with.
Rect _mapNaturalRect(Rect naturalRect, Size screenSize) {
  final scale = (screenSize.width / splashNaturalSize.width) > (screenSize.height / splashNaturalSize.height)
      ? screenSize.width / splashNaturalSize.width
      : screenSize.height / splashNaturalSize.height;
  final renderW = splashNaturalSize.width * scale;
  final renderH = splashNaturalSize.height * scale;
  final offX = (screenSize.width - renderW) / 2;
  final offY = (screenSize.height - renderH) / 2;
  return Rect.fromLTWH(
    offX + naturalRect.left * scale,
    offY + naturalRect.top * scale,
    naturalRect.width * scale,
    naturalRect.height * scale,
  );
}

/// The "DEVELOPED BY WEB SANCTUM" credit — originally baked into the
/// image's pixels like the rest of the credits, but painted out of the
/// image (see the asset's own history) and rebuilt as real text here so
/// "WEB SANCTUM" can be colored and the whole line can be a genuine
/// clickable hyperlink to https://websanctum.co/, rather than static
/// pixels with an invisible tap target over them.
///
/// Zooms in slightly on hover so it visually reads as interactive —
/// requested directly, since an inline text link with no visual hover
/// state is easy to miss.
class _WebSanctumLink extends StatefulWidget {
  const _WebSanctumLink({required this.size});

  final Size size;

  @override
  State<_WebSanctumLink> createState() => _WebSanctumLinkState();
}

class _WebSanctumLinkState extends State<_WebSanctumLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final rect = _mapNaturalRect(_webSanctumTextBox, widget.size);
    if (rect.width <= 0 || rect.height <= 0) return const SizedBox.shrink();
    final fontSize = rect.height * 0.6;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://websanctum.co/'), mode: LaunchMode.externalApplication),
            child: AnimatedScale(
              scale: _hovering ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: fontSize * 0.08,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  children: [
                    const TextSpan(text: 'DEVELOPED BY '),
                    TextSpan(
                      text: 'WEB SANCTUM',
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft diagonal glare that sweeps continuously across the BAKERTILLY
/// wordmark every 5.5s (no pause/hold — a held sweep read as the effect
/// getting stuck).
class _GlareSweep extends StatelessWidget {
  const _GlareSweep({required this.size, required this.progress});

  final Size size;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final box = _mapNaturalRect(_glareBox, size);
    if (box.width <= 0 || box.height <= 0) return const SizedBox.shrink();

    final t = Curves.easeInOut.transform(progress);
    final dx = ui.lerpDouble(-1.6 * box.width, 1.9 * box.width, t)!;

    return Positioned(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      child: ClipRect(
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.rotate(
            angle: 0.17,
            child: Container(
              width: box.width * 2.5,
              height: box.height * 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.42, 0.5, 0.58],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
