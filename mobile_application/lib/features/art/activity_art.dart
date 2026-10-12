import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/activity.dart';

/// The colours of one kind of activity's scene: the sky it sits in and the three accents drawn on it.
class ArtPalette {
  const ArtPalette(this.skyTop, this.skyBottom, this.a, this.b, this.c, this.ink);

  final Color skyTop;
  final Color skyBottom;
  final Color a;
  final Color b;
  final Color c;

  /// A deep tone of the scene, for text and chips set against it.
  final Color ink;
}

/// A small painted, gently moving scene for each kind of activity: a winding path for movement, two
/// overlapping circles for company, ribbons of paint, hills and trees, a breathing lotus, an open book,
/// a card ticking itself off. Drawn in code (no asset pipeline), full colour, and slow enough to be calm.
///
/// [progress] fixes the moment drawn (0..1), for previews and tests; leave it null to animate.
class ActivityArt extends StatefulWidget {
  const ActivityArt({
    required this.type,
    this.animate = true,
    this.progress,
    this.radius = 0,
    this.circle = false,
    super.key,
  });

  final ActivityType type;
  final bool animate;
  final double? progress;

  /// Corner radius of the scene's frame. [circle] clips it to a circle instead.
  final double radius;
  final bool circle;

  static ArtPalette paletteFor(ActivityType type) => switch (type) {
        ActivityType.movement => const ArtPalette(Color(0xFFFFE3C2), Color(0xFFFFF6E6), Color(0xFFFFA94D), Color(0xFFE8814A), Color(0xFFF7C98B), Color(0xFF8A4F1D)),
        ActivityType.social => const ArtPalette(Color(0xFFFFDFD6), Color(0xFFFFF3EC), Color(0xFFFF8F70), Color(0xFFFFC15E), Color(0xFFFFE0A0), Color(0xFF9C4A30)),
        ActivityType.creative => const ArtPalette(Color(0xFFEFE0FF), Color(0xFFFFEFF6), Color(0xFF8A5FBF), Color(0xFFFF7E91), Color(0xFFFFB84D), Color(0xFF5E3A91)),
        ActivityType.nature => const ArtPalette(Color(0xFFDDF2DA), Color(0xFFFFF6E3), Color(0xFF5FA463), Color(0xFF3F7F4A), Color(0xFF9CCB7E), Color(0xFF2F6B3A)),
        ActivityType.mindfulness => const ArtPalette(Color(0xFFD6EEF5), Color(0xFFF4FAF6), Color(0xFF3F9AB5), Color(0xFFF2A6B8), Color(0xFF8FD1D8), Color(0xFF23607A)),
        ActivityType.learning => const ArtPalette(Color(0xFFFFEBC4), Color(0xFFFFF8EA), Color(0xFFD99A2B), Color(0xFFB8741F), Color(0xFFFFD27A), Color(0xFF7A4E10)),
        ActivityType.productivity => const ArtPalette(Color(0xFFE4E0F8), Color(0xFFF8F4FF), Color(0xFF6A63A8), Color(0xFF8E85D6), Color(0xFFB9B2F0), Color(0xFF3F3A7A)),
      };

  @override
  State<ActivityArt> createState() => _ActivityArtState();
}

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class _ActivityArtState extends State<ActivityArt> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    if (widget.animate && widget.progress == null && !_isTestEnvironment) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: ActivityArtPainter(widget.type, widget.progress ?? _controller.value),
        ),
      ),
    );
    if (widget.circle) return ClipOval(child: art);
    if (widget.radius > 0) return ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: art);
    return art;
  }
}

double _s(double t, [double phase = 0, double speed = 1]) => math.sin((t * speed + phase) * 2 * math.pi);

class ActivityArtPainter extends CustomPainter {
  ActivityArtPainter(this.type, this.t);

  final ActivityType type;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = ActivityArt.paletteFor(type);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [p.skyTop, p.skyBottom]),
    );
    switch (type) {
      case ActivityType.movement:
        _movement(canvas, size, p);
      case ActivityType.social:
        _social(canvas, size, p);
      case ActivityType.creative:
        _creative(canvas, size, p);
      case ActivityType.nature:
        _nature(canvas, size, p);
      case ActivityType.mindfulness:
        _mindfulness(canvas, size, p);
      case ActivityType.learning:
        _learning(canvas, size, p);
      case ActivityType.productivity:
        _productivity(canvas, size, p);
    }
  }

  @override
  bool shouldRepaint(covariant ActivityArtPainter old) => old.t != t || old.type != type;

  // ---- shared pieces -------------------------------------------------------------------------

  void _glow(Canvas c, Offset o, double r, Color color, [double a = 0.55]) {
    c.drawCircle(
      o,
      r,
      Paint()..shader = ui.Gradient.radial(o, r, [color.withValues(alpha: a), color.withValues(alpha: 0)]),
    );
  }

  void _hill(Canvas c, Size s, double baseY, double amp, double phase, double freq, Color color) {
    final path = Path()
      ..moveTo(0, s.height)
      ..lineTo(0, baseY);
    const n = 48;
    for (var i = 0; i <= n; i++) {
      final x = s.width * i / n;
      path.lineTo(x, baseY + amp * math.sin(i / n * freq * 2 * math.pi + phase));
    }
    path
      ..lineTo(s.width, s.height)
      ..close();
    c.drawPath(path, Paint()..color = color);
  }

  void _bird(Canvas c, Offset o, double size, Color color, double flap) {
    final w = size * (0.6 + 0.4 * flap.abs());
    final path = Path()
      ..moveTo(o.dx - size, o.dy)
      ..quadraticBezierTo(o.dx - size * 0.5, o.dy - w, o.dx, o.dy)
      ..quadraticBezierTo(o.dx + size * 0.5, o.dy - w, o.dx + size, o.dy);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.22
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _sparkle(Canvas c, Offset o, double r, Color color) {
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r);
    c.drawPath(path, Paint()..color = color);
  }

  void _heart(Canvas c, Offset o, double r, Color color) {
    final path = Path()
      ..moveTo(o.dx, o.dy + r)
      ..cubicTo(o.dx - r * 1.6, o.dy - r * 0.2, o.dx - r * 0.7, o.dy - r * 1.3, o.dx, o.dy - r * 0.45)
      ..cubicTo(o.dx + r * 0.7, o.dy - r * 1.3, o.dx + r * 1.6, o.dy - r * 0.2, o.dx, o.dy + r);
    c.drawPath(path, Paint()..color = color);
  }

  void _leaf(Canvas c, Offset o, double r, double angle, Color color) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(angle);
    final path = Path()
      ..moveTo(-r, 0)
      ..quadraticBezierTo(0, -r * 0.9, r, 0)
      ..quadraticBezierTo(0, r * 0.9, -r, 0);
    c.drawPath(path, Paint()..color = color);
    c.drawLine(
      Offset(-r * 0.8, 0),
      Offset(r * 0.8, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = r * 0.08,
    );
    c.restore();
  }

  Offset _on(ui.PathMetric m, double frac) {
    final tan = m.getTangentForOffset(m.length * frac.clamp(0.0, 1.0));
    return tan?.position ?? Offset.zero;
  }

  // ---- movement: a path climbing the hills, with a light travelling it ----------------------

  void _movement(Canvas c, Size s, ArtPalette p) {
    final u = math.min(s.width, s.height);
    final sun = Offset(s.width * 0.74, s.height * 0.3);
    _glow(c, sun, u * 0.55, const Color(0xFFFFC14D), 0.5 + 0.1 * _s(t));
    c.drawCircle(sun, u * 0.12, Paint()..color = const Color(0xFFFFB547));
    c.drawCircle(sun, u * 0.09, Paint()..color = const Color(0xFFFFD27A));

    _hill(c, s, s.height * 0.6, u * 0.05, 0.6, 1.2, p.c.withValues(alpha: 0.85));
    _hill(c, s, s.height * 0.72, u * 0.06, 2.4, 0.9, const Color(0xFFEFA86B));
    _hill(c, s, s.height * 0.86, u * 0.04, 4.0, 1.4, const Color(0xFFE08B55));

    final path = Path()
      ..moveTo(s.width * 0.12, s.height * 1.02)
      ..cubicTo(s.width * 0.42, s.height * 0.92, s.width * 0.18, s.height * 0.78, s.width * 0.48, s.height * 0.7)
      ..cubicTo(s.width * 0.66, s.height * 0.65, s.width * 0.56, s.height * 0.6, s.width * 0.64, s.height * 0.58);
    // a road that narrows into the distance
    final road = path.computeMetrics().first;
    final left = <Offset>[], right = <Offset>[];
    const steps = 60;
    for (var i = 0; i <= steps; i++) {
      final f = i / steps;
      final tan = road.getTangentForOffset(road.length * f)!;
      final normal = Offset(-tan.vector.dy, tan.vector.dx) / tan.vector.distance;
      final half = u * (0.085 * (1 - f) + 0.012);
      left.add(tan.position + normal * half);
      right.add(tan.position - normal * half);
    }
    final shape = Path()..moveTo(left.first.dx, left.first.dy);
    for (final o in left.skip(1)) {
      shape.lineTo(o.dx, o.dy);
    }
    for (final o in right.reversed) {
      shape.lineTo(o.dx, o.dy);
    }
    shape.close();
    c.drawPath(shape, Paint()..color = const Color(0xFFFFEFD3));
    c.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFF2C58E),
    );

    final m = path.computeMetrics().first;
    // footprints appear behind the light and fade
    for (var i = 0; i < 9; i++) {
      final f = 0.06 + i * 0.1;
      final since = (t - f + 1) % 1.0;
      final a = (1 - since * 1.6).clamp(0.0, 1.0);
      if (a <= 0 || since > 0.6) continue;
      final o = _on(m, f) + Offset(i.isEven ? -u * 0.012 : u * 0.012, 0);
      c.drawOval(
        Rect.fromCenter(center: o, width: u * 0.03, height: u * 0.045),
        Paint()..color = const Color(0xFFD9824A).withValues(alpha: 0.55 * a),
      );
    }
    final pos = _on(m, t);
    final r = u * (0.055 - 0.025 * t);
    for (var i = 5; i >= 1; i--) {
      final o = _on(m, (t - i * 0.025 + 1) % 1.0);
      c.drawCircle(o, r * (1 - i * 0.12), Paint()..color = Colors.white.withValues(alpha: 0.5 - i * 0.08));
    }
    _glow(c, pos, r * 3.2, const Color(0xFFFFE08A), 0.8);
    c.drawCircle(pos, r, Paint()..color = Colors.white);

    for (var i = 0; i < 3; i++) {
      final bx = ((t * 0.5 + i * 0.3) % 1.0) * (s.width + 60) - 30;
      _bird(c, Offset(bx, s.height * (0.2 + 0.07 * i) + 4 * _s(t, i * 0.3, 2)), u * (0.035 - i * 0.005), const Color(0xFF9A5B2D).withValues(alpha: 0.7), _s(t, i * 0.2, 6));
    }
  }

  // ---- social: two circles drawing together, little hearts rising -------------------------------

  void _social(Canvas c, Size s, ArtPalette p) {
    final u = math.min(s.width, s.height);
    final cx = s.width / 2, cy = s.height * 0.52;
    for (var i = 0; i < 10; i++) {
      final o = Offset(s.width * ((i * 0.37 + 0.1) % 1.0), s.height * ((i * 0.53 + 0.2 + 0.03 * _s(t, i * 0.1)) % 1.0));
      _glow(c, o, u * (0.06 + 0.02 * (i % 3)), Colors.white, 0.5);
    }
    final gap = u * 0.17 - u * 0.035 * _s(t);
    final r = u * 0.27;
    final left = Offset(cx - gap, cy), right = Offset(cx + gap, cy);
    final a = Path()..addOval(Rect.fromCircle(center: left, radius: r));
    final b = Path()..addOval(Rect.fromCircle(center: right, radius: r));
    c.drawPath(a, Paint()..color = p.a.withValues(alpha: 0.78));
    c.drawPath(b, Paint()..color = p.b.withValues(alpha: 0.82));
    c.drawPath(Path.combine(PathOperation.intersect, a, b), Paint()..color = const Color(0xFFFFEFC9));
    // a small smile on each, kept abstract
    for (final side in [left, right]) {
      c.drawArc(
        Rect.fromCenter(center: side + Offset(side == left ? -u * 0.06 : u * 0.06, u * 0.03), width: u * 0.12, height: u * 0.08),
        0.2,
        math.pi - 0.4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = u * 0.014
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
    for (var i = 0; i < 6; i++) {
      final f = (t + i / 6) % 1.0;
      final o = Offset(cx + math.sin((f * 2 + i) * math.pi) * u * 0.08, cy - f * u * 0.5);
      final al = math.sin(f * math.pi).clamp(0.0, 1.0);
      _heart(c, o, u * (0.022 + 0.01 * (i % 2)), (i.isEven ? p.a : p.b).withValues(alpha: 0.9 * al));
    }
    final orbit = Offset(cx + math.cos(t * 2 * math.pi) * u * 0.42, cy - u * 0.05 + math.sin(t * 2 * math.pi) * u * 0.16);
    _glow(c, orbit, u * 0.12, const Color(0xFFFFE0A0), 0.7);
    c.drawCircle(orbit, u * 0.045, Paint()..color = Colors.white);
  }

  // ---- creative: ribbons of paint drawing themselves ---------------------------------------------

  void _creative(Canvas c, Size s, ArtPalette p) {
    final u = math.min(s.width, s.height);
    _glow(c, Offset(s.width * 0.8, s.height * 0.2), u * 0.5, const Color(0xFFFFD8F0), 0.6);
    final colors = [p.a, p.b, p.c];
    for (var i = 0; i < 3; i++) {
      final y = s.height * (0.34 + 0.17 * i);
      final path = Path()
        ..moveTo(s.width * 0.08, y + u * 0.05)
        ..cubicTo(s.width * 0.32, y - u * 0.2, s.width * 0.45, y + u * 0.22, s.width * 0.62, y)
        ..cubicTo(s.width * 0.76, y - u * 0.16, s.width * 0.86, y + u * 0.08, s.width * 0.94, y - u * 0.04);
      final m = path.computeMetrics().first;
      final f = (t * 1.0 + i * 0.22) % 1.0;
      final draw = Curves.easeInOut.transform((f / 0.7).clamp(0.0, 1.0));
      final fade = f < 0.82 ? 1.0 : (1 - (f - 0.82) / 0.18).clamp(0.0, 1.0);
      final part = m.extractPath(0, m.length * draw);
      c.drawPath(
        part,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = u * 0.075
          ..color = colors[i].withValues(alpha: 0.9 * fade),
      );
      c.drawPath(
        part,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = u * 0.02
          ..color = Colors.white.withValues(alpha: 0.35 * fade),
      );
      final head = _on(m, draw);
      c.drawCircle(head, u * 0.05, Paint()..color = colors[i].withValues(alpha: fade));
      for (var k = 0; k < 4; k++) {
        final ang = k * 1.7 + i;
        c.drawCircle(head + Offset(math.cos(ang), math.sin(ang)) * u * (0.09 + 0.02 * k), u * 0.012 * (4 - k) / 2, Paint()..color = colors[(i + k) % 3].withValues(alpha: 0.7 * fade));
      }
    }
    for (var i = 0; i < 5; i++) {
      final o = Offset(s.width * ((0.15 + i * 0.2) % 1.0), s.height * (0.15 + 0.08 * math.sin(i * 2.0)));
      final tw = 0.5 + 0.5 * _s(t, i * 0.2, 2);
      _sparkle(c, o, u * 0.035 * tw, Colors.white.withValues(alpha: 0.9));
    }
  }

  // ---- nature: hills, swaying trees, drifting leaves ---------------------------------------------

  void _nature(Canvas c, Size s, ArtPalette p) {
    final u = math.min(s.width, s.height);
    final sun = Offset(s.width * 0.25, s.height * 0.26);
    _glow(c, sun, u * 0.5, const Color(0xFFFFE08A), 0.65);
    c.drawCircle(sun, u * 0.09, Paint()..color = const Color(0xFFFFD36B));
    _hill(c, s, s.height * 0.58, u * 0.05, 1.0, 1.1, const Color(0xFFBFE0A8));
    _hill(c, s, s.height * 0.7, u * 0.06, 3.2, 0.8, p.c);
    _hill(c, s, s.height * 0.84, u * 0.04, 5.0, 1.3, p.a);

    void tree(double x, double base, double scale, double phase) {
      c.save();
      c.translate(x, base);
      c.rotate(0.03 * _s(t, phase, 1));
      final h = u * 0.3 * scale;
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-u * 0.012 * scale, -h * 0.5, u * 0.024 * scale, h * 0.5), const Radius.circular(3)),
        Paint()..color = const Color(0xFF7A5A3A),
      );
      for (final d in [
        (const Offset(-0.07, -0.62), 0.12, p.b),
        (const Offset(0.07, -0.64), 0.12, p.b),
        (const Offset(0, -0.78), 0.14, p.a),
        (const Offset(0, -0.56), 0.11, p.a),
      ]) {
        c.drawCircle(Offset(d.$1.dx * u * scale, d.$1.dy * h * 1.2), d.$2 * u * scale, Paint()..color = d.$3);
      }
      c.restore();
    }

    tree(s.width * 0.62, s.height * 0.8, 0.8, 0.0);
    tree(s.width * 0.82, s.height * 0.76, 0.6, 0.3);
    tree(s.width * 0.45, s.height * 0.84, 1.0, 0.6);

    for (var i = 0; i < 5; i++) {
      final f = (t + i / 5) % 1.0;
      final o = Offset(s.width * (0.15 + 0.7 * ((i * 0.37) % 1.0)) + math.sin((f * 3 + i) * math.pi) * u * 0.06, s.height * (0.1 + f * 0.8));
      _leaf(c, o, u * 0.03, f * 6 + i, (i.isEven ? const Color(0xFFE9B04A) : p.c).withValues(alpha: 0.95));
    }
    for (var i = 0; i < 2; i++) {
      final bx = ((t * 0.4 + i * 0.5) % 1.0) * (s.width + 60) - 30;
      _bird(c, Offset(bx, s.height * (0.3 + 0.08 * i)), u * 0.032, const Color(0xFF4F6B4A).withValues(alpha: 0.7), _s(t, i * 0.3, 6));
    }
  }

  // ---- mindfulness: a lotus opening and closing with the breath ------------------------------------

  void _mindfulness(Canvas c, Size s, ArtPalette p) {
    final u = math.min(s.width, s.height);
    final centre = Offset(s.width / 2, s.height * 0.54);
    final breath = 0.5 + 0.5 * _s(t, -0.25); // 0..1, in and out
    _glow(c, centre, u * (0.55 + 0.1 * breath), p.c, 0.6);
    for (var i = 0; i < 4; i++) {
      final r = u * (0.16 + 0.1 * i) * (0.94 + 0.08 * breath);
      c.drawCircle(centre, r, Paint()..color = p.a.withValues(alpha: 0.06 + 0.02 * (3 - i)));
      c.drawCircle(
        centre,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.7 - i * 0.12),
      );
    }
    const petals = 8;
    for (var i = 0; i < petals; i++) {
      final ang = i / petals * 2 * math.pi - math.pi / 2;
      c.save();
      c.translate(centre.dx, centre.dy);
      c.rotate(ang);
      final len = u * (0.2 + 0.04 * breath);
      final wid = u * (0.075 + 0.015 * breath);
      final rect = Rect.fromCenter(center: Offset(len * 0.62, 0), width: len, height: wid * 2);
      final grad = ui.Gradient.linear(Offset.zero, Offset(len * 1.1, 0), [p.b.withValues(alpha: 0.95), p.a.withValues(alpha: 0.9)]);
      c.drawOval(rect, Paint()..shader = grad);
      c.restore();
    }
    c.drawCircle(centre, u * 0.05, Paint()..color = const Color(0xFFFFE9A8));
    _glow(c, centre, u * 0.14, Colors.white, 0.8);
    for (var i = 0; i < 12; i++) {
      final f = (t * 0.6 + i / 12) % 1.0;
      final o = Offset(s.width * ((i * 0.31 + 0.07) % 1.0) + math.sin((f * 2 + i) * math.pi) * 6, s.height * (1.05 - f * 1.1));
      c.drawCircle(o, u * (0.008 + 0.006 * (i % 3)), Paint()..color = Colors.white.withValues(alpha: 0.8 * math.sin(f * math.pi)));
    }
  }

  // ---- learning: an open book letting go of small lights --------------------------------------------

  void _learning(Canvas c, Size s, ArtPalette p) {
    final u = math.min(s.width, s.height);
    final cx = s.width / 2, cy = s.height * 0.66;
    _glow(c, Offset(cx, cy - u * 0.2), u * 0.6, const Color(0xFFFFE08A), 0.55);

    final stars = <Offset>[
      Offset(cx - u * 0.3, cy - u * 0.42),
      Offset(cx - u * 0.12, cy - u * 0.58),
      Offset(cx + u * 0.08, cy - u * 0.44),
      Offset(cx + u * 0.26, cy - u * 0.6),
      Offset(cx + u * 0.34, cy - u * 0.36),
    ];
    final line = Paint()
      ..color = p.a.withValues(alpha: 0.45)
      ..strokeWidth = 1.4;
    for (var i = 0; i < stars.length - 1; i++) {
      final a = 0.5 + 0.5 * _s(t, i * 0.17, 1);
      line.color = p.a.withValues(alpha: 0.2 + 0.35 * a);
      c.drawLine(stars[i], stars[i + 1], line);
    }
    for (var i = 0; i < stars.length; i++) {
      final tw = 0.6 + 0.4 * _s(t, i * 0.21, 2);
      _glow(c, stars[i], u * 0.07, const Color(0xFFFFD27A), 0.8 * tw);
      _sparkle(c, stars[i], u * 0.04 * tw + u * 0.01, Colors.white);
    }

    final page = Paint()..color = const Color(0xFFFFFBF1);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = p.b.withValues(alpha: 0.7);
    Path half(double dir) => Path()
      ..moveTo(cx, cy + u * 0.12)
      ..quadraticBezierTo(cx + dir * u * 0.16, cy + u * 0.06, cx + dir * u * 0.34, cy + u * 0.12)
      ..lineTo(cx + dir * u * 0.34, cy - u * 0.14)
      ..quadraticBezierTo(cx + dir * u * 0.16, cy - u * 0.2, cx, cy - u * 0.14)
      ..close();
    c.drawPath(
      Path()
        ..moveTo(cx, cy + u * 0.16)
        ..lineTo(cx - u * 0.37, cy + u * 0.16)
        ..lineTo(cx - u * 0.37, cy - u * 0.1)
        ..lineTo(cx + u * 0.37, cy - u * 0.1)
        ..lineTo(cx + u * 0.37, cy + u * 0.16)
        ..close(),
      Paint()..color = p.b,
    );
    c.drawPath(half(-1), page);
    c.drawPath(half(1), page);
    c.drawPath(half(-1), edge);
    c.drawPath(half(1), edge);
    final ink = Paint()
      ..color = p.a.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = cy - u * 0.08 + i * u * 0.05;
      c.drawLine(Offset(cx - u * 0.29, y), Offset(cx - u * 0.06, y + u * 0.012), ink);
    }
    // a page turning
    final flip = (t * 2) % 1.0;
    final k = math.cos(flip * math.pi);
    final x = cx + k * u * 0.3;
    final turning = Path()
      ..moveTo(cx, cy + u * 0.12)
      ..quadraticBezierTo((cx + x) / 2, cy + u * 0.04 - u * 0.05 * math.sin(flip * math.pi), x, cy + u * 0.1)
      ..lineTo(x, cy - u * 0.14)
      ..quadraticBezierTo((cx + x) / 2, cy - u * 0.24 - u * 0.04 * math.sin(flip * math.pi), cx, cy - u * 0.14)
      ..close();
    c.drawPath(turning, Paint()..color = const Color(0xFFFFF6DE));
    c.drawPath(turning, edge);
    for (var i = 0; i < 4; i++) {
      final f = (t * 0.7 + i / 4) % 1.0;
      c.drawCircle(Offset(cx + math.sin((f * 2 + i) * math.pi) * u * 0.12, cy - u * 0.15 - f * u * 0.4), u * 0.01, Paint()..color = const Color(0xFFFFD27A).withValues(alpha: math.sin(f * math.pi)));
    }
  }

  // ---- productivity: a card ticking itself off -------------------------------------------------------

  void _productivity(Canvas c, Size s, ArtPalette p) {
    final u = math.min(s.width, s.height);
    final cx = s.width / 2, cy = s.height * 0.56;
    _glow(c, Offset(cx, cy), u * 0.6, p.c, 0.5);
    for (var i = 2; i >= 1; i--) {
      c.save();
      c.translate(cx + i * u * 0.035, cy + i * u * 0.03);
      c.rotate(i * 0.06 * (i.isEven ? -1 : 1));
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * 0.56, height: u * 0.62), Radius.circular(u * 0.06)),
        Paint()..color = [p.c, p.b][i - 1].withValues(alpha: 0.55),
      );
      c.restore();
    }
    final card = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: u * 0.56, height: u * 0.62), Radius.circular(u * 0.06));
    c.drawShadow(Path()..addRRect(card), p.a.withValues(alpha: 0.4), 10, false);
    c.drawRRect(card, Paint()..color = Colors.white);

    final cycle = t % 1.0;
    for (var i = 0; i < 3; i++) {
      final y = cy - u * 0.17 + i * u * 0.17;
      final box = Rect.fromCenter(center: Offset(cx - u * 0.17, y), width: u * 0.1, height: u * 0.1);
      final done = ((cycle - 0.1 - i * 0.22) / 0.2).clamp(0.0, 1.0);
      final fadeOut = cycle > 0.92 ? 1 - (cycle - 0.92) / 0.08 : 1.0;
      c.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(u * 0.025)),
        Paint()..color = Color.lerp(const Color(0xFFEDEBF8), p.a, done)!.withValues(alpha: fadeOut),
      );
      if (done > 0) {
        final tick = Path()
          ..moveTo(box.left + box.width * 0.24, box.center.dy)
          ..lineTo(box.left + box.width * 0.44, box.center.dy + box.height * 0.2)
          ..lineTo(box.left + box.width * 0.78, box.center.dy - box.height * 0.2);
        final m = tick.computeMetrics().first;
        c.drawPath(
          m.extractPath(0, m.length * done),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = u * 0.016
            ..color = Colors.white.withValues(alpha: fadeOut),
        );
      }
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx - u * 0.07, y - u * 0.012, u * (0.24 - 0.04 * i), u * 0.024), Radius.circular(u * 0.012)),
        Paint()..color = Color.lerp(const Color(0xFFE6E2F4), p.c, done * 0.8)!,
      );
    }
    final ringC = Offset(cx + u * 0.3, cy - u * 0.36);
    final total = (cycle / 0.82).clamp(0.0, 1.0);
    c.drawCircle(
      ringC,
      u * 0.085,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.026
        ..color = Colors.white.withValues(alpha: 0.8),
    );
    c.drawArc(
      Rect.fromCircle(center: ringC, radius: u * 0.085),
      -math.pi / 2,
      total * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = u * 0.026
        ..color = p.a,
    );
    if (cycle > 0.78 && cycle < 0.98) {
      final k = (cycle - 0.78) / 0.2;
      for (var i = 0; i < 8; i++) {
        final ang = i / 8 * 2 * math.pi;
        c.drawCircle(ringC + Offset(math.cos(ang), math.sin(ang)) * u * (0.1 + 0.12 * k), u * 0.012 * (1 - k), Paint()..color = [p.a, p.b, const Color(0xFFFFB84D)][i % 3]);
      }
    }
  }
}
