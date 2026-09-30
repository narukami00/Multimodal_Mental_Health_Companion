import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/activity.dart';

/// A drawn scene for an activity, used as the background of its card.
///
/// Drawn rather than shipped as an image so it scales cleanly to any card size
/// and can be animated without an asset pipeline. Each scene is a simple
/// figurative sketch — someone walking, reading, taking a note — which gives the
/// card a subject instead of a floating symbol.
class ActivityScene extends StatefulWidget {
  const ActivityScene({
    required this.type,
    required this.color,
    this.animate = true,
    super.key,
  });

  final ActivityType type;

  /// Stroke colour. Passed in so the card can tint it to its own palette.
  final Color color;
  final bool animate;

  @override
  State<ActivityScene> createState() => _ActivitySceneState();
}

class _ActivitySceneState extends State<ActivityScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate && !_isTestEnvironment) _controller.repeat();
  }

  @override
  void didUpdateWidget(ActivityScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different scene gets its own motion rather than inheriting a phase.
    if (oldWidget.type != widget.type) _controller.value = 0;
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
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _ScenePainter(
          type: widget.type,
          color: widget.color,
          progress: _controller.value,
        ),
      ),
    );
  }
}

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.type,
    required this.color,
    required this.progress,
  });

  final ActivityType type;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Fit the scene inside whatever box it is given, so the figure is always
    // whole. Cropping it to fill the card was what turned it into stray shapes.
    final side = math.min(size.width, size.height);
    final origin = Offset(
      (size.width - side) / 2,
      (size.height - side) / 2,
    );

    canvas.save();
    canvas.translate(origin.dx, origin.dy);

    // A soft shape behind the figure, so the art has mass even where the
    // strokes are thin.
    canvas.drawCircle(
      Offset(side * 0.5, side * 0.5),
      side * 0.42,
      Paint()..color = color.withValues(alpha: 0.09),
    );

    canvas.save();
    // A slow breathe, so the scene is alive without being busy.
    final breathe = 1 + math.sin(progress * 2 * math.pi) * 0.022;
    final sway = math.sin(progress * 2 * math.pi) * 0.012;
    canvas.translate(side * (0.5 + sway), side * 0.5);
    canvas.scale(breathe);
    canvas.translate(-side * 0.5, -side * 0.5);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.022
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.42);

    final fill = Paint()..color = color.withValues(alpha: 0.42);

    switch (type) {
      case ActivityType.movement:
        _walking(canvas, side, stroke, fill);
      case ActivityType.mindfulness:
        _seated(canvas, side, stroke, fill);
      case ActivityType.productivity:
        _noteTaking(canvas, side, stroke, fill);
      case ActivityType.learning:
        _reading(canvas, side, stroke, fill);
      case ActivityType.creative:
        _drawing(canvas, side, stroke, fill);
      case ActivityType.nature:
        _outdoors(canvas, side, stroke, fill);
      case ActivityType.social:
        _together(canvas, side, stroke, fill);
    }

    canvas.restore();
    canvas.restore();
  }

  /// Someone mid-stride.
  void _walking(Canvas canvas, double s, Paint stroke, Paint fill) {
    _head(canvas, s, const Offset(0.52, 0.20), fill);
    canvas.drawLine(
      const Offset(0.52, 0.28) * s,
      const Offset(0.48, 0.54) * s,
      stroke,
    );
    // Arms, one forward one back.
    canvas.drawLine(
      const Offset(0.51, 0.35) * s,
      const Offset(0.66, 0.43) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.51, 0.35) * s,
      const Offset(0.37, 0.42) * s,
      stroke,
    );
    // Legs, mid-stride.
    canvas.drawLine(
      const Offset(0.48, 0.54) * s,
      const Offset(0.58, 0.70) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.58, 0.70) * s,
      const Offset(0.64, 0.88) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.48, 0.54) * s,
      const Offset(0.37, 0.70) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.37, 0.70) * s,
      const Offset(0.29, 0.87) * s,
      stroke,
    );
    // Ground.
    canvas.drawLine(
      const Offset(0.20, 0.90) * s,
      const Offset(0.76, 0.90) * s,
      stroke,
    );
  }

  /// Sitting still, with ripples going out.
  void _seated(Canvas canvas, double s, Paint stroke, Paint fill) {
    _head(canvas, s, const Offset(0.50, 0.22), fill);
    canvas.drawLine(
      const Offset(0.50, 0.30) * s,
      const Offset(0.50, 0.58) * s,
      stroke,
    );
    // Crossed legs.
    canvas.drawLine(
      const Offset(0.50, 0.58) * s,
      const Offset(0.34, 0.70) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.34, 0.70) * s,
      const Offset(0.67, 0.70) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.67, 0.70) * s,
      const Offset(0.50, 0.58) * s,
      stroke,
    );
    // Hands resting.
    canvas.drawLine(
      const Offset(0.50, 0.40) * s,
      const Offset(0.36, 0.54) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.50, 0.40) * s,
      const Offset(0.64, 0.54) * s,
      stroke,
    );
    // Ripples.
    for (final r in [0.16, 0.26]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(0.50 * s, 0.78 * s), radius: r * s),
        math.pi * 1.15,
        math.pi * 0.7,
        false,
        stroke,
      );
    }
  }

  /// Sitting, writing on a pad on the lap.
  void _noteTaking(Canvas canvas, double s, Paint stroke, Paint fill) {
    _head(canvas, s, const Offset(0.44, 0.20), fill);
    canvas.drawLine(
      const Offset(0.44, 0.28) * s,
      const Offset(0.46, 0.56) * s,
      stroke,
    );

    // The pad, a slab across the lap. Drawn before the arm so the arm lands on
    // top of it rather than behind.
    final pad = Path()
      ..moveTo(0.32 * s, 0.60 * s)
      ..lineTo(0.66 * s, 0.55 * s)
      ..lineTo(0.70 * s, 0.69 * s)
      ..lineTo(0.36 * s, 0.75 * s)
      ..close();
    canvas.drawPath(pad, stroke);

    // Legs, bent under the pad.
    canvas.drawLine(
      const Offset(0.46, 0.56) * s,
      const Offset(0.40, 0.74) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.40, 0.74) * s,
      const Offset(0.32, 0.88) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.46, 0.56) * s,
      const Offset(0.58, 0.72) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.58, 0.72) * s,
      const Offset(0.64, 0.86) * s,
      stroke,
    );

    // The writing arm and the pencil, held up.
    canvas.drawLine(
      const Offset(0.45, 0.36) * s,
      const Offset(0.56, 0.48) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.56, 0.48) * s,
      const Offset(0.64, 0.39) * s,
      stroke,
    );

    canvas.drawLine(
      const Offset(0.22, 0.90) * s,
      const Offset(0.78, 0.90) * s,
      stroke,
    );
  }

  /// Sitting, reading an open book.
  void _reading(Canvas canvas, double s, Paint stroke, Paint fill) {
    _head(canvas, s, const Offset(0.40, 0.20), fill);
    canvas.drawLine(
      const Offset(0.40, 0.28) * s,
      const Offset(0.42, 0.56) * s,
      stroke,
    );

    // The open book, held up in front of the chest.
    final left = Path()
      ..moveTo(0.30 * s, 0.50 * s)
      ..lineTo(0.52 * s, 0.57 * s)
      ..lineTo(0.52 * s, 0.73 * s)
      ..lineTo(0.30 * s, 0.66 * s)
      ..close();
    final right = Path()
      ..moveTo(0.52 * s, 0.57 * s)
      ..lineTo(0.76 * s, 0.50 * s)
      ..lineTo(0.76 * s, 0.66 * s)
      ..lineTo(0.52 * s, 0.73 * s)
      ..close();
    canvas.drawPath(left, stroke);
    canvas.drawPath(right, stroke);

    // Arms reaching down to hold it.
    canvas.drawLine(
      const Offset(0.41, 0.36) * s,
      const Offset(0.36, 0.50) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.42, 0.42) * s,
      const Offset(0.66, 0.48) * s,
      stroke,
    );

    // Legs, folded.
    canvas.drawLine(
      const Offset(0.42, 0.56) * s,
      const Offset(0.36, 0.76) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.36, 0.76) * s,
      const Offset(0.30, 0.88) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.42, 0.56) * s,
      const Offset(0.54, 0.74) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.54, 0.74) * s,
      const Offset(0.60, 0.86) * s,
      stroke,
    );

    canvas.drawLine(
      const Offset(0.20, 0.90) * s,
      const Offset(0.80, 0.90) * s,
      stroke,
    );
  }

  /// Standing at an easel, painting.
  void _drawing(Canvas canvas, double s, Paint stroke, Paint fill) {
    // The easel: a surface and three legs.
    canvas.drawLine(
      const Offset(0.54, 0.26) * s,
      const Offset(0.92, 0.26) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.54, 0.26) * s,
      const Offset(0.92, 0.26) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.54, 0.60) * s,
      const Offset(0.92, 0.60) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.54, 0.26) * s,
      const Offset(0.54, 0.60) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.92, 0.26) * s,
      const Offset(0.92, 0.60) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.70, 0.60) * s,
      const Offset(0.66, 0.90) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.78, 0.60) * s,
      const Offset(0.84, 0.90) * s,
      stroke,
    );
    // Something already on the canvas.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(0.72 * s, 0.44 * s), radius: 0.10 * s),
      0,
      math.pi * 1.6,
      false,
      stroke,
    );

    // The painter, standing to the left.
    _head(canvas, s, const Offset(0.30, 0.26), fill);
    canvas.drawLine(
      const Offset(0.30, 0.34) * s,
      const Offset(0.32, 0.62) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.31, 0.42) * s,
      const Offset(0.48, 0.46) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.48, 0.46) * s,
      const Offset(0.56, 0.42) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.32, 0.62) * s,
      const Offset(0.26, 0.88) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.32, 0.62) * s,
      const Offset(0.40, 0.88) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.14, 0.90) * s,
      const Offset(0.94, 0.90) * s,
      stroke,
    );
  }

  /// Outdoors, under a tree.
  void _outdoors(Canvas canvas, double s, Paint stroke, Paint fill) {
    // Trunk and canopy.
    canvas.drawLine(
      const Offset(0.74, 0.30) * s,
      const Offset(0.74, 0.84) * s,
      stroke,
    );
    canvas.drawCircle(const Offset(0.74, 0.24) * s, 0.18 * s, stroke);
    canvas.drawCircle(const Offset(0.60, 0.30) * s, 0.12 * s, stroke);
    canvas.drawCircle(const Offset(0.88, 0.30) * s, 0.12 * s, stroke);
    // Someone standing under it.
    _head(canvas, s, const Offset(0.36, 0.36), fill);
    canvas.drawLine(
      const Offset(0.36, 0.44) * s,
      const Offset(0.36, 0.68) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.36, 0.52) * s,
      const Offset(0.25, 0.62) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.36, 0.52) * s,
      const Offset(0.47, 0.62) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.36, 0.68) * s,
      const Offset(0.29, 0.88) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.36, 0.68) * s,
      const Offset(0.43, 0.88) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.16, 0.90) * s,
      const Offset(0.86, 0.90) * s,
      stroke,
    );
  }

  /// Two people, talking.
  void _together(Canvas canvas, double s, Paint stroke, Paint fill) {
    _head(canvas, s, const Offset(0.32, 0.32), fill);
    canvas.drawLine(
      const Offset(0.32, 0.40) * s,
      const Offset(0.32, 0.66) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.32, 0.48) * s,
      const Offset(0.46, 0.54) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.53, 0.48) * s,
      const Offset(0.67, 0.54) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.32, 0.66) * s,
      const Offset(0.25, 0.86) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.32, 0.66) * s,
      const Offset(0.39, 0.86) * s,
      stroke,
    );

    _head(canvas, s, const Offset(0.68, 0.32), fill);
    canvas.drawLine(
      const Offset(0.68, 0.40) * s,
      const Offset(0.68, 0.66) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.68, 0.66) * s,
      const Offset(0.61, 0.86) * s,
      stroke,
    );
    canvas.drawLine(
      const Offset(0.68, 0.66) * s,
      const Offset(0.75, 0.86) * s,
      stroke,
    );
    // A word between them.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(0.50 * s, 0.30 * s), radius: 0.13 * s),
      math.pi * 1.15,
      math.pi * 0.7,
      false,
      stroke,
    );
  }

  void _head(Canvas canvas, double s, Offset at, Paint fill) {
    canvas.drawCircle(Offset(at.dx * s, at.dy * s), s * 0.062, fill);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.type != type ||
        oldDelegate.color != color;
  }
}
