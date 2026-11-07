import 'dart:math' as math;
import 'dart:ui';

import '../../domain/forest/tree_geometry.dart';

/// Draws trees with the trunk's base at the canvas origin, up as negative y: a straight translation of the approved forest
/// prototype's canvas code. Only paths, ovals, circles, gradients and transforms are used.

typedef Rgb = List<double>;

Rgb hexRgb(String h) {
  final n = int.parse(h.substring(1), radix: 16);
  return [((n >> 16) & 255).toDouble(), ((n >> 8) & 255).toDouble(), ((n >> 0) & 255).toDouble()];
}

Rgb _mix(Rgb a, Rgb b, double t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
Rgb _shade(Rgb c, double k) => k >= 0 ? _mix(c, [255, 255, 255], k) : _mix(c, [0, 0, 0], -k);
double _easeInOut(double t) => 0.5 - 0.5 * math.cos(math.pi * clamp01(t));
double _easeOut(double t) => 1 - math.pow(1 - clamp01(t), 3).toDouble();
const _youngScale = 1.6;

class _Brush {
  _Brush(this.canvas);
  final Canvas canvas;

  /// Like the canvas' globalAlpha: multiplies every colour drawn while it is set.
  double ga = 1;

  Color col(Rgb c, [double a = 1]) => Color.fromRGBO(c[0].round().clamp(0, 255), c[1].round().clamp(0, 255), c[2].round().clamp(0, 255), clamp01(a * ga));
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
    _limbBand(b, s, f, -0.5, 0.5, rv.thick, b.fill(bark));
    if (s.w0 * rv.thick > 2.2) {
      _limbBand(b, s, f, 0.12, 0.5, rv.thick, b.fill(lo, 0.5));
      _limbBand(b, s, f, -0.42, -0.2, rv.thick, b.fill(hi, 0.55));
    }
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

void _drawClumps(_Brush b, List<TreeClump> clumps, List<Rgb> cols, TreeReveal rv,
    {required double top, required double bot, bool back = false, double alpha = 1, double shrink = 1}) {
  final list = <(TreeClump, double)>[];
  for (final c in clumps) {
    final k = _easeOut((rv.rr - c.t) / 0.16);
    if (k <= 0.01) continue;
    list.add((c, k * shrink));
  }
  if (list.isEmpty) return;
  final dark = cols[0], mid = cols[1], light = cols[2];
  final span = math.max(1.0, bot - top);
  double vOf(double y) => clamp01((y - top) / span);
  final under = back ? _shade(dark, -0.2) : dark;
  for (final (c, k) in list) {
    for (final bl in c.blobs) {
      b.circle(c.x + bl.dx * k, c.y + bl.dy * k + bl.r * k * 0.2, bl.r * k, b.fill(under, alpha));
    }
  }
  final hiBody = _mix(mid, light, 0.38), loBody = _mix(mid, dark, 0.5);
  for (final (c, k) in list) {
    for (final bl in c.blobs) {
      final y = c.y + bl.dy * k, v = vOf(y);
      b.circle(c.x + bl.dx * k - bl.r * k * 0.05, y - bl.r * k * 0.06, bl.r * k * 0.86, b.fill(_shade(_mix(hiBody, loBody, v), back ? -0.12 : 0), alpha));
    }
  }
  if (back) return;
  for (final (c, k) in list) {
    for (final bl in c.blobs) {
      final x = c.x + bl.dx * k - bl.r * k * 0.22, y = c.y + bl.dy * k - bl.r * k * 0.3, rr = bl.r * k * 0.66, v = vOf(y);
      if (v > 0.7) continue;
      final paint = Paint()..shader = Gradient.radial(Offset(x, y), rr, [b.col(light, 0.75 * alpha * (1 - v)), b.col(light, 0)]);
      b.canvas.drawCircle(Offset(x, y), rr, paint);
    }
  }
}

void _drawTiers(_Brush b, TreeGeometry geo, List<Rgb> cols, TreeReveal rv) {
  final dark = cols[0], mid = cols[1], light = cols[2];
  Path tierPath(TreeTier t, double k, double lift, double sx) {
    final w = t.w * k * sx, h = t.h * (0.5 + 0.5 * k), y = t.y - lift, ax = t.lean * k;
    final p = Path()
      ..moveTo(ax, y - h)
      ..quadraticBezierTo(-w * 0.3, y - h * 0.35, -w, y);
    const m = 5;
    for (var i = 0; i < m; i++) {
      final xa = lerp(-w, w, i / m), xb = lerp(-w, w, (i + 1) / m);
      p.quadraticBezierTo((xa + xb) / 2, y + h * 0.2, xb, y);
    }
    p.quadraticBezierTo(w * 0.3, y - h * 0.35, ax, y - h);
    p.close();
    return p;
  }

  for (final t in geo.tiers) {
    final k = _easeOut((rv.rr - t.t) / 0.22);
    if (k <= 0.01) continue;
    b.canvas.drawPath(tierPath(t, k, 0, 1), b.fill(dark));
    b.canvas.drawPath(tierPath(t, k, t.h * 0.1, 0.86), b.fill(mid));
    final w = t.w * k, h = t.h * (0.5 + 0.5 * k), y = t.y - t.h * 0.12;
    final paint = Paint()..shader = Gradient.linear(Offset(-w * 0.6, y - h), Offset(w * 0.1, y), [b.col(light, 0.8), b.col(light, 0)]);
    final hi = Path()
      ..moveTo(t.lean * k, y - h * 0.95)
      ..quadraticBezierTo(-w * 0.3, y - h * 0.4, -w * 0.78, y - h * 0.05)
      ..quadraticBezierTo(-w * 0.35, y - h * 0.2, t.lean * k, y - h * 0.5)
      ..close();
    b.canvas.drawPath(hi, paint);
  }
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
        b.circle(t.x, t.y, t.r, b.fill([255, 246, 249], 0.95));
        b.circle(t.x, t.y, t.r * 0.4, b.fill(hexRgb('#f19bb6')));
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
      _drawClumps(b, front, [for (final h in sp.leafEnd) hexRgb(h)], rv, top: top, bot: bot, alpha: rv.touch, shrink: 0.82);
    }
    if (sp.form == 'willow') _drawStrands(b, geo, cols, rv, 1);
  }
  _drawTouches(b, geo, sp, rv);
  c.restore();
}

void _drawYoung(_Brush b, double s, double alpha) {
  if (alpha <= 0.01) return;
  final c = b.canvas;
  final saved = b.ga;
  c.save();
  b.ga = saved * alpha;
  c.scale(_youngScale, _youngScale);
  final stemCol = s < 2 ? hexRgb('#a8cf74') : hexRgb('#7fb157');
  if (s < 1.6) {
    final sink = smooth(0, 1, s) * 3, fade = 1 - smooth(1.1, 1.6, s);
    final keep = b.ga;
    b.ga = keep * fade;
    b.ellipse(1, -5.5 + sink, 4.6, 3, -0.4, b.fill(hexRgb('#8a5f35')));
    b.ellipse(-0.2, -6.6 + sink, 1.8, 1, -0.4, b.fill([255, 225, 180], 0.55));
    b.ga = keep;
  }
  if (s > 1) {
    final k = _easeInOut(s - 1), k2 = _easeInOut(s - 2);
    final h = s < 2 ? 4 + 18 * k : 22 + 30 * k2;
    final hook = s < 2 ? (1 - k) * 6 : 0.0;
    final stem = Path()
      ..moveTo(0, -3)
      ..quadraticBezierTo(1.5 + hook, -h * 0.55, hook * 0.6, -h);
    c.drawPath(stem, b.stroke(stemCol, s < 2 ? 2.2 : 2.2 + k2 * 0.9));
    final cy = s < 2 ? -h : -22 - k2 * 2;
    final open = s < 2 ? lerp(0.25, 1.15, k) : 1.15 + k2 * 0.15;
    final size = s < 2 ? lerp(0.45, 1, k) : 1 - k2 * 0.15;
    for (final side in [-1.0, 1.0]) {
      c.save();
      c.translate(s < 2 ? hook * 0.6 : 0, cy);
      c.rotate(side * open);
      b.ellipse(0, -6 * size, 3.4 * size, 6.2 * size, 0, b.fill(hexRgb('#9fcb6a')));
      b.ellipse(-0.8 * size, -7 * size, 1.4 * size, 3.4 * size, 0, b.fill([220, 245, 180], 0.6));
      c.restore();
    }
    if (s > 2) {
      for (var i = 0; i < 4; i++) {
        final g = _easeOut((k2 - i * 0.22) / 0.4);
        if (g <= 0) continue;
        final y = -26 - i * 7.5 * (0.6 + k2 * 0.4), side = i % 2 == 1 ? -1.0 : 1.0, len = (8 + 4 * (3 - i) / 3) * g;
        c.save();
        c.translate(0, y);
        c.rotate(side * (0.95 - i * 0.12));
        final leaf = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(len * 0.45, -len * 0.45, 0, -len * 1.25)
          ..quadraticBezierTo(-len * 0.45, -len * 0.45, 0, 0);
        c.drawPath(leaf, b.fill(hexRgb('#5f9e40')));
        c.drawLine(const Offset(0, -1), Offset(0, -len * 1.05), b.stroke([200, 235, 160], 0.7, 0.7));
        c.restore();
      }
    }
    if (s > 2.2) b.ellipse(0, -h - 1.5, 1.8, 3, 0, b.fill(hexRgb('#8cc35e')));
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
void paintTree(Canvas canvas, TreeGeometry geo, TreeSpecies sp, double s, {bool soil = false, double wet = 0}) {
  final b = _Brush(canvas);
  if (soil) _drawSoil(b, s, wet);
  final rv = revealAt(s);
  if (rv.tree > 0.01) {
    b.ga = rv.tree;
    _drawWoody(b, geo, sp, rv);
    b.ga = 1;
  }
  _drawYoung(b, s, rv.seedling);
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
