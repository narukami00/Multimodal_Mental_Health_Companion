import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/forest/tree_geometry.dart';
import 'tree_painter.dart';

/// How the check-in card looks at each time of day: the orange stays warm and keeps the dark text readable, and melts into
/// the sky of the hour on the right, where the growing tree stands.
class ForestPalette {
  const ForestPalette({
    required this.name,
    required this.left,
    required this.text,
    required this.skyA,
    required this.skyB,
    required this.ground,
    required this.sun,
    required this.sunFromRight,
    required this.sunY,
    required this.glow,
    required this.treeTint,
    required this.shadowAlpha,
    required this.shadowLength,
    required this.stars,
    required this.tint,
    required this.shadow,
  });

  final String name;

  /// The three stops of the card's own gradient.
  final List<Color> left;
  final Color text;
  final Color skyA, skyB;
  final List<Color> ground;
  final Color sun, glow;
  final double sunFromRight, sunY;

  /// The light of the hour laid over the tree and its ground (null in full daylight).
  final Color? treeTint;
  final double shadowAlpha, shadowLength, stars;

  /// A faint tint over the whole card.
  final Color? tint;
  final Color shadow;

  static const day = ForestPalette(
    name: 'day', left: [Color(0xFFFFD07A), Color(0xFFFFB534), Color(0xFFFFA446)], text: Color(0xFF55350F),
    skyA: Color(0xFFE9F3F0), skyB: Color(0xFFBFE3F4), ground: [Color(0xFFB4DC84), Color(0xFF8FC468)],
    sun: Color(0xFFFFD36B), sunFromRight: 56, sunY: 44, glow: Color(0xBFFFF0BE), treeTint: null,
    shadowAlpha: .16, shadowLength: 34, stars: 0, tint: null, shadow: Color(0xFFE28C1E),
  );
  static const golden = ForestPalette(
    name: 'golden', left: [Color(0xFFFFC46A), Color(0xFFFFA23E), Color(0xFFFF8E3A)], text: Color(0xFF4A2708),
    skyA: Color(0xFFFDE3BD), skyB: Color(0xFFF8B98A), ground: [Color(0xFFC2CF7C), Color(0xFF9BB45E)],
    sun: Color(0xFFFF9D4D), sunFromRight: 34, sunY: 112, glow: Color(0xCCFFBE78), treeTint: Color(0x33FF8030),
    shadowAlpha: .22, shadowLength: 74, stars: 0, tint: Color(0x12FF8C3C), shadow: Color(0xFFD9731A),
  );
  static const dusk = ForestPalette(
    name: 'dusk', left: [Color(0xFFFFB873), Color(0xFFF29158), Color(0xFFDE7A55)], text: Color(0xFF3A1C0C),
    skyA: Color(0xFFD8A8B0), skyB: Color(0xFF8C78AD), ground: [Color(0xFF80A273), Color(0xFF5F8760)],
    sun: Color(0xFFFF8A4C), sunFromRight: 26, sunY: 176, glow: Color(0xBFFF966E), treeTint: Color(0x575C348C),
    shadowAlpha: .18, shadowLength: 96, stars: .25, tint: Color(0x1A462882), shadow: Color(0xFFA24D2A),
  );
  static const night = ForestPalette(
    name: 'night', left: [Color(0xFFF1B070), Color(0xFFD9885A), Color(0xFFB96A50)], text: Color(0xFF2B1407),
    skyA: Color(0xFF6C6AA0), skyB: Color(0xFF1D2655), ground: [Color(0xFF456F5D), Color(0xFF33594A)],
    sun: Color(0xFFF3EFD8), sunFromRight: 58, sunY: 46, glow: Color(0x73C8D7FF), treeTint: Color(0x800A1246),
    shadowAlpha: .10, shadowLength: 20, stars: 1, tint: Color(0x330A1040), shadow: Color(0xFF3A2760),
  );

  /// The palette for a local [hour] (0..23): night, early golden light, day, evening golden light, dusk.
  static ForestPalette forHour(int hour) {
    if (hour >= 21 || hour < 5) return night;
    if (hour < 8) return golden;
    if (hour < 17) return day;
    if (hour < 19) return golden;
    return dusk;
  }
}

/// Everything the check-in card needs to show the growing tree, and what tapping the tree does.
class ForestCardData {
  const ForestCardData({required this.palette, required this.species, required this.stage, required this.waterWaiting, required this.onOpen});
  final ForestPalette palette;
  final int species;
  final double stage;
  final bool waterWaiting;
  final VoidCallback onOpen;
}

final _geometryCache = <int, TreeGeometry>{};
TreeGeometry geometryFor(int species) =>
    _geometryCache.putIfAbsent(species, () => generateTree(4242 + species * 7919 + 13, treeSpecies[species]));

/// The sky, sun or moon, ground, shadow, growing tree and (when a water is waiting) the watering can, drawn behind the
/// text of the check-in card.
class ForestCardPainter extends CustomPainter {
  ForestCardPainter({required this.palette, required this.species, required this.stage, required this.waterWaiting});

  final ForestPalette palette;
  final int species;
  final double stage;
  final bool waterWaiting;

  static final _cloudShape = Path()
    ..moveTo(0, 13)
    ..cubicTo(5, 9, 12, 9, 18, 8)
    ..cubicTo(21, 3, 30, 2, 35, 5)
    ..cubicTo(40, -1, 50, -2, 57, 5)
    ..cubicTo(65, 3, 73, 8, 74, 11)
    ..cubicTo(82, 11, 89, 13, 92, 15)
    ..cubicTo(76, 18, 20, 19, 0, 13)
    ..close();

  void _paintSkyDetails(Canvas canvas, Size size, bool night) {
    final p = palette, width = size.width, height = size.height;
    final pale = night ? const Color(0xFF9A9DCD) : Color.lerp(Colors.white, p.sun, .12)!;
    final cloud = Paint()..shader = ui.Gradient.linear(
      Offset.zero,
      const Offset(0, 18),
      [pale.withValues(alpha: night ? .20 : .74), p.skyA.withValues(alpha: night ? .08 : .38)],
    );
    for (final (x, y, scale) in const [(.68, .31, .92), (.80, .12, .52), (.64, .50, .56)]) {
      final k = math.min(1.0, width / 365) * scale;
      canvas.save();
      canvas.translate(width * x, height * y);
      canvas.scale(k, k);
      canvas.drawPath(_cloudShape, cloud);
      canvas.restore();
    }
    if (night) return;

    final birds = Path();
    for (final (x, y, wing) in const [(.83, .42, 4.2), (.88, .40, 3.2), (.91, .46, 2.6)]) {
      final bx = width * x, by = height * y;
      birds
        ..moveTo(bx - wing, by - wing * .35)
        ..quadraticBezierTo(bx - wing * .48, by - wing * .45, bx, by)
        ..quadraticBezierTo(bx + wing * .47, by - wing * .61, bx + wing, by - wing * .48);
    }
    canvas.drawPath(birds, Paint()
      ..color = const Color(0xFF414C62).withValues(alpha: .64)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);
  }

  void _paintGrass(Canvas canvas, double width, double baseY) {
    final far = Path(), near = Path();
    for (var row = 0; row < 3; row++) {
      final count = 6 + row * 2;
      for (var i = 0; i < count; i++) {
        final r = mulberry32(432 + row * 367 + i * 619);
        final x = width * (.31 + .70 * (i + r() * .85) / count);
        final y = baseY + 3 + row * 13 + r() * 8;
        final size = (.54 + row * .18) * (.75 + r() * .5);
        final path = row == 0 ? far : near;
        for (final (spread, length) in const [(-3.8, 5.5), (-1.4, 8.2), (1.8, 6.9), (4.2, 4.7)]) {
          final root = x + spread * size * .21;
          path
            ..moveTo(root, y)
            ..quadraticBezierTo(x + spread * size * .45, y - 3 * size, x + spread * size, y - length * size)
            ..quadraticBezierTo(x + spread * size * .70, y - 2 * size, root + .9 * size, y)
            ..close();
        }
      }
    }
    canvas.drawPath(far, Paint()..color = Color.lerp(palette.ground.last, const Color(0xFF346342), .38)!.withValues(alpha: .49));
    canvas.drawPath(near, Paint()..color = Color.lerp(palette.ground.last, const Color(0xFF31563B), .46)!.withValues(alpha: .62));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = palette;
    final full = Offset.zero & size;

    // the melt from orange into the sky of the hour
    canvas.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          [const Color(0x00FFFFFF), p.skyA.withValues(alpha: .70), p.skyB],
          [.40, .62, 1.0],
        ),
    );
    if (p.tint != null) canvas.drawRect(full, Paint()..color = p.tint!);

    // stars over the sky side
    if (p.stars > 0) {
      final star = Paint()..color = Colors.white.withValues(alpha: p.stars * .9);
      for (var i = 0; i < 22; i++) {
        final r = mulberry32(i * 17 + 3);
        canvas.drawCircle(Offset(w * .55 + r() * w * .43, r() * h * .55), .6 + r() * .9, star);
      }
    }

    // the sun (or moon) and its glow
    final sx = w - p.sunFromRight, sy = p.sunY;
    canvas.drawCircle(Offset(sx, sy), 46, Paint()..shader = ui.Gradient.radial(Offset(sx, sy), 46, [p.glow, const Color(0x00FFFFFF)]));
    final night = p.name == 'night';
    canvas.drawCircle(Offset(sx, sy), night ? 9 : 11, Paint()..color = p.sun);
    if (night) canvas.drawCircle(Offset(sx + 4, sy - 2), 8, Paint()..color = const Color(0xE61D2655));
    _paintSkyDetails(canvas, size, night);

    // the tree layer on the right, sized by the card
    final tw = math.min(210.0, w * .62);
    canvas.save();
    canvas.translate(w - tw, 0);
    canvas.clipRect(Rect.fromLTWH(0, 0, tw, h));
    canvas.saveLayer(Rect.fromLTWH(0, 0, tw, h), Paint());
    final baseY = h - 46, gx = tw * .59;

    final ground = Path()
      ..moveTo(0, h)
      ..lineTo(0, baseY + 6)
      ..quadraticBezierTo(70, baseY - 8, 125, baseY - 2)
      ..quadraticBezierTo(175, baseY - 10, tw, baseY - 4)
      ..lineTo(tw, h)
      ..close();
    canvas.drawPath(
      ground,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(tw, 0),
          [p.ground[0].withValues(alpha: 0), p.ground[0].withValues(alpha: .88), p.ground[1]],
          [0, .32, 1],
        ),
    );

    final grow = clamp01((stage - 2) / 4.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(gx - p.shadowLength * .42 * grow, baseY + 3),
        width: 2 * (22 + 20 * grow + p.shadowLength * .5 * grow),
        height: 2 * (5 + 3 * grow),
      ),
      Paint()..color = const Color(0xFF162018).withValues(alpha: p.shadowAlpha * (.35 + .65 * grow)),
    );
    _paintGrass(canvas, tw, baseY);

    final sp = treeSpecies[species];
    var sc = (h - 62) / (sp.height + 30);
    sc = math.min(sc, 176 / (sp.width + 30));
    if (stage < 4.2) sc *= lerp(1.5, 1, stage / 4.2);
    canvas.save();
    canvas.translate(gx, baseY);
    canvas.scale(sc, sc);
    paintTree(canvas, geometryFor(species), sp, stage, soil: true);
    canvas.restore();

    if (waterWaiting) {
      canvas.save();
      canvas.translate(gx + 62, baseY + 8);
      canvas.scale(.9, .9);
      paintWateringCan(canvas);
      canvas.restore();
    }

    // the light of the hour, only over what was drawn here, so there is no edge
    if (p.treeTint != null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, tw, h), Paint()
        ..color = p.treeTint!
        ..blendMode = BlendMode.srcATop);
    }
    canvas.restore(); // layer
    canvas.restore();
  }

  @override
  bool shouldRepaint(ForestCardPainter old) =>
      old.palette != palette || old.species != species || old.stage != stage || old.waterWaiting != waterWaiting;
}
