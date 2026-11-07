import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../art/activity_art.dart';

bool get _inTest {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// A small looping picture of what a guided exercise does: a circle that breathes, a dot that travels a square,
/// five things lighting up one by one, a sprout, two ways of seeing the same thing. Drawn in code, so it stays
/// sharp at any size and matches the app's other scenes. Still (and cheap) when animations are off.
class GuideGlyph extends StatefulWidget {
  const GuideGlyph({required this.guide, this.size = 56, this.animate = true, super.key});

  final ExerciseGuide guide;
  final double size;
  final bool animate;

  @override
  State<GuideGlyph> createState() => _GuideGlyphState();
}

class _GuideGlyphState extends State<GuideGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  bool get _running => widget.animate && !_inTest;

  @override
  void initState() {
    super.initState();
    if (_running) _loop.repeat();
  }

  @override
  void didUpdateWidget(GuideGlyph old) {
    super.didUpdateWidget(old);
    if (_running && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!_running) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _loop.isAnimating) _loop.stop();
    final palette = ActivityArt.paletteFor(ActivityType.mindfulness);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _loop,
          builder: (context, _) => CustomPaint(
            painter: GuideGlyphPainter(guide: widget.guide, t: still ? 0.35 : _loop.value, palette: palette),
          ),
        ),
      ),
    );
  }
}

class GuideGlyphPainter extends CustomPainter {
  const GuideGlyphPainter({required this.guide, required this.t, required this.palette});

  final ExerciseGuide guide;

  /// Position in the loop, 0 to 1.
  final double t;
  final ArtPalette palette;

  static double _ease(double x) => x * x * (3 - 2 * x);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final u = size.shortestSide;
    switch (guide) {
      case ExerciseGuide.breathing:
        _orb(canvas, c, u, _ease(0.5 - 0.5 * math.cos(t * 2 * math.pi * 2)));
      case ExerciseGuide.longExhale:
        // In for 40% of the loop, out for 60%: the longer breath out.
        final p = (t * 2) % 1.0;
        _orb(canvas, c, u, p < 0.4 ? _ease(p / 0.4) : 1 - _ease((p - 0.4) / 0.6));
      case ExerciseGuide.boxBreathing:
        _box(canvas, c, u);
      case ExerciseGuide.grounding:
        _senses(canvas, c, u);
      case ExerciseGuide.gratitude:
        _sprout(canvas, c, u);
      case ExerciseGuide.reframe:
        _views(canvas, c, u);
    }
  }

  void _orb(Canvas canvas, Offset c, double u, double fill) {
    final core = u * (0.2 + 0.2 * fill);
    for (var i = 3; i >= 1; i--) {
      canvas.drawCircle(c, core + i * u * 0.05, Paint()..color = palette.c.withValues(alpha: 0.14 * (4 - i)));
    }
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = RadialGradient(
          colors: [palette.c, palette.a],
          center: const Alignment(-0.3, -0.35),
        ).createShader(Rect.fromCircle(center: c, radius: core)),
    );
  }

  void _box(Canvas canvas, Offset c, double u) {
    final half = u * 0.3;
    final rect = Rect.fromCenter(center: c, width: half * 2, height: half * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(u * 0.08)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.045
        ..color = palette.c.withValues(alpha: 0.7),
    );
    final side = (t * 4) % 4;
    final k = side.floor();
    final f = side - k;
    final corners = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
    final from = corners[k % 4];
    final to = corners[(k + 1) % 4];
    final dot = Offset.lerp(from, to, f)!;
    canvas.drawCircle(dot, u * 0.075, Paint()..color = palette.a);
  }

  void _senses(Canvas canvas, Offset c, double u) {
    // Five dots in an arc that light up one after another, then rest.
    final lit = (t * 7).floor().clamp(0, 5);
    for (var i = 0; i < 5; i++) {
      final angle = math.pi * (1.15 + 0.7 * i / 4);
      final p = c + Offset(math.cos(angle), math.sin(angle)) * (u * 0.34) + Offset(0, u * 0.2);
      final on = i < lit;
      canvas.drawCircle(p, u * (on ? 0.085 : 0.07), Paint()..color = on ? palette.a : palette.c.withValues(alpha: 0.35));
    }
  }

  void _sprout(Canvas canvas, Offset c, double u) {
    final grow = _ease((t * 1.6).clamp(0.0, 1.0));
    final base = c + Offset(0, u * 0.3);
    final top = base - Offset(0, u * 0.5 * grow);
    canvas.drawLine(
      base,
      top,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = u * 0.06
        ..color = palette.ink.withValues(alpha: 0.7),
    );
    final leaf = _ease(((t - 0.35) * 2.2).clamp(0.0, 1.0));
    for (final side in [-1, 1]) {
      canvas.save();
      canvas.translate(top.dx, top.dy + u * 0.08);
      canvas.rotate(side * 0.7);
      canvas.drawOval(
        Rect.fromLTWH(side == -1 ? -u * 0.3 * leaf : 0, -u * 0.07, u * 0.3 * leaf, u * 0.14),
        Paint()..color = palette.a,
      );
      canvas.restore();
    }
  }

  void _views(Canvas canvas, Offset c, double u) {
    // Two circles sliding past each other: the same thing, seen from a little further back.
    final shift = math.sin(t * 2 * math.pi) * u * 0.14;
    canvas.drawCircle(c + Offset(-u * 0.1 - shift, 0), u * 0.26, Paint()..color = palette.a.withValues(alpha: 0.65));
    canvas.drawCircle(c + Offset(u * 0.1 + shift, 0), u * 0.26, Paint()..color = palette.c.withValues(alpha: 0.65));
  }

  @override
  bool shouldRepaint(GuideGlyphPainter old) => old.t != t || old.guide != guide;
}
