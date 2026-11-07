import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/solace_palette.dart';
import 'page_back_button.dart';

/// Shared building blocks for the visual pages: a painted hero header, cards, rings, bars, stat tiles
/// and settings-style rows. Pages use these instead of long runs of text.

const kitInk = Color(0xFF3A3125);
const kitSoft = Color(0xFF6E6252);
const kitMuted = Color(0xFFA69883);
const kitLine = Color(0x143B2F26);
const kitBg = Color(0xFFFEFCE8);
const kitAmber = Color(0xFFFFB534);
const kitCoral = Color(0xFFFF7F50);

/// The scene painted in a [PageHero].
enum HeroScene { rhythm, noticed, support, contacts, privacy, permissions, memory, baseline, decisions, about, terms, faq, settings }

class _HeroPalette {
  const _HeroPalette(this.top, this.bottom, this.a, this.b, this.c, this.ink);

  final Color top;
  final Color bottom;
  final Color a;
  final Color b;
  final Color c;
  final Color ink;
}

_HeroPalette _paletteOf(HeroScene s) => switch (s) {
      HeroScene.rhythm => const _HeroPalette(Color(0xFFFFE6C2), Color(0xFFFFF6E6), Color(0xFFFFA94D), Color(0xFFE8814A), Color(0xFFFFD08A), Color(0xFF7A4318)),
      HeroScene.noticed => const _HeroPalette(Color(0xFFE0E3F8), Color(0xFFF6F3FF), Color(0xFF6E73C8), Color(0xFFFFB84D), Color(0xFFB9BDF0), Color(0xFF35397A)),
      HeroScene.support => const _HeroPalette(Color(0xFFFFDAD2), Color(0xFFFFF1EA), Color(0xFFFF7F6A), Color(0xFFFFB86B), Color(0xFFFFC9BD), Color(0xFF8E3A2A)),
      HeroScene.contacts => const _HeroPalette(Color(0xFFFFE0D2), Color(0xFFFFF3EA), Color(0xFFE8714F), Color(0xFFFFB84D), Color(0xFFF7A58C), Color(0xFF8A3A22)),
      HeroScene.privacy => const _HeroPalette(Color(0xFFD8EEE6), Color(0xFFF3FAF6), Color(0xFF3F9A7C), Color(0xFFFFB84D), Color(0xFF9FD8C3), Color(0xFF1F5E48)),
      HeroScene.permissions => const _HeroPalette(Color(0xFFD9ECF5), Color(0xFFF4FAFB), Color(0xFF3F8FB5), Color(0xFFFFB84D), Color(0xFF9CCBE0), Color(0xFF1F5878)),
      HeroScene.memory => const _HeroPalette(Color(0xFFE6DDFA), Color(0xFFFAF4FF), Color(0xFF8A5FBF), Color(0xFFFFB84D), Color(0xFFC9B5EE), Color(0xFF4E2F82)),
      HeroScene.baseline => const _HeroPalette(Color(0xFFDDF0D8), Color(0xFFFFF7E4), Color(0xFF5FA463), Color(0xFFFFB84D), Color(0xFFA5D28C), Color(0xFF2F6B3A)),
      HeroScene.decisions => const _HeroPalette(Color(0xFFFFE9C4), Color(0xFFFFF8EA), Color(0xFFD99A2B), Color(0xFF6E73C8), Color(0xFFFFD27A), Color(0xFF7A4E10)),
      HeroScene.about => const _HeroPalette(Color(0xFFFFE2B8), Color(0xFFFFF4E0), Color(0xFFFFA23A), Color(0xFFFF7F50), Color(0xFFFFCF8A), Color(0xFF7A4318)),
      HeroScene.terms => const _HeroPalette(Color(0xFFE2E6F3), Color(0xFFF7F8FD), Color(0xFF5C6BB0), Color(0xFFFFB84D), Color(0xFFB7C0E6), Color(0xFF2E3870)),
      HeroScene.faq => const _HeroPalette(Color(0xFFFFE0CF), Color(0xFFFFF3EA), Color(0xFFFF8F5A), Color(0xFF6E73C8), Color(0xFFFFC7A5), Color(0xFF8A3E1A)),
      HeroScene.settings => const _HeroPalette(Color(0xFFE6E6EE), Color(0xFFF8F6F2), Color(0xFF7A74B8), Color(0xFFFFA23A), Color(0xFFC9C5E8), Color(0xFF3F3A70)),
    };

bool get _kitTesting {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// A painted header for a page: a gentle moving scene on the right, the title and a one-line subtitle on
/// the left, a back button on top. [progress] fixes the moment (previews and tests).
class PageHero extends StatefulWidget {
  const PageHero({
    required this.scene,
    required this.title,
    this.subtitle,
    this.height = 210,
    this.progress,
    this.showBack = true,
    this.trailing,
    this.onBack,
    this.backTooltip = 'Back',
    super.key,
  });

  final HeroScene scene;
  final String title;
  final String? subtitle;
  final double height;
  final double? progress;
  final bool showBack;
  final Widget? trailing;

  /// Replaces the default pop, e.g. to record that a page was seen before leaving.
  final VoidCallback? onBack;
  final String backTooltip;

  @override
  State<PageHero> createState() => _PageHeroState();
}

class _PageHeroState extends State<PageHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 10));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(PageHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) _syncMotion();
  }

  void _syncMotion() {
    final animate = widget.progress == null && !_kitTesting && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_c.isAnimating) _c.repeat();
    if (!animate) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _paletteOf(widget.scene);
    final top = MediaQuery.of(context).padding.top;
    final width = MediaQuery.of(context).size.width;
    // Bigger text widens the title column; the header then grows with its content instead of clipping it.
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final titleWidth = width * (scale > 1.25 ? 0.9 : 0.58);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: HeroPainter(widget.scene, widget.progress ?? _c.value)),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.height - 26),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.showBack) PageBackButton(onPressed: widget.onBack, tooltip: widget.backTooltip),
                      const Spacer(),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: titleWidth),
                        child: Text(
                          widget.title,
                          style: TextStyle(fontSize: 28, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: p.ink),
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: titleWidth),
                          child: Text(
                            widget.subtitle!,
                            style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: p.ink.withValues(alpha: 0.75)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the scene of a [PageHero]. Public so previews and tests can draw it at a fixed moment.
class HeroPainter extends CustomPainter {
  HeroPainter(this.scene, this.t);

  final HeroScene scene;
  final double t;

  double _s([double phase = 0, double speed = 1]) => math.sin((t * speed + phase) * 2 * math.pi);

  void _glow(Canvas c, Offset o, double r, Color color, [double a = 0.55]) =>
      c.drawCircle(o, r, Paint()..shader = ui.Gradient.radial(o, r, [color.withValues(alpha: a), color.withValues(alpha: 0)]));

  void _sparkle(Canvas c, Offset o, double r, Color color) {
    final p = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r);
    c.drawPath(p, Paint()..color = color);
  }

  Paint _stroke(Color color, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = w
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _paletteOf(scene);
    canvas.drawRect(Offset.zero & size, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [p.top, p.bottom]));
    final u = size.height * 0.62;
    final o = Offset(size.width * 0.74, size.height * 0.48);
    final compactWidth = math.min(u, size.width * 0.36);
    final compactCenter = Offset(size.width * 0.775, size.height * 0.45);
    _glow(canvas, o, u * 0.95, p.c, 0.6);
    switch (scene) {
      case HeroScene.rhythm:
        _rhythm(canvas, size, o, u, p);
      case HeroScene.noticed:
        _noticed(canvas, o, u, p);
      case HeroScene.support:
        _support(canvas, o, u, p);
      case HeroScene.contacts:
        _contacts(canvas, o, u, p);
      case HeroScene.privacy:
        _privacy(canvas, o, u, p);
      case HeroScene.permissions:
        _permissions(canvas, compactCenter, compactWidth, p);
      case HeroScene.memory:
        _memory(canvas, o, u, p);
      case HeroScene.baseline:
        _baseline(canvas, compactCenter, compactWidth, p);
      case HeroScene.decisions:
        _decisions(canvas, compactCenter, compactWidth, p);
      case HeroScene.about:
        _about(canvas, o, u, p);
      case HeroScene.terms:
        _terms(canvas, o, u, p);
      case HeroScene.faq:
        _faq(canvas, o, u, p);
      case HeroScene.settings:
        _settings(canvas, o, u, p);
    }
  }

  @override
  bool shouldRepaint(covariant HeroPainter old) => old.t != t || old.scene != scene;

  // A single highlight passes along seven beads. It enters and exits outside
  // the visible track so both ends of the animation loop have the same pose.

  void _rhythm(Canvas c, Size s, Offset o, double u, _HeroPalette p) {
    if (s.isEmpty) return;
    final start = Offset(s.width * .46, o.dy + u * .13);
    final end = Offset(s.width * .96, o.dy - u * .10);
    final span = end.dx - start.dx;
    final wave = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(start.dx + span * .14, o.dy - u * .34, start.dx + span * .29, o.dy - u * .24, start.dx + span * .49, o.dy)
      ..cubicTo(start.dx + span * .68, o.dy + u * .25, start.dx + span * .84, o.dy + u * .23, end.dx, end.dy);
    final track = _stroke(p.b, 1.65)
      ..shader = ui.Gradient.linear(start, end, [
        p.b.withValues(alpha: .08),
        p.b.withValues(alpha: .48),
        p.b.withValues(alpha: .31),
      ], [0, .31, 1]);
    c.drawPath(wave, track);

    final metric = wave.computeMetrics().first;
    final head = t * 1.32 - .09;
    final tail = head - .20;
    if (head > 0 && tail < 1) {
      final from = metric.length * tail.clamp(0.0, 1.0);
      final to = metric.length * head.clamp(0.0, 1.0);
      final a = metric.getTangentForOffset(from)!.position;
      final b = metric.getTangentForOffset(to)!.position;
      final fade = (math.min(head, 1 - tail) / .08).clamp(0.0, 1.0);
      final streak = _stroke(p.b, 2.55)
        ..shader = ui.Gradient.linear(a, b, [
          p.a.withValues(alpha: 0),
          p.a.withValues(alpha: .65 * fade),
          p.b.withValues(alpha: fade),
        ], [0, .58, 1]);
      c.drawPath(metric.extractPath(from, to), streak);
    }

    final ink = Paint();
    final bead = (u * .025).clamp(2.7, 4.2);
    for (var i = 0; i < 7; i++) {
      final f = .065 + i * .145;
      final center = metric.getTangentForOffset(metric.length * f)!.position;
      final proximity = (1 - (f - head).abs() / .115).clamp(0.0, 1.0);
      final lit = proximity * proximity;
      c.drawCircle(center, bead + lit * .8, ink..color = Color.lerp(p.bottom, p.a, lit)!);
      c.drawCircle(center, bead + lit * .8, _stroke(p.b.withValues(alpha: .58 + lit * .42), 1.05));
      if (lit > .12) {
        c.drawCircle(center + const Offset(-.7, -.9), 1.1, ink..color = Colors.white.withValues(alpha: .8 * lit));
      }
    }
    if (head > 0 && head < 1) {
      final center = metric.getTangentForOffset(metric.length * head)!.position;
      final fade = (math.min(head, 1 - head) / .065).clamp(0.0, 1.0);
      c.drawCircle(center, 2.15, ink..color = p.b.withValues(alpha: fade));
      c.drawCircle(center, 1.15, ink..color = const Color(0xFFFFF5D8).withValues(alpha: fade));
    }

    final sun = Offset(s.width * .87, s.height * .22);
    final radius = (u * .063).clamp(6.0, 11.0);
    c.drawCircle(sun, radius + 3, _stroke(p.a.withValues(alpha: .44), 1));
    c.drawCircle(sun, radius, ink..color = const Color(0xFFFFC85A));
  }

  // ---- noticed: a phone with a moon and orbiting readings ---------------------------------------

  void _noticed(Canvas c, Offset o, double u, _HeroPalette p) {
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: u * 0.52, height: u * 0.92), Radius.circular(u * 0.09));
    c.drawShadow(Path()..addRRect(body), p.ink, 10, false);
    c.drawRRect(body, Paint()..color = const Color(0xFF2E3170));
    final screen = RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: u * 0.44, height: u * 0.82), Radius.circular(u * 0.06));
    c.drawRRect(screen, Paint()..shader = ui.Gradient.linear(screen.outerRect.topCenter, screen.outerRect.bottomCenter, [const Color(0xFF4A4FA8), const Color(0xFF8E93E0)]));
    c.drawCircle(o + Offset(u * 0.07, -u * 0.22), u * 0.075, Paint()..color = const Color(0xFFFFE9A8));
    c.drawCircle(o + Offset(u * 0.1, -u * 0.24), u * 0.065, Paint()..color = const Color(0xFF4A4FA8));
    for (var i = 0; i < 4; i++) {
      final y = o.dy + u * (0.0 + i * 0.1);
      final w = u * (0.3 - (i % 2) * 0.1) * (0.6 + 0.4 * (0.5 + 0.5 * _s(i * 0.2)));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - u * 0.17, y, w, u * 0.045), Radius.circular(u * 0.02)), Paint()..color = Colors.white.withValues(alpha: 0.7 - i * 0.12));
    }
    for (var i = 0; i < 5; i++) {
      final a = (t + i / 5) * 2 * math.pi;
      final pos = o + Offset(math.cos(a) * u * 0.62, math.sin(a) * u * 0.34);
      _sparkle(c, pos, u * 0.05, i.isEven ? p.b : p.c);
    }
  }

  // ---- support: a heart with ripples of care -----------------------------------------------------

  void _support(Canvas c, Offset o, double u, _HeroPalette p) {
    for (var i = 0; i < 3; i++) {
      final f = (t * 1.2 + i / 3) % 1.0;
      c.drawCircle(o, u * (0.3 + 0.5 * f), _stroke(p.a.withValues(alpha: 0.45 * (1 - f)), 2.4));
    }
    final beat = 1 + 0.06 * math.pow(math.sin(t * 2 * math.pi * 2).abs(), 3);
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(beat.toDouble());
    final r = u * 0.3;
    final heart = Path()
      ..moveTo(0, r * 0.9)
      ..cubicTo(-r * 1.7, -r * 0.1, -r * 0.8, -r * 1.3, 0, -r * 0.4)
      ..cubicTo(r * 0.8, -r * 1.3, r * 1.7, -r * 0.1, 0, r * 0.9);
    c.drawPath(heart, Paint()..shader = ui.Gradient.linear(Offset(0, -r), Offset(0, r), [p.b, p.a]));
    c.drawPath(
      Path()
        ..moveTo(-r * 0.55, -r * 0.35)
        ..quadraticBezierTo(-r * 0.7, -r * 0.7, -r * 0.2, -r * 0.62),
      _stroke(Colors.white.withValues(alpha: 0.7), 3),
    );
    c.restore();
    for (var i = 0; i < 5; i++) {
      final f = (t * 0.8 + i / 5) % 1.0;
      _sparkle(c, o + Offset(math.sin((f * 2 + i) * math.pi) * u * 0.5, u * 0.45 - f * u * 0.95), u * 0.04 * math.sin(f * math.pi), Colors.white);
    }
  }

  // ---- contacts: people connected to one another --------------------------------------------------

  void _contacts(Canvas c, Offset o, double u, _HeroPalette p) {
    final nodes = [o + Offset(-u * 0.42, u * 0.22), o + Offset(u * 0.0, -u * 0.3), o + Offset(u * 0.44, u * 0.2), o + Offset(u * 0.02, u * 0.38)];
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        c.drawLine(nodes[i], nodes[j], _stroke(p.a.withValues(alpha: 0.28), 2));
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      final pulse = 1 + 0.06 * _s(i * 0.25);
      final col = [p.a, p.b, p.c, p.a][i];
      _glow(c, nodes[i], u * 0.22, col, 0.5);
      c.drawCircle(nodes[i], u * 0.13 * pulse, Paint()..color = col);
      c.drawCircle(nodes[i] + Offset(0, -u * 0.035), u * 0.04, Paint()..color = Colors.white);
      c.drawArc(Rect.fromCenter(center: nodes[i] + Offset(0, u * 0.075), width: u * 0.13, height: u * 0.09), math.pi, math.pi, true, Paint()..color = Colors.white);
    }
    final travel = (t * 2) % 1.0;
    final pos = Offset.lerp(nodes[0], nodes[1], travel)!;
    _glow(c, pos, u * 0.1, Colors.white, 0.9);
    c.drawCircle(pos, u * 0.025, Paint()..color = Colors.white);
  }

  // ---- privacy: a shield with a keyhole ---------------------------------------------------------------

  void _privacy(Canvas c, Offset o, double u, _HeroPalette p) {
    final shield = Path()
      ..moveTo(o.dx, o.dy - u * 0.46)
      ..cubicTo(o.dx + u * 0.2, o.dy - u * 0.36, o.dx + u * 0.36, o.dy - u * 0.34, o.dx + u * 0.4, o.dy - u * 0.32)
      ..cubicTo(o.dx + u * 0.42, o.dy + u * 0.2, o.dx + u * 0.2, o.dy + u * 0.4, o.dx, o.dy + u * 0.5)
      ..cubicTo(o.dx - u * 0.2, o.dy + u * 0.4, o.dx - u * 0.42, o.dy + u * 0.2, o.dx - u * 0.4, o.dy - u * 0.32)
      ..cubicTo(o.dx - u * 0.36, o.dy - u * 0.34, o.dx - u * 0.2, o.dy - u * 0.36, o.dx, o.dy - u * 0.46);
    c.drawShadow(shield, p.ink, 8, false);
    c.drawPath(shield, Paint()..shader = ui.Gradient.linear(o - Offset(0, u * 0.46), o + Offset(0, u * 0.5), [p.a, p.ink]));
    c.drawPath(shield, _stroke(Colors.white.withValues(alpha: 0.5), 3));
    c.drawCircle(o + Offset(0, -u * 0.06), u * 0.1, Paint()..color = Colors.white);
    c.drawPath(
      Path()
        ..moveTo(o.dx - u * 0.035, o.dy)
        ..lineTo(o.dx + u * 0.035, o.dy)
        ..lineTo(o.dx + u * 0.06, o.dy + u * 0.2)
        ..lineTo(o.dx - u * 0.06, o.dy + u * 0.2)
        ..close(),
      Paint()..color = Colors.white,
    );
    for (var i = 0; i < 6; i++) {
      final a = (t + i / 6) * 2 * math.pi;
      final pos = o + Offset(math.cos(a) * u * 0.68, math.sin(a) * u * 0.5);
      c.drawCircle(pos, u * 0.025, Paint()..color = p.b.withValues(alpha: 0.9));
    }
  }

  // A lock anchors the camera and microphone tiles in one compact panel.
  void _permissions(Canvas c, Offset o, double u, _HeroPalette p) {
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(u / 100);
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-46, -31, 46, 38),
      const Radius.circular(17),
    );
    final tile = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-33, 7, -3, 27),
      const Radius.circular(7),
    );
    final shadow = frame.shift(const Offset(0, 4));
    c.drawRRect(shadow, Paint()..color = p.ink.withValues(alpha: 0.10));
    c.drawRRect(frame, Paint()..color = Colors.white.withValues(alpha: 0.85));
    c.drawRRect(frame, _stroke(p.a.withValues(alpha: 0.18), 1.1));

    final lock = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-12, -17, 12, -2),
      const Radius.circular(5),
    );
    c.drawArc(
      const Rect.fromLTWH(-6, -25, 12, 14),
      math.pi,
      math.pi,
      false,
      _stroke(p.ink, 2.6),
    );
    c.drawRRect(lock, Paint()..color = p.ink);
    c.drawCircle(const Offset(0, -10), 1.9, Paint()..color = Colors.white);

    final focus = (1 + _s(-0.25)) / 2;
    final cameraColor = Color.lerp(p.a, p.ink, focus)!;
    final micColor = Color.lerp(p.a, p.ink, 1 - focus)!;
    c.drawRRect(tile, Paint()..color = p.c.withValues(alpha: 0.30 + focus * 0.35));
    c.drawRRect(
      tile.shift(const Offset(36, 0)),
      Paint()..color = p.c.withValues(alpha: 0.30 + (1 - focus) * 0.35),
    );

    final cameraInk = _stroke(cameraColor, 1.5);
    c.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(-25, 13, -11, 22), const Radius.circular(2.4)),
      cameraInk,
    );
    c.drawLine(const Offset(-21, 12), const Offset(-15, 12), cameraInk);
    c.drawCircle(const Offset(-18, 17.5), 2.6, cameraInk);

    final micInk = _stroke(micColor, 1.5);
    c.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(15.5, 11, 20.5, 19), const Radius.circular(2.5)),
      micInk,
    );
    c.drawArc(const Rect.fromLTRB(13, 12, 23, 22), 0, math.pi, false, micInk);
    c.drawLine(const Offset(18, 22), const Offset(18, 24), micInk);
    c.restore();
  }

  // ---- memory: a constellation of kept moments ----------------------------------------------------------------

  void _memory(Canvas c, Offset o, double u, _HeroPalette p) {
    final pts = [o + Offset(-u * 0.45, u * 0.1), o + Offset(-u * 0.2, -u * 0.3), o + Offset(u * 0.1, -u * 0.05), o + Offset(u * 0.32, -u * 0.34), o + Offset(u * 0.46, u * 0.18), o + Offset(u * 0.02, u * 0.36)];
    final line = _stroke(p.a.withValues(alpha: 0.32), 1.8);
    for (var i = 0; i < pts.length - 1; i++) {
      c.drawLine(pts[i], pts[i + 1], line);
    }
    c.drawLine(pts[2], pts[5], line);
    for (var i = 0; i < pts.length; i++) {
      final tw = 0.6 + 0.4 * _s(i * 0.17, 2);
      _glow(c, pts[i], u * 0.16, p.b, 0.7 * tw);
      c.drawCircle(pts[i], u * (0.045 + 0.015 * (i % 3)), Paint()..color = i.isEven ? p.a : Colors.white);
      _sparkle(c, pts[i] + Offset(u * 0.05, -u * 0.05), u * 0.03 * tw, Colors.white);
    }
  }

  // The seedling bends as one piece from its roots.
  void _baseline(Canvas c, Offset o, double u, _HeroPalette p) {
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(u / 100);
    const sun = Offset(25, -18);
    _glow(c, sun, 28, p.b, 0.45);
    c.drawCircle(sun, 12, Paint()..color = const Color(0xFFFFD47F));

    final meadow = Path()
      ..moveTo(-44, 39)
      ..cubicTo(-27, 25, -16, 27, -5, 33)
      ..cubicTo(7, 27, 23, 24, 44, 39)
      ..quadraticBezierTo(1, 53, -44, 39)
      ..close();
    c.drawPath(
      meadow,
      Paint()..shader = ui.Gradient.linear(
        const Offset(0, 25),
        const Offset(0, 47),
        [p.c.withValues(alpha: 0.9), p.c.withValues(alpha: 0.34)],
      ),
    );

    const root = Offset(-4, 37);
    c.drawOval(
      Rect.fromCenter(center: root, width: 37, height: 8),
      Paint()..color = p.ink.withValues(alpha: 0.12),
    );
    c.translate(root.dx, root.dy);
    c.rotate(0.085 * _s());
    final stem = Path()
      ..moveTo(0, 0)
      ..cubicTo(-3, -13, -2, -29, 3, -45);
    c.drawPath(stem, _stroke(p.ink, 2.7));

    final left = Path()
      ..moveTo(0, -22)
      ..cubicTo(-10, -21, -21, -26, -27, -41)
      ..cubicTo(-12, -41, -3, -36, 0, -22)
      ..close();
    final right = Path()
      ..moveTo(1, -34)
      ..cubicTo(4, -46, 14, -56, 28, -56)
      ..cubicTo(26, -42, 16, -32, 1, -34)
      ..close();
    c.drawPath(left, Paint()..color = p.a);
    c.drawPath(
      right,
      Paint()..shader = ui.Gradient.linear(
        const Offset(2, -34),
        const Offset(26, -56),
        [p.a, p.c],
      ),
    );
    final vein = _stroke(Colors.white.withValues(alpha: 0.43), 1);
    c.drawPath(Path()..moveTo(-3, -25)..quadraticBezierTo(-12, -32, -21, -36), vein);
    c.drawPath(Path()..moveTo(5, -36)..quadraticBezierTo(13, -44, 22, -50), vein);
    c.restore();
  }

  // Three signals converge. A single highlight follows the resulting choice.
  void _decisions(Canvas c, Offset o, double u, _HeroPalette p) {
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(u / 100);
    const inputs = [Offset(-39, -26), Offset(-43, 0), Offset(-39, 26)];
    const hub = Offset(4, 0);
    const result = Offset(40, 0);
    final guide = _stroke(p.ink.withValues(alpha: 0.18), 1.6);
    final active = _stroke(p.a, 2.2);

    for (var i = 0; i < inputs.length; i++) {
      final start = inputs[i];
      final connector = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(-17, start.dy, -16, 0, hub.dx, hub.dy);
      c.drawPath(connector, guide);
      c.drawCircle(start, 5, Paint()..color = p.b.withValues(alpha: 0.20));
      c.drawCircle(start, 2.5, Paint()..color = p.b);

      final fraction = ((t - i * 0.055) / 0.43).clamp(0.0, 1.0);
      final opacity = math.sin(math.pi * fraction);
      final metric = connector.computeMetrics().first;
      final point = metric.getTangentForOffset(metric.length * fraction)!.position;
      c.drawCircle(point, 3.2, Paint()..color = p.b.withValues(alpha: opacity));
    }

    c.drawLine(hub, result, guide);
    final send = ((t - 0.47) / 0.28).clamp(0.0, 1.0);
    final settle = ((t - 0.73) / 0.27).clamp(0.0, 1.0);
    active.color = p.a.withValues(alpha: 1 - Curves.easeInOut.transform(settle));
    c.drawLine(hub, Offset.lerp(hub, result, Curves.easeInOut.transform(send))!, active);

    c.drawCircle(hub, 12, Paint()..color = p.c.withValues(alpha: 0.55));
    c.drawCircle(hub, 9, Paint()..color = Colors.white);
    c.drawCircle(hub, 9, _stroke(p.a.withValues(alpha: 0.45), 1.3));
    _sparkle(c, hub, 4.8 + 1.5 * math.sin(math.pi * send), p.a);
    c.drawCircle(result, 8, Paint()..color = Color.lerp(p.c, p.a, send * (1 - settle))!);
    c.drawPath(
      Path()
        ..moveTo(36.5, 0)
        ..lineTo(39, 2.5)
        ..lineTo(43.5, -2.5),
      _stroke(p.ink, 1.45),
    );
    c.restore();
  }

  // ---- about: the sun with petals --------------------------------------------------------------------------------------------

  void _about(Canvas c, Offset o, double u, _HeroPalette p) {
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * 2 * math.pi + t * 2 * math.pi * 0.1;
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(a);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(u * 0.3, -u * 0.03, u * (0.16 + 0.04 * _s(i * 0.1)), u * 0.06), Radius.circular(u * 0.03)), Paint()..color = (i.isEven ? p.a : p.b).withValues(alpha: 0.85));
      c.restore();
    }
    c.drawCircle(o, u * 0.27, Paint()..shader = ui.Gradient.radial(o, u * 0.27, [const Color(0xFFFFE08A), p.a]));
    c.drawArc(Rect.fromCenter(center: o + Offset(0, u * 0.03), width: u * 0.24, height: u * 0.16), 0.25, math.pi - 0.5, false, _stroke(Colors.white, 4));
    c.drawCircle(o + Offset(-u * 0.08, -u * 0.05), u * 0.02, Paint()..color = Colors.white);
    c.drawCircle(o + Offset(u * 0.08, -u * 0.05), u * 0.02, Paint()..color = Colors.white);
    for (var i = 0; i < 4; i++) {
      _sparkle(c, o + Offset(math.cos(i * 1.7 + 1) * u * 0.7, math.sin(i * 1.7 + 1) * u * 0.45), u * 0.04 * (0.6 + 0.4 * _s(i * 0.2, 2)), Colors.white);
    }
  }

  // ---- terms: sheets with a seal ----------------------------------------------------------------------------------------------------

  void _terms(Canvas c, Offset o, double u, _HeroPalette p) {
    for (var i = 2; i >= 0; i--) {
      c.save();
      c.translate(o.dx + i * u * 0.05, o.dy + i * u * 0.04);
      c.rotate((i - 1) * 0.07);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * 0.55, height: u * 0.72), Radius.circular(u * 0.05));
      if (i == 0) c.drawShadow(Path()..addRRect(r), p.ink, 6, false);
      c.drawRRect(r, Paint()..color = i == 0 ? Colors.white : p.c.withValues(alpha: 0.7));
      if (i == 0) {
        for (var k = 0; k < 5; k++) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-u * 0.2, -u * 0.26 + k * u * 0.08, u * (0.4 - (k % 2) * 0.12), u * 0.03), Radius.circular(u * 0.015)), Paint()..color = p.c);
        }
      }
      c.restore();
    }
    final seal = o + Offset(u * 0.2, u * 0.26);
    final pulse = 1 + 0.05 * _s();
    c.drawCircle(seal, u * 0.13 * pulse, Paint()..color = p.b);
    c.drawPath(
      Path()
        ..moveTo(seal.dx - u * 0.05, seal.dy)
        ..lineTo(seal.dx - u * 0.01, seal.dy + u * 0.04)
        ..lineTo(seal.dx + u * 0.06, seal.dy - u * 0.05),
      _stroke(Colors.white, 4),
    );
  }

  // ---- faq: speech bubbles, one with a question mark -----------------------------------------------------------------------------------

  void _faq(Canvas c, Offset o, double u, _HeroPalette p) {
    void bubble(Offset at, double w, double h, Color col, {bool left = true}) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: at, width: w, height: h), Radius.circular(h * 0.45));
      c.drawShadow(Path()..addRRect(r), p.ink, 4, false);
      c.drawRRect(r, Paint()..color = col);
      final dir = left ? -1 : 1;
      c.drawPath(
        Path()
          ..moveTo(at.dx + dir * w * 0.3, at.dy + h * 0.4)
          ..lineTo(at.dx + dir * w * 0.45, at.dy + h * 0.8)
          ..lineTo(at.dx + dir * w * 0.12, at.dy + h * 0.42)
          ..close(),
        Paint()..color = col,
      );
    }

    final bob = _s() * u * 0.02;
    bubble(o + Offset(-u * 0.2, -u * 0.2 + bob), u * 0.62, u * 0.34, Colors.white);
    final tp = TextPainter(text: TextSpan(text: '?', style: TextStyle(fontSize: u * 0.3, fontWeight: FontWeight.w800, color: p.a)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o + Offset(-u * 0.2 - tp.width / 2, -u * 0.2 + bob - tp.height / 2));
    bubble(o + Offset(u * 0.2, u * 0.22 - bob), u * 0.6, u * 0.3, p.a, left: false);
    for (var i = 0; i < 3; i++) {
      c.drawCircle(o + Offset(u * 0.1 + i * u * 0.1, u * 0.22 - bob), u * 0.03, Paint()..color = Colors.white.withValues(alpha: 0.5 + 0.5 * (0.5 + 0.5 * _s(i * 0.15, 2))));
    }
  }

  // ---- settings: sliders with knobs that glide ----------------------------------------------------------------------------------------------------

  void _settings(Canvas c, Offset o, double u, _HeroPalette p) {
    for (var i = 0; i < 3; i++) {
      final y = o.dy + (i - 1) * u * 0.3;
      final x0 = o.dx - u * 0.5, x1 = o.dx + u * 0.5;
      c.drawLine(Offset(x0, y), Offset(x1, y), _stroke(Colors.white.withValues(alpha: 0.9), u * 0.07));
      final f = 0.5 + 0.4 * _s(i * 0.33);
      final x = x0 + (x1 - x0) * f;
      c.drawLine(Offset(x0, y), Offset(x, y), _stroke([p.a, p.b, p.c][i], u * 0.07));
      c.drawCircle(Offset(x, y), u * 0.075, Paint()..color = Colors.white);
      c.drawCircle(Offset(x, y), u * 0.045, Paint()..color = [p.a, p.b, p.c][i]);
    }
  }
}

/// A white rounded card, the surface of the visual pages.
class KitCard extends StatelessWidget {
  const KitCard({required this.child, this.padding = const EdgeInsets.all(16), this.color, this.gradient, this.onTap, super.key});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    final decoration = BoxDecoration(
      color: color ?? SolaceColors.from(context).surface,
      gradient: gradient,
      borderRadius: radius,
      border: Border.all(color: kitLine),
      boxShadow: const [BoxShadow(color: Color(0x14B0782A), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 8))],
    );
    if (onTap == null) return Container(decoration: decoration, padding: padding, child: child);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(borderRadius: radius, onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class KitLabel extends StatelessWidget {
  const KitLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: kitMuted)),
      );
}

/// An icon in a soft coloured tile.
class IconTile extends StatelessWidget {
  const IconTile({required this.icon, required this.color, this.size = 42, super.key});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.34)),
        child: Icon(icon, size: size * 0.5, color: color),
      );
}

/// A big number with a small label under it, optionally with an icon. Sits in a Row.
class StatTile extends StatelessWidget {
  const StatTile({required this.value, required this.label, required this.color, this.icon, super.key});

  final String value;
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) Icon(icon, size: 18, color: color),
            if (icon != null) const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 24, height: 1.0, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w700, color: kitSoft)),
          ],
        ),
      ),
    );
  }
}

/// A circular gauge: [value] of [max] around a ring, with a big centre label.
class RingGauge extends StatelessWidget {
  const RingGauge({required this.value, required this.max, required this.centre, this.caption, this.color = kitAmber, this.size = 120, this.track, super.key});

  final double value;
  final double max;
  final String centre;
  final String? caption;
  final Color color;
  final double size;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: max <= 0 ? 0 : (value / max).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, f, _) => CustomPaint(
          painter: _RingPainter(f, color, track ?? color.withValues(alpha: 0.16)),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(size * 0.17),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(centre, style: TextStyle(fontSize: size * 0.24, height: 1.0, fontWeight: FontWeight.w800, color: kitInk)),
                    if (caption != null) Text(caption!, style: TextStyle(fontSize: size * 0.1, fontWeight: FontWeight.w700, color: kitSoft)),
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

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.color, this.track);

  final double f;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.11;
    final rect = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * f, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w
      ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.f != f || old.color != color;
}

/// Vertical bars with a label under each. Missing values draw as a faint stub.
class MiniBars extends StatelessWidget {
  const MiniBars({required this.values, required this.labels, this.height = 110, this.color = kitAmber, this.highlight, this.valueLabel, super.key});

  final List<double?> values;
  final List<String> labels;
  final double height;
  final Color color;
  final int? highlight;
  final String Function(double v)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final maxV = values.whereType<double>().fold<double>(0, math.max);
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return SizedBox(
      height: height + 52 + (scale > 1 ? (scale - 1) * 50 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (values[i] != null && valueLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(valueLabel!(values[i]!), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kitSoft)),
                    ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: values[i] == null || maxV == 0 ? 0 : values[i]! / maxV),
                    duration: Duration(milliseconds: 500 + i * 70),
                    curve: Curves.easeOutCubic,
                    builder: (context, f, _) => Container(
                      width: 18,
                      height: math.max(4, f * height),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        color: values[i] == null ? const Color(0xFFEDE4CF) : (highlight == null || highlight == i ? color : color.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(labels[i], style: TextStyle(fontSize: 10.5, fontWeight: highlight == i ? FontWeight.w800 : FontWeight.w600, color: highlight == i ? kitInk : kitMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A row for a setting: icon tile, title, a short line, and a trailing control.
class SettingRow extends StatelessWidget {
  const SettingRow({required this.icon, required this.color, required this.title, this.subtitle, this.trailing, this.onTap, this.padding = const EdgeInsets.symmetric(vertical: 9), super.key});

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = SolaceColors.from(context);
    final row = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            IconTile(icon: icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: palette.mutedInk)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && onTap != null) const Icon(Icons.chevron_right_rounded, color: Color(0xFFD8C9B2)),
          ],
        ),
      ),
    );
    return trailing is Switch ? MergeSemantics(child: row) : row;
  }
}

/// A small pill label ("On", "Needs your OK") in a colour.
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {required this.color, super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
      );
}
