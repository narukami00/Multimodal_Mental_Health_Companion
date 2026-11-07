import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../domain/forest/tree_geometry.dart';

/// Draws trees with the trunk's base at the canvas origin, up as negative y: a straight translation of the approved forest
/// prototype's canvas code. Only paths, ovals, circles, gradients and transforms are used.

typedef Rgb = List<double>;

final _hexCache = <String, Rgb>{};

Rgb hexRgb(String h) => _hexCache.putIfAbsent(h, () {
  final n = int.parse(h.substring(1), radix: 16);
  return [((n >> 16) & 255).toDouble(), ((n >> 8) & 255).toDouble(), ((n >> 0) & 255).toDouble()];
});

Rgb _mix(Rgb a, Rgb b, double t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
Rgb _shade(Rgb c, double k) => k >= 0 ? _mix(c, [255, 255, 255], k) : _mix(c, [0, 0, 0], -k);
double _easeOut(double t) => 1 - math.pow(1 - clamp01(t), 3).toDouble();
const _youngScale = 1.6;

class _Brush {
  _Brush(this.canvas);
  final Canvas canvas;

  /// Like the canvas' globalAlpha: multiplies every colour drawn while it is set.
  double ga = 1;

  /// The light of the hour: every colour is multiplied by it, so trees darken and warm with the sky.
  Rgb light = const [255, 255, 255];

  Color col(Rgb c, [double a = 1]) => Color.fromRGBO(
        (c[0] * light[0] / 255).round().clamp(0, 255),
        (c[1] * light[1] / 255).round().clamp(0, 255),
        (c[2] * light[2] / 255).round().clamp(0, 255),
        clamp01(a * ga),
      );
  Paint fill(Rgb c, [double a = 1]) => Paint()..color = col(c, a);
  Paint stroke(Rgb c, double width, [double a = 1]) => Paint()
    ..color = col(c, a)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  void circle(double x, double y, double r, Paint p) => canvas.drawCircle(Offset(x, y), r, p);
  void ellipse(double x, double y, double rx, double ry, double rot, Paint p) {
    canvas.save();
    canvas.translate(x, y);
    if (rot != 0) canvas.rotate(rot);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), p);
    canvas.restore();
  }
}

Offset _qpt(TreeSeg s, double f) {
  final a = (1 - f) * (1 - f), b = 2 * (1 - f) * f, c = f * f;
  return Offset(a * s.x0 + b * s.cx + c * s.x1, a * s.y0 + b * s.cy + c * s.y1);
}

Offset _qtan(TreeSeg s, double f) {
  final dx = 2 * (1 - f) * (s.cx - s.x0) + 2 * f * (s.x1 - s.cx), dy = 2 * (1 - f) * (s.cy - s.y0) + 2 * f * (s.y1 - s.cy);
  final l = math.sqrt(dx * dx + dy * dy);
  final k = l == 0 ? 1.0 : l;
  return Offset(dx / k, dy / k);
}

void _limbBand(_Brush b, TreeSeg s, double f, double uA, double uB, double thick, Paint paint) {
  const n = 6;
  final l = <Offset>[], r = <Offset>[];
  for (var i = 0; i <= n; i++) {
    final v = (i / n) * f, p = _qpt(s, v), t = _qtan(s, v), w = lerp(s.w0, s.w1, v) * thick;
    final nx = -t.dy, ny = t.dx;
    l.add(Offset(p.dx + nx * w * uA, p.dy + ny * w * uA));
    r.add(Offset(p.dx + nx * w * uB, p.dy + ny * w * uB));
  }
  final path = Path()..moveTo(l[0].dx, l[0].dy);
  for (var i = 1; i <= n; i++) {
    path.lineTo(l[i].dx, l[i].dy);
  }
  for (var i = n; i >= 0; i--) {
    path.lineTo(r[i].dx, r[i].dy);
  }
  path.close();
  b.canvas.drawPath(path, paint);
}

List<Rgb> _leafColours(TreeSpecies sp, double touch) {
  final end = sp.touch == 'blossom' ? sp.leaf : sp.leafEnd;
  return [for (var i = 0; i < 3; i++) _mix(hexRgb(sp.leaf[i]), hexRgb(end[i]), touch)];
}

void _drawRoots(_Brush b, TreeGeometry geo, TreeSpecies sp, double thick, double sc) {
  if (geo.segs.isEmpty) return;
  final t = geo.segs.first;
  final w = t.w0 * thick, bark = hexRgb(sp.bark);
  final c = b.canvas;
  final flare = Path()
    ..moveTo(-w * 0.95, 1.5)
    ..quadraticBezierTo(-w * 0.5, -w * 0.15, -w * 0.48, -w * 1.5)
    ..lineTo(w * 0.48, -w * 1.5)
    ..quadraticBezierTo(w * 0.5, -w * 0.15, w * 0.95, 1.5)
    ..close();
  c.drawPath(flare, b.fill(bark));
  for (final r in geo.roots) {
    final len = w * (0.7 + r.len * 0.6) / math.max(0.6, sc), s = r.side.toDouble();
    final p = Path()
      ..moveTo(s * w * 0.25, -w * 0.5)
      ..quadraticBezierTo(s * w * 0.6, -w * 0.05, s * (w * 0.5 + len), 2)
      ..lineTo(s * w * 0.2, 2)
      ..close();
    c.drawPath(p, b.fill(bark));
  }
  final shade = Path()
    ..moveTo(w * 0.15, -w * 1.4)
    ..lineTo(w * 0.48, -w * 1.5)
    ..quadraticBezierTo(w * 0.5, -w * 0.15, w * 0.95, 1.5)
    ..lineTo(w * 0.2, 1.5)
    ..close();
  c.drawPath(shade, b.fill(hexRgb(sp.barkLo), 0.45));
}

void _drawLimbs(_Brush b, TreeGeometry geo, TreeSpecies sp, TreeReveal rv) {
  final bark = hexRgb(sp.bark), hi = hexRgb(sp.barkHi), lo = hexRgb(sp.barkLo);
  for (final s in geo.segs) {
    final f = clamp01((rv.rr - s.t0) / (s.t1 - s.t0));
    if (f <= 0.001) continue;
    final paint = b.fill(bark);
    if (s.w0 * rv.thick > 2.2) {
      final p = _qpt(s, f * 0.48), t = _qtan(s, f * 0.48);
      final across = Offset(-t.dy, t.dx) * s.w0 * rv.thick * 0.58;
      paint.shader = Gradient.linear(p - across, p + across, [b.col(bark), b.col(hi), b.col(bark), b.col(lo)], [0, 0.25, 0.58, 1]);
    }
    _limbBand(b, s, f, -0.5, 0.5, rv.thick, paint);
    if (s.d > 0) b.circle(s.x0, s.y0, s.w0 * rv.thick * 0.48, b.fill(bark));
  }
  for (final m in geo.bark) {
    final s = geo.segs[m.s];
    final f = clamp01((rv.rr - s.t0) / (s.t1 - s.t0));
    if (f < m.v1) continue;
    if (sp.barkStyle == 'birch' || sp.barkStyle == 'bands') {
      final p = _qpt(s, m.v0), t = _qtan(s, m.v0), w = lerp(s.w0, s.w1, m.v0) * rv.thick, nx = -t.dy, ny = t.dx;
      final u0 = m.u - 0.12, u1 = math.min(0.48, m.u + 0.22);
      final paint = sp.barkStyle == 'birch' ? b.stroke([52, 44, 36], math.max(1, w * 0.09), 0.75) : b.stroke(hi, 0.9, 0.6);
      b.canvas.drawLine(Offset(p.dx + nx * w * u0, p.dy + ny * w * u0), Offset(p.dx + nx * w * u1, p.dy + ny * w * u1), paint);
    } else {
      final path = Path();
      for (var i = 0; i <= 4; i++) {
        final v = lerp(m.v0, m.v1, i / 4), p = _qpt(s, v), t = _qtan(s, v), w = lerp(s.w0, s.w1, v) * rv.thick;
        final x = p.dx - t.dy * w * m.u, y = p.dy + t.dx * w * m.u;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      b.canvas.drawPath(path, b.stroke(lo, 0.9, 0.5));
    }
  }
}

void _leaf(Path path, Offset base, Offset tip, double width) {
  final length = tip.distance;
  if (length == 0) return;
  final normal = Offset(-tip.dy, tip.dx) * (width / length);
  final end = base + tip, a = base + tip * 0.27 + normal, z = base + tip * 0.72 + normal;
  final c = base + tip * 0.65 - normal * 0.76, d = base + tip * 0.23 - normal * 0.76;
  path
    ..moveTo(base.dx, base.dy)
    ..cubicTo(a.dx, a.dy, z.dx, z.dy, end.dx, end.dy)
    ..cubicTo(c.dx, c.dy, d.dx, d.dy, base.dx, base.dy)
    ..close();
}

({Path outline, Path shadows, Path glints}) _canopyPatch(TreeClump clump) {
  final rnd = mulberry32((clump.x * 827 + clump.y * 613).round());
  final outline = Path(), shadows = Path(), glints = Path();
  for (final blob in clump.blobs) {
    final center = Offset(blob.dx, blob.dy), radius = blob.r;
    final points = List.generate(10, (i) {
      final a = i * math.pi / 5, size = radius * (0.76 + rnd() * 0.34);
      return center + Offset(math.cos(a) * size * 1.08, math.sin(a) * size * 0.86);
    });
    final start = (points.last + points.first) / 2;
    outline.moveTo(start.dx, start.dy);
    for (var i = 0; i < points.length; i++) {
      final point = points[i], end = (point + points[(i + 1) % points.length]) / 2;
      outline.quadraticBezierTo(point.dx, point.dy, end.dx, end.dy);
    }
    outline.close();
    for (var i = 0; i < 5; i++) {
      final a = rnd() * math.pi * 2, spread = 0.25 + rnd() * 0.52, len = radius * (0.18 + rnd() * 0.30);
      final direction = Offset(math.cos(a), math.sin(a));
      final base = center + Offset(direction.dx, direction.dy * 0.85) * (radius * spread);
      _leaf(direction.dy < -0.16 ? glints : shadows, base, direction * len, len * 0.35);
    }
  }
  return (outline: outline, shadows: shadows, glints: glints);
}

// Geometry is shared by the card and forest. Cache the paths in clump-local
// coordinates so a growth frame only scales them and changes the lighting.
final _patches = Expando<({Path outline, Path shadows, Path glints})>();
({Path outline, Path shadows, Path glints}) _patchFor(TreeClump c) => _patches[c] ??= _canopyPatch(c);


void _drawClumps(_Brush b, List<TreeClump> clumps, List<Rgb> cols, TreeReveal rv,
    {required double top, required double bot, bool back = false, double alpha = 1, double shrink = 1}) {
  final dark = cols[0], mid = cols[1], light = cols[2];
  final span = math.max(1.0, bot - top);
  final canvas = b.canvas, paint = Paint();
  final shadows = b.fill(dark, alpha * 0.54), glints = b.fill(light, alpha * (back ? 0.39 : 0.70));
  for (final clump in clumps) {
    final k = _easeOut((rv.rr - clump.t) / 0.20) * shrink;
    if (k <= 0.01) continue;
    final patch = _patchFor(clump);
    final depth = clamp01((clump.y - top) / span), r = clump.r;
    paint.shader = Gradient.linear(Offset(-r * 0.6, -r * 0.9), Offset(r * 0.45, r), [
      b.col(_mix(mid, light, back ? 0.24 : 0.78 - depth * 0.3), alpha),
      b.col(_mix(mid, dark, back ? 0.42 : depth * 0.36), alpha),
      b.col(_shade(dark, back ? -0.14 : 0), alpha),
    ], [0, 0.51, 1]);
    canvas.save();
    canvas.translate(clump.x, clump.y);
    canvas.scale(k, k);
    canvas.drawPath(patch.outline, paint);
    canvas.drawPath(patch.shadows, shadows);
    canvas.drawPath(patch.glints, glints);
    canvas.restore();
  }
}

({Path sprays, Path needles}) _tierPaths(TreeTier tier, double k) {
  final y = tier.y, w = tier.w * k, h = tier.h * (0.45 + 0.55 * k), x = tier.lean * k;
  final sprays = Path(), needles = Path();
  for (final side in const [-1.0, 1.0]) {
    for (var i = 0; i < 4; i++) {
      final v = i / 3, tipX = x + side * w * lerp(1, 0.12, v);
      final tipY = y + h * (0.09 + v * 0.18 + (i % 2) * 0.065);
      final startY = y - h * lerp(0.77, 0.92, v), inner = x + (tipX - x) * 0.75;
      sprays
        ..moveTo(x, startY)
        ..quadraticBezierTo(inner, y - h * 0.06, tipX, tipY)
        ..quadraticBezierTo(inner, tipY + h * 0.04, inner, tipY - h * 0.07)
        ..lineTo(inner - side * w * 0.13, tipY + h * 0.06)
        ..quadraticBezierTo(x, tipY + h * 0.09, x, startY)
        ..close();
      if (i < 3) {
        _leaf(needles, Offset(x + (tipX - x) * 0.33, y - h * (0.38 - v * 0.16)),
            Offset((tipX - x) * 0.51, h * 0.31), math.min(w * 0.033, h * 0.044));
      }
    }
  }
  _leaf(sprays, Offset(x, y - h * 0.30), Offset(x * 0.2, -h * 0.72), w * 0.28);
  return (sprays: sprays, needles: needles);
}

void _drawTiers(_Brush b, TreeGeometry geo, List<Rgb> cols, TreeReveal rv) {
  final dark = cols[0], mid = cols[1], light = cols[2];
  final glints = b.fill(light, 0.49);
  for (final tier in geo.tiers) {
    final k = _easeOut((rv.rr - tier.t) / 0.23);
    if (k <= 0.01) continue;
    final y = tier.y, w = tier.w * k, h = tier.h * (0.45 + 0.55 * k), x = tier.lean * k;
    final paint = Paint()..shader = Gradient.linear(
      Offset(x - w * 0.5, y - h), Offset(x + w * 0.43, y + h * 0.16),
      [b.col(light), b.col(mid), b.col(dark)], [0, 0.63, 1],
    );
    final paths = _tierPaths(tier, k);
    b.canvas.drawPath(paths.sprays, paint);
    b.canvas.drawPath(paths.needles, glints);
  }
}

/// Hit shape in the same local coordinates used by the painter.
Path matureTreeOutline(TreeGeometry geo, [TreeReveal? reveal]) {
  final rv = reveal ?? revealAt(7);
  final outline = Path();
  for (final clump in geo.clumps) {
    final k = _easeOut((rv.rr - clump.t) / 0.20);
    if (k <= 0.01) continue;
    outline.addPath(_patchFor(clump).outline, Offset.zero, matrix4: Float64List.fromList([
      k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, clump.x, clump.y, 0, 1,
    ]));
  }
  for (final tier in geo.tiers) {
    final k = _easeOut((rv.rr - tier.t) / 0.23);
    if (k > 0.01) outline.addPath(_tierPaths(tier, k).sprays, Offset.zero);
  }
  for (final seg in geo.segs) {
    final f = clamp01((rv.rr - seg.t0) / (seg.t1 - seg.t0));
    if (f <= 0.001) continue;
    final start = _qpt(seg, 0), end = _qpt(seg, f);
    final a = _qtan(seg, 0), z = _qtan(seg, f);
    final lhs = Offset(-a.dy, a.dx) * (seg.w0 * rv.thick / 2 + 2);
    final rhs = Offset(-z.dy, z.dx) * (lerp(seg.w0, seg.w1, f) * rv.thick / 2 + 2);
    outline.addPolygon([start + lhs, end + rhs, end - rhs, start - lhs], true);
  }
  return outline;
}

void _drawStrands(_Brush b, TreeGeometry geo, List<Rgb> cols, TreeReveal rv, int half) {
  final dark = cols[0], mid = cols[1], light = cols[2];
  void pass(Rgb col, double w, double a) {
    final path = Path();
    for (var i = 0; i < geo.strands.length; i++) {
      final s = geo.strands[i];
      if (i % 2 != half) continue;
      final k = _easeOut((rv.rr - s.t) / 0.25);
      if (k <= 0.01) continue;
      final len = math.min(s.len * k, -s.y - 8);
      path.moveTo(s.x, s.y);
      path.quadraticBezierTo(s.x + s.dx * len * 0.6, s.y + len * 0.45, s.x + s.dx * len * 0.3, s.y + len);
    }
    b.canvas.drawPath(path, b.stroke(col, w, a));
  }

  pass(dark, 5, half == 1 ? 1 : 0.85);
  pass(mid, 2.6, 1);
  if (half == 1) pass(light, 1, 0.7);
}

void _drawTouches(_Brush b, TreeGeometry geo, TreeSpecies sp, TreeReveal rv) {
  final a = rv.touch;
  if (a <= 0.01 || geo.touches.isEmpty) return;
  final saved = b.ga;
  b.ga = saved * a;
  for (final t in geo.touches) {
    if (_easeOut((rv.rr - t.t) / 0.16) < 0.9) continue;
    switch (t.kind) {
      case 'fruit':
        b.circle(t.x, t.y, t.r, b.fill(hexRgb('#b8322a')));
        b.circle(t.x - t.r * 0.35, t.y - t.r * 0.35, t.r * 0.35, b.fill([255, 170, 140], 0.8));
      case 'acorns':
        b.ellipse(t.x, t.y + 1, t.r * 0.8, t.r * 1.1, 0, b.fill(hexRgb('#8a6a32')));
        b.ellipse(t.x, t.y - t.r * 0.3, t.r * 0.95, t.r * 0.5, 0, b.fill(hexRgb('#5c4222')));
      case 'blossom':
        final petals = Path();
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * math.pi / 5 + t.x * 0.18;
          petals.addOval(Rect.fromCircle(center: Offset(t.x + math.cos(a) * t.r * 0.60, t.y + math.sin(a) * t.r * 0.60), radius: t.r * 0.59));
        }
        b.canvas.drawPath(petals, b.fill([255, 246, 249], 0.95));
        b.circle(t.x, t.y, t.r * 0.34, b.fill(hexRgb('#d77c92')));
      case 'catkins':
        final p = Path()
          ..moveTo(t.x, t.y)
          ..quadraticBezierTo(t.x + 1.5, t.y + 4, t.x + 0.5, t.y + 8);
        b.canvas.drawPath(p, b.stroke(hexRgb('#b9a34e'), 1.8));
      case 'cones':
        b.ellipse(t.x, t.y + 3, 2.2, 3.6, 0, b.fill(hexRgb('#6b4a2c')));
    }
  }
  b.ga = saved;
}

void _drawWoody(_Brush b, TreeGeometry geo, TreeSpecies sp, TreeReveal rv) {
  final c = b.canvas;
  c.save();
  c.scale(rv.sc, rv.sc);
  final cols = _leafColours(sp, rv.touch);
  final back = <TreeClump>[], front = <TreeClump>[];
  for (var i = 0; i < geo.clumps.length; i++) {
    ((i % 5 == 1 || i % 5 == 3) ? back : front).add(geo.clumps[i]);
  }
  back.sort((a, z) => a.y.compareTo(z.y));
  front.sort((a, z) => a.y.compareTo(z.y));
  if (sp.form == 'conifer') {
    _drawLimbs(b, geo, sp, rv);
    _drawRoots(b, geo, sp, rv.thick, rv.sc);
    _drawTiers(b, geo, cols, rv);
  } else {
    final top = geo.crownTop, bot = geo.crownBot;
    _drawClumps(b, back, cols, rv, top: top, bot: bot, back: true);
    if (sp.form == 'willow') _drawStrands(b, geo, cols, rv, 0);
    _drawRoots(b, geo, sp, rv.thick, rv.sc);
    _drawLimbs(b, geo, sp, rv);
    _drawClumps(b, front, cols, rv, top: top, bot: bot);
    if (sp.touch == 'blossom' && rv.touch > 0.01) {
      _drawClumps(b, front, [for (final h in sp.leafEnd) hexRgb(h)], rv, top: top, bot: bot, alpha: rv.touch, shrink: 0.91);
    }
    if (sp.form == 'willow') _drawStrands(b, geo, cols, rv, 1);
  }
  _drawTouches(b, geo, sp, rv);
  c.restore();
}


void _drawYoung(_Brush b, TreeSpecies species, double s, double alpha) {
  if (alpha <= 0.01) return;
  final c = b.canvas, saved = b.ga;
  c.save();
  c.scale(_youngScale, _youngScale);
  b.ga = saved * alpha;
  final pine = species.form == 'conifer';
  final slender = pine || species.form == 'willow';
  if (s < 1.66) {
    final bury = smooth(0, 1.18, s), fade = 1 - smooth(0.70, 1.58, s);
    c.save();
    c.clipRect(Rect.fromLTWH(-14, -16, 28, 16 - 4.2 * bury));
    c.translate(-0.6 + bury, -6.9 + bury * 5.4);
    c.rotate(-0.44 + bury * 0.19);
    b.ga = saved * alpha * fade;
    final w = slender ? 4.7 : 5.7, h = slender ? 2.5 : 3.9;
    final seed = Path()
      ..moveTo(w, 0)
      ..cubicTo(w * 0.36, -h * 1.34, -w * 0.93, -h * 1.12, -w, -h * 0.12)
      ..cubicTo(-w * 1.06, h * 1.23, w * 0.54, h * 1.13, w, 0)
      ..close();
    c.drawPath(seed, Paint()..shader = Gradient.linear(Offset(-w * 0.8, -h), Offset(w * 0.6, h), [
      b.col(hexRgb('#e0b885')), b.col(hexRgb('#ad7746')), b.col(hexRgb('#825233')), b.col(hexRgb('#5e3927')),
    ], [0, 0.39, 0.74, 1]));
    c.drawPath(Path()
      ..moveTo(-w * 0.70, -h * 0.32)
      ..quadraticBezierTo(-w * 0.19, -h * 0.84, w * 0.45, -h * 0.23),
      b.stroke(hexRgb('#f3d29e'), 0.55, 0.64));
    c.restore();
    b.ga = saved * alpha;
  }
  if (s > 1) {
    final rise = smooth(1, 2, s), grow = smooth(2, 3.22, s);
    final h = 2 + 18 * rise + 24 * grow;
    final stem = TreeSeg(0, -1, 6.2 + grow * 0.8, -h * 0.54, 2.2 - rise * 2.8 + grow * 2.2, -h,
        0.7 + rise * 1.2 + grow * 1.5, 0.64, 0, 0, 1);
    final green = _mix(hexRgb('#699346'), hexRgb(species.bark), smooth(3, 3.75, s));
    b.ga = saved * alpha * smooth(1, 1.31, s);
    _limbBand(b, stem, 1, -0.5, 0.5, 1, Paint()..shader = Gradient.linear(Offset(0, -h), const Offset(3, 1), [
      b.col(hexRgb('#b6cf72')), b.col(green), b.col(_mix(green, hexRgb('#4a5532'), 0.37)),
    ], [0, 0.51, 1]));

    void leaf(double along, double side, double length, double width, double up, {bool starter = false}) {
      final base = _qpt(stem, along), tip = Offset(side * length, -length * up);
      final body = Path();
      _leaf(body, base, tip, width);
      final paint = Paint()..shader = Gradient.linear(base, base + Offset(tip.dx * 0.76, tip.dy - width * 0.42), [
        b.col(hexRgb('#4f792f')),
        b.col(_mix(hexRgb(species.leaf[1]), hexRgb('#93b75a'), starter ? 0.74 : 0.35)),
        b.col(_mix(hexRgb(species.leaf[2]), hexRgb('#d8dd91'), starter ? 0.52 : 0.24)),
      ], [0, 0.62, 1]);
      c.drawPath(body, paint);
      if (length < 2 || pine) return;
      c.drawPath(Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(base.dx + tip.dx * 0.46, base.dy + tip.dy * 0.32, base.dx + tip.dx * 0.85, base.dy + tip.dy * 0.82),
        b.stroke(hexRgb('#dce5a3'), 0.42, 0.64));
    }
    final starter = 1.8 + rise * 7.2 - grow * 2.2;
    leaf(1 - grow * 0.56, -1, starter, starter * (slender ? 0.21 : 0.43), 0.36, starter: true);
    leaf(1 - grow * 0.58, 1, starter * 0.88, starter * (slender ? 0.21 : 0.41), 0.55, starter: true);
    for (var i = 0; i < 4; i++) {
      final open = smooth(i * 0.15, 0.53 + i * 0.14, grow);
      if (open < 0.01) continue;
      final len = (11.5 - i * 1.4) * open, side = i.isOdd ? -1.0 : 1.0, along = 0.53 + i * 0.13;
      leaf(along, side, len, len * (slender ? 0.22 : 0.53), 0.52 + i * 0.14);
      if (pine) leaf(along, -side, len * 0.82, len * 0.15, 1.20);
    }
    final bud = smooth(2.2, 2.92, s);
    if (bud > 0) {
      final tip = Path();
      _leaf(tip, Offset(stem.x1, stem.y1 + 1), Offset(-0.4, -4.6 * bud), 1.8 * bud);
      c.drawPath(tip, b.fill(hexRgb('#8eae58')));
    }
  }
  c.restore();
  b.ga = saved;
}

void _drawSoil(_Brush b, double s, double wet) {
  final fade = 1 - smooth(4.2, 5.6, s);
  final mound = smooth(0.15, 1, s);
  final c = b.canvas;
  final saved = b.ga;
  c.save();
  b.ga = saved * (0.35 + 0.65 * fade);
  final rx = 30 - 6 * (1 - fade);
  final patch = Paint()
    ..shader = Gradient.radial(
      Offset.zero,
      rx,
      [b.col(_mix([118, 84, 56], [70, 48, 32], wet)), b.col(_mix([126, 92, 60], [84, 58, 38], wet), 0.85), b.col([120, 90, 60], 0)],
      [0.0, 0.75, 1.0],
    );
  c.save();
  c.scale(1, 0.26);
  c.drawCircle(const Offset(0, 4), rx, patch);
  c.restore();
  if (fade > 0.01) {
    b.ga = saved * fade;
    final h = 2 + 5 * mound;
    final hill = Path()
      ..moveTo(-17, 2)
      ..quadraticBezierTo(-9, -h, 0, -h)
      ..quadraticBezierTo(9, -h, 17, 2)
      ..close();
    c.drawPath(hill, b.fill(_mix([132, 96, 63], [86, 60, 40], wet)));
    final light = Path()
      ..moveTo(-12, -h * 0.4)
      ..quadraticBezierTo(-6, -h * 1.05, 2, -h * 0.95)
      ..quadraticBezierTo(-4, -h * 0.6, -12, -h * 0.4);
    c.drawPath(light, b.fill(_mix([160, 122, 84], [108, 78, 52], wet), 0.7));
    final clod = b.fill(_mix([104, 74, 48], [62, 42, 28], wet));
    for (final p in const [[-13.0, 0.0, 2.0], [10.0, -1.0, 2.4], [15.0, 1.5, 1.6], [-6.0, 1.8, 1.4], [5.0, 2.0, 1.7]]) {
      b.ellipse(p[0], p[1], p[2] * 1.3, p[2], 0, clod);
    }
    final shine = math.max(wet, smooth(0.6, 1, s) * (1 - smooth(1.5, 2.2, s)) * 0.6);
    if (shine > 0.02) b.ellipse(-4, -h * 0.75, 6, 1.2, -0.1, b.fill([200, 225, 240], 0.35 * shine));
  }
  c.restore();
  b.ga = saved;
}

/// Draws species [sp] at stage [s] (0..7) with the trunk's base at the origin. [soil] adds the planting spot of the tree
/// being grown; [wet] (0..1) darkens it after watering.
void paintTree(Canvas canvas, TreeGeometry geo, TreeSpecies sp, double s, {bool soil = false, double wet = 0, Rgb? light, double opacity = 1}) {
  final b = _Brush(canvas)..ga = opacity;
  if (light != null) b.light = light;
  if (soil) _drawSoil(b, s, wet);
  final rv = revealAt(s);
  final woody = s > 3 && s < 4 ? smooth(3.15, 3.75, s) : rv.tree;
  final young = s > 3 && s < 4 ? 1 - smooth(3.34, 3.88, s) : rv.seedling;
  if (woody > 0.01) {
    b.ga = opacity * woody;
    _drawWoody(b, geo, sp, rv);
    b.ga = opacity;
  }
  _drawYoung(b, sp, s, young);
}

/// Just the planting spot (turned earth) of the tree being grown, at the origin.
void paintSoil(Canvas canvas, double s, double wet, {Rgb? light, double opacity = 1}) {
  final b = _Brush(canvas)..ga = opacity;
  if (light != null) b.light = light;
  _drawSoil(b, s, wet);
}

/// A little watering can standing on the ground, drawn at the origin.
void paintWateringCan(Canvas canvas, {double tilt = 0, double alpha = 1}) {
  final b = _Brush(canvas)..ga = alpha;
  final c = canvas;
  c.save();
  if (tilt != 0) c.rotate(tilt);
  final body = Path()
    ..moveTo(-12, -9)
    ..lineTo(10, -9)
    ..quadraticBezierTo(13, -9, 13, -6)
    ..lineTo(13, 8)
    ..quadraticBezierTo(13, 11, 10, 11)
    ..lineTo(-12, 11)
    ..quadraticBezierTo(-15, 11, -15, 8)
    ..lineTo(-15, -6)
    ..quadraticBezierTo(-15, -9, -12, -9)
    ..close();
  c.drawPath(body, b.fill(hexRgb('#7fa6b8')));
  c.drawRect(const Rect.fromLTWH(-12, -6, 6, 14), b.fill(hexRgb('#9cc0cf')));
  final spout = Path()
    ..moveTo(-13, -2)
    ..lineTo(-30, -14)
    ..lineTo(-32, -11)
    ..lineTo(-14, 4)
    ..close();
  c.drawPath(spout, b.fill(hexRgb('#6b93a6')));
  b.ellipse(-31, -12.5, 2.5, 4, -0.9, b.fill(hexRgb('#6b93a6')));
  final handle = Path()
    ..moveTo(10, -6)
    ..quadraticBezierTo(22, -6, 20, 6);
  c.drawPath(handle, b.stroke(hexRgb('#6b93a6'), 2.6));
  c.restore();
}
