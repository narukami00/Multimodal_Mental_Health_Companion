import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../exercises/guide_glyph.dart';
import '../forest/forest_card_scene.dart';

bool get _still {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// The soft rounded frame every onboarding picture sits in, so the new scenes match the older ones.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x1FB0782A), blurRadius: 24, spreadRadius: -8, offset: Offset(0, 12))],
      ),
      child: RepaintBoundary(child: child),
    );
  }
}

/// The real forest scene from the check-in card, with a young tree that grows while the page settles. The sky is the
/// one for the hour, so the picture matches the light outside.
class OnboardingForestScene extends StatefulWidget {
  const OnboardingForestScene({this.hour, super.key});

  /// Fixes the time of day for previews and tests. Defaults to now.
  final int? hour;

  @override
  State<OnboardingForestScene> createState() => _OnboardingForestSceneState();
}

class _OnboardingForestSceneState extends State<OnboardingForestScene> with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));

  @override
  void initState() {
    super.initState();
    if (_still) {
      _grow.value = 1;
    } else {
      _grow.forward();
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ForestPalette.forHour(widget.hour ?? DateTime.now().hour);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) _grow.value = 1;
    return _Frame(
      child: AnimatedBuilder(
        animation: _grow,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_grow.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              // The warm card colour the real check-in card has behind the scene.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: palette.left),
                ),
              ),
              CustomPaint(
                painter: ForestCardPainter(palette: palette, species: 0, stage: 2.4 + 3.6 * t, waterWaiting: false),
              ),
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                width: 120,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Check in,', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: palette.text, height: 1.15)),
                    Text('water a tree', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: palette.text, height: 1.15)),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .55), borderRadius: BorderRadius.circular(99)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Text('no streaks', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: palette.text)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A conversation on one side and a breathing circle on the other: talking it through, or trying something small.
class OnboardingChatScene extends StatefulWidget {
  const OnboardingChatScene({super.key});

  @override
  State<OnboardingChatScene> createState() => _OnboardingChatSceneState();
}

class _OnboardingChatSceneState extends State<OnboardingChatScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    if (!_still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce && _c.isAnimating) _c.stop();
    return _Frame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(painter: _ChatScenePainter(_still || reduce ? .35 : _c.value)),
          ),
          Positioned(
            right: 22,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .55),
                ),
                child: const Center(child: GuideGlyph(guide: ExerciseGuide.breathing, size: 74)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatScenePainter extends CustomPainter {
  const _ChatScenePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE6D6), Color(0xFFFFF3E4)],
      ).createShader(rect),
    );

    // Soft hills so the scene sits on something.
    final hill = Path()
      ..moveTo(0, h * .82)
      ..cubicTo(w * .25, h * .70, w * .55, h * .92, w, h * .76)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0xFFFFD9B8).withValues(alpha: .7));

    void bubble(Rect r, Color fill, {required bool tailLeft, required Color line}) {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(18));
      canvas.drawShadow(Path()..addRRect(rr), const Color(0x33B0782A), 6, false);
      canvas.drawRRect(rr, Paint()..color = fill);
      final tail = Path();
      if (tailLeft) {
        tail
          ..moveTo(r.left + 10, r.bottom - 2)
          ..lineTo(r.left - 2, r.bottom + 9)
          ..lineTo(r.left + 22, r.bottom - 2);
      } else {
        tail
          ..moveTo(r.right - 10, r.bottom - 2)
          ..lineTo(r.right + 2, r.bottom + 9)
          ..lineTo(r.right - 22, r.bottom - 2);
      }
      canvas.drawPath(tail, Paint()..color = fill);
      final p = Paint()
        ..color = line
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(r.left + 14, r.top + 17), Offset(r.right - 14, r.top + 17), p);
      canvas.drawLine(Offset(r.left + 14, r.top + 30), Offset(r.right - 38, r.top + 30), p);
    }

    // Their message, then the companion's gentle answer.
    bubble(Rect.fromLTWH(w * .06, h * .13, w * .40, 46), Colors.white, tailLeft: true, line: const Color(0xFFE8CFA9));
    bubble(Rect.fromLTWH(w * .14, h * .46, w * .36, 46), const Color(0xFFFFB534), tailLeft: false, line: const Color(0xFFFFE2A6));

    // Three dots that take turns, as if the companion is thinking.
    for (var i = 0; i < 3; i++) {
      final phase = (t * 3 - i * .12) % 1;
      final lift = math.sin(phase * math.pi) * 3.5;
      canvas.drawCircle(
        Offset(w * .12 + i * 11, h * .80 - lift),
        3.4,
        Paint()..color = const Color(0xFFFF7F50).withValues(alpha: .75),
      );
    }

    // A few small sparkles.
    final sparkle = Paint()..color = const Color(0xFFFFB534).withValues(alpha: .6);
    canvas.drawCircle(Offset(w * .56, h * .16), 3.5, sparkle);
    canvas.drawCircle(Offset(w * .94, h * .14), 4.5, sparkle);
    canvas.drawCircle(Offset(w * .60, h * .86), 3, Paint()..color = const Color(0xFFFF7F50).withValues(alpha: .5));
  }

  @override
  bool shouldRepaint(_ChatScenePainter old) => old.t != t;
}

/// A phone that keeps everything inside it: a padlock on the screen, with a copy leaving and a copy coming back.
class OnboardingDataScene extends StatefulWidget {
  const OnboardingDataScene({super.key});

  @override
  State<OnboardingDataScene> createState() => _OnboardingDataSceneState();
}

class _OnboardingDataSceneState extends State<OnboardingDataScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (!_still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce && _c.isAnimating) _c.stop();
    return _Frame(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _DataScenePainter(_still || reduce ? .3 : _c.value)),
      ),
    );
  }
}

class _DataScenePainter extends CustomPainter {
  const _DataScenePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE3F1D8), Color(0xFFF6F8E4)],
      ).createShader(rect),
    );
    final hill = Path()
      ..moveTo(0, h * .84)
      ..cubicTo(w * .3, h * .72, w * .7, h * .92, w, h * .78)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0xFFBFDDA6).withValues(alpha: .75));

    // The phone.
    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w / 2, h * .5), width: 84, height: 132),
      const Radius.circular(20),
    );
    canvas.drawShadow(Path()..addRRect(phone), const Color(0x40306A38), 10, false);
    canvas.drawRRect(phone, Paint()..color = const Color(0xFF4F8A52));
    final screen = RRect.fromRectAndRadius(phone.outerRect.deflate(6), const Radius.circular(15));
    canvas.drawRRect(screen, Paint()..color = const Color(0xFFFEFCE8));

    // The padlock on the screen.
    final c = screen.outerRect.center.translate(0, 4);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 11, c.dy - 4)
        ..lineTo(c.dx - 11, c.dy - 14)
        ..arcToPoint(Offset(c.dx + 11, c.dy - 14), radius: const Radius.circular(11), clockwise: true)
        ..lineTo(c.dx + 11, c.dy - 4),
      Paint()
        ..color = const Color(0xFF4F8A52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, 8), width: 38, height: 28), const Radius.circular(8)),
      Paint()..color = const Color(0xFF4F8A52),
    );
    canvas.drawCircle(c.translate(0, 6), 3.6, Paint()..color = const Color(0xFFFEFCE8));
    canvas.drawRect(Rect.fromCenter(center: c.translate(0, 11), width: 3.2, height: 8), Paint()..color = const Color(0xFFFEFCE8));

    // A copy drifts out to the right and another comes back from the left, one after the other.
    void paper(Offset at, double alpha, {required bool out}) {
      if (alpha <= 0) return;
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: at, width: 26, height: 32), const Radius.circular(6));
      canvas.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: alpha));
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = (out ? const Color(0xFFFFB534) : const Color(0xFFFF7F50)).withValues(alpha: alpha),
      );
      final line = Paint()
        ..color = const Color(0xFFE8CFA9).withValues(alpha: alpha)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(at.translate(-8, -6), at.translate(8, -6), line);
      canvas.drawLine(at.translate(-8, 1), at.translate(8, 1), line);
      canvas.drawLine(at.translate(-8, 8), at.translate(2, 8), line);
    }

    double fade(double p) => p < .15 ? p / .15 : (p > .85 ? (1 - p) / .15 : 1);
    final out = (t * 2) % 1;
    final back = (t * 2 + .5) % 1;
    paper(Offset(w / 2 + 52 + out * (w * .22), h * .42 - math.sin(out * math.pi) * 8), fade(out).clamp(0.0, 1.0), out: true);
    paper(Offset(w * .06 + back * (w * .22) + 14, h * .60 - math.sin(back * math.pi) * 8), fade(back).clamp(0.0, 1.0), out: false);

    final sparkle = Paint()..color = const Color(0xFF6FA372).withValues(alpha: .5);
    canvas.drawCircle(Offset(w * .12, h * .2), 4, sparkle);
    canvas.drawCircle(Offset(w * .88, h * .18), 3.2, sparkle);
  }

  @override
  bool shouldRepaint(_DataScenePainter old) => old.t != t;
}
