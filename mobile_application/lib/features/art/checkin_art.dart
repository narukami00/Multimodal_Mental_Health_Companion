import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum CheckInKind { text, voice, video }

/// Painted, gently moving art for the three ways to check in: a pen writing, a voice rippling out, a
/// lens opening. Drawn in code like [ActivityArt]; [progress] fixes the moment for previews and tests.
class CheckInArt extends StatefulWidget {
  const CheckInArt({required this.kind, this.progress, this.radius = 0, super.key});

  final CheckInKind kind;
  final double? progress;
  final double radius;

  @override
  State<CheckInArt> createState() => _CheckInArtState();
}

bool get _testing {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class _CheckInArtState extends State<CheckInArt> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    if (widget.progress == null && !_testing) _controller.repeat();
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
          painter: CheckInArtPainter(widget.kind, widget.progress ?? _controller.value),
        ),
      ),
    );
    return widget.radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: art) : art;
  }
}

class CheckInArtPainter extends CustomPainter {
  CheckInArtPainter(this.kind, this.t);

  final CheckInKind kind;
  final double t;

  static (Color, Color) skyOf(CheckInKind k) => switch (k) {
        CheckInKind.text => (const Color(0xFFFFE6C9), const Color(0xFFFFF4E4)),
        CheckInKind.voice => (const Color(0xFFFFD9D2), const Color(0xFFFFF0E8)),
        CheckInKind.video => (const Color(0xFFE2DDFB), const Color(0xFFF6F2FF)),
      };

  void _glow(Canvas c, Offset o, double r, Color color, [double a = 0.6]) =>
      c.drawCircle(o, r, Paint()..shader = ui.Gradient.radial(o, r, [color.withValues(alpha: a), color.withValues(alpha: 0)]));

  void _sparkle(Canvas c, Offset o, double r, Color color) {
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r);
    c.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (top, bottom) = skyOf(kind);
    canvas.drawRect(Offset.zero & size, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [top, bottom]));
    switch (kind) {
      case CheckInKind.text:
        _text(canvas, size);
      case CheckInKind.voice:
        _voice(canvas, size);
      case CheckInKind.video:
        _video(canvas, size);
    }
  }

  void _text(Canvas c, Size s) {
    final u = math.min(s.width, s.height);
    final cx = s.width / 2, cy = s.height / 2;
    _glow(c, Offset(cx, cy), u * 0.6, const Color(0xFFFFC76B), 0.5);
    c.save();
    c.translate(cx, cy);
    c.rotate(-0.1);
    final page = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * 0.62, height: u * 0.74), Radius.circular(u * 0.06));
    c.drawShadow(Path()..addRRect(page), const Color(0xFFB4793A), 8, false);
    c.drawRRect(page, Paint()..color = const Color(0xFFFFFCF4));
    final margin = Paint()
      ..color = const Color(0xFFFFB5A8).withValues(alpha: 0.7)
      ..strokeWidth = 1.4;
    c.drawLine(Offset(-u * 0.2, -u * 0.34), Offset(-u * 0.2, u * 0.34), margin);
    const ink = Color(0xFF8A5A2B);
    Offset? head;
    for (var i = 0; i < 4; i++) {
      final y = -u * 0.2 + i * u * 0.13;
      final path = Path()..moveTo(-u * 0.15, y);
      const segs = 7;
      for (var k = 1; k <= segs; k++) {
        path.quadraticBezierTo(-u * 0.15 + (k - 0.5) * u * 0.4 / segs, y + (k.isEven ? -1 : 1) * u * 0.022, -u * 0.15 + k * u * 0.4 / segs, y);
      }
      final m = path.computeMetrics().first;
      final phase = (t * 4 - i).clamp(0.0, 1.0); // lines are written one after another
      final p = Curves.easeInOut.transform(phase);
      c.drawPath(
        m.extractPath(0, m.length * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = u * 0.016
          ..color = ink.withValues(alpha: 0.8),
      );
      if (phase > 0 && phase < 1) head = m.getTangentForOffset(m.length * p)?.position;
    }
    head ??= Offset(u * 0.25, u * 0.3);
    // the pen
    c.save();
    c.translate(head.dx, head.dy);
    c.rotate(0.9);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-u * 0.016, -u * 0.34, u * 0.032, u * 0.3), Radius.circular(u * 0.016)), Paint()..color = const Color(0xFFE8814A));
    c.drawPath(
      Path()
        ..moveTo(-u * 0.016, -u * 0.04)
        ..lineTo(u * 0.016, -u * 0.04)
        ..lineTo(0, u * 0.01)
        ..close(),
      Paint()..color = const Color(0xFF5A3A1C),
    );
    c.restore();
    c.restore();
    for (var i = 0; i < 4; i++) {
      final f = (t + i / 4) % 1.0;
      _sparkle(c, Offset((s.width * (0.15 + 0.2 * i)) % s.width, s.height * (0.9 - f * 0.7)), u * 0.03 * math.sin(f * math.pi), const Color(0xFFFFB534));
    }
  }

  void _voice(Canvas c, Size s) {
    final u = math.min(s.width, s.height);
    final cy = s.height / 2;
    final orb = Offset(s.width * 0.3, cy);
    for (var i = 0; i < 4; i++) {
      final f = (t * 1.5 + i / 4) % 1.0;
      c.drawCircle(
        orb,
        u * (0.1 + 0.5 * f),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = const Color(0xFFFF8F70).withValues(alpha: 0.6 * (1 - f)),
      );
    }
    _glow(c, orb, u * 0.4, const Color(0xFFFF9E80), 0.7);
    c.drawCircle(orb, u * 0.12, Paint()..shader = ui.Gradient.linear(orb - Offset(0, u * 0.12), orb + Offset(0, u * 0.12), [const Color(0xFFFFB86B), const Color(0xFFFF7F6A)]));
    c.drawCircle(orb - Offset(u * 0.03, u * 0.04), u * 0.035, Paint()..color = Colors.white.withValues(alpha: 0.6));
    const bars = 15;
    final x0 = s.width * 0.46, x1 = s.width * 0.96;
    for (var i = 0; i < bars; i++) {
      final f = i / (bars - 1);
      final env = math.sin(f * math.pi);
      final h = u * (0.05 + 0.34 * env * (0.5 + 0.5 * math.sin((t * 2 + f * 1.3) * 2 * math.pi + i * 0.7)).abs());
      final x = x0 + (x1 - x0) * f;
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, cy), width: u * 0.03, height: h), Radius.circular(u * 0.015));
      c.drawRRect(r, Paint()..color = Color.lerp(const Color(0xFFFF8F70), const Color(0xFFFFB534), f)!);
    }
  }

  void _video(Canvas c, Size s) {
    final u = math.min(s.width, s.height);
    final centre = Offset(s.width / 2, s.height / 2);
    _glow(c, centre, u * 0.6, const Color(0xFFB9ABFF), 0.55);
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = u * 0.022
      ..color = const Color(0xFF6A5BC2).withValues(alpha: 0.85);
    final b = u * 0.4, l = u * 0.12;
    for (final sx in [-1.0, 1.0]) {
      for (final sy in [-1.0, 1.0]) {
        final o = centre + Offset(sx * b, sy * b * 0.92);
        c.drawPath(
          Path()
            ..moveTo(o.dx - sx * l, o.dy)
            ..lineTo(o.dx, o.dy)
            ..lineTo(o.dx, o.dy - sy * l),
          corner,
        );
      }
    }
    final breathe = 1 + 0.03 * math.sin(t * 2 * math.pi);
    c.drawCircle(centre, u * 0.26 * breathe, Paint()..color = const Color(0xFF4B3E9E));
    c.drawCircle(centre, u * 0.21 * breathe, Paint()..shader = ui.Gradient.radial(centre, u * 0.21, [const Color(0xFF8B7CE6), const Color(0xFF3A2F86)]));
    for (var i = 0; i < 6; i++) {
      c.save();
      c.translate(centre.dx, centre.dy);
      c.rotate(i / 6 * 2 * math.pi + t * 2 * math.pi * 0.25);
      c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(u * 0.1, -u * 0.05, u * 0.17, 0)
          ..quadraticBezierTo(u * 0.1, u * 0.05, 0, 0),
        Paint()..color = const Color(0xFFD7CFFF).withValues(alpha: 0.18),
      );
      c.restore();
    }
    c.drawCircle(centre, u * 0.06, Paint()..color = const Color(0xFF1F1856));
    c.drawCircle(centre + Offset(-u * 0.07, -u * 0.08), u * 0.04, Paint()..color = Colors.white.withValues(alpha: 0.75));
    _sparkle(c, centre + Offset(u * 0.1, -u * 0.1), u * 0.03, Colors.white);
    final on = math.sin(t * 2 * math.pi * 2) > 0 ? 1.0 : 0.35;
    final dot = Offset(centre.dx + b - u * 0.04, centre.dy - b * 0.92 + u * 0.05);
    _glow(c, dot, u * 0.08, const Color(0xFFFF6B6B), 0.6 * on);
    c.drawCircle(dot, u * 0.022, Paint()..color = const Color(0xFFFF6B6B).withValues(alpha: on));
  }

  @override
  bool shouldRepaint(covariant CheckInArtPainter old) => old.t != t || old.kind != kind;
}
