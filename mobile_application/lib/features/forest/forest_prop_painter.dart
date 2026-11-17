import 'dart:math' as math;
import 'dart:ui';

import '../../domain/forest/forest_habitat.dart';
import '../../domain/forest/tree_geometry.dart';
import 'tree_painter.dart' show hexRgb;

/// The approved canvas artwork, with the base of the landmark at (0, 0).
/// Slow growth is recorded into a picture by ForestWorld rather than rebuilt
/// every animation frame. All colors receive the same light as the trees.
void paintForestProp(Canvas canvas, ForestProp prop, DateTime now,
    {required List<double> light, bool wet = false, double snow = 0}) {
  final b = _PropInk(canvas, light);
  final age = prop.ageAt(now), fraction = prop.returnFraction(now);
  if (fraction >= 1) {
    b.alpha = 1 - smooth(1, 1.5, fraction);
    b.oval(0, 3, 30, 4, '#7e9a63', 0.33);
    b.fern(13, 3, 0.35);
    b.flowers(-9, 4, 0.32, prop.id + 70, 3);
    return;
  }
  final k = prop.returnProgress(now), stone = prop.kind == ForestPropKind.stone;
  canvas.save();
  canvas.clipRect(const Rect.fromLTWH(-65, -75, 130, 78));
  canvas.translate(0, (stone ? 27 : 23) * k * k * k);
  canvas.scale(1, 1 - (stone ? 0.08 : 0.15) * k);
  if (stone) {
    b.oval(0, 5, 25, 5, '#314f40', 0.19);
    b.path(Path()..moveTo(-23, 2)..lineTo(-15, -12)
      ..quadraticBezierTo(0, -23, 15, -11)..lineTo(24, 4)
      ..quadraticBezierTo(4, 12, -23, 2)..close(), wet ? '#788a7c' : '#909c88');
    b.path(Path()..moveTo(-18, -3)..lineTo(-11, -12)
      ..quadraticBezierTo(1, -18, 12, -10)..lineTo(5, -4)..close(), '#b6c0a5');
    b.alpha = smooth(3, 8, age);
    for (var i = 0; i < 5; i++) {
      b.oval(-11 + i * 5.0, -8 + math.sin(i) * 2, 2.5, 1.4, '#c4be87');
    }
    b.alpha = smooth(7, 14, age);
    b.path(Path()..moveTo(-23, 2)..quadraticBezierTo(-6, -10, 9, -5)
      ..quadraticBezierTo(13, 5, 22, 5)..quadraticBezierTo(2, 14, -23, 2)..close(), '#6e8b59');
    b.alpha = 1;
    if (age > 12) b.fern(24, 3, 0.85 * smooth(12, 22, age));
    b.alpha = smooth(18, 26, age);
    b.flowers(-26, 6, 0.36, prop.id + 90, 4);
  } else {
    b.oval(0, 3, 35, 6, '#263b29', 0.16);
    b.line(Path()..moveTo(-29, 0)..quadraticBezierTo(0, -3, 28, -5), wet ? '#594b3a' : '#6c5941', 16);
    b.line(Path()..moveTo(-25, -5)..lineTo(22, -9), '#927658', 2);
    b.oval(-28, 0, 7, 9, '#bd9e71');
    b.oval(-28, 0, 4.8, 6.4, '#876e4d');
    b.oval(-28, 0, 2.2, 3.4, '#c3a981');
    b.alpha = smooth(2, 7, age);
    for (var i = 0; i < 8; i++) {
      b.oval(-18 + i * 6.0, -7 + math.sin(i) * 2, 4, 2, '#76905a');
    }
    b.fern(29, 4, 0.25 + 0.3 * smooth(3, 10, age));
    b.alpha = 1;
    if (age >= 8) {
      for (var i = 0; i < (wet ? 5 : 3); i++) {
        b.mushroom(-8 + i * 8.0, -6, smooth(8, 15, age) * 0.8);
      }
    }
    b.alpha = smooth(12, 18, age);
    b.flowers(-9, 6, 0.52, prop.id + 65, 7);
    b.alpha = smooth(0, 0.25, k);
    b.line(Path()..moveTo(-6, -12)..lineTo(-10, -7)..lineTo(-4, -5)..lineTo(-8, 5), '#3e392e', 2);
    b.line(Path()..moveTo(15, -12)..lineTo(11, -8)..lineTo(17, -5), '#4b4232', 1.5);
    b.oval(-34, 4, 4, 2, '#77634b');
    b.oval(30, 3, 5, 2, '#917657');
  }
  b.alpha = snow * 0.85;
  if (stone) {
    b.path(Path()..moveTo(-15, -12)..quadraticBezierTo(0, -23, 15, -11)
      ..lineTo(11, -7)..quadraticBezierTo(0, -12, -12, -7)..close(), '#e6ede7');
  } else {
    b.line(Path()..moveTo(-24, -8)..quadraticBezierTo(0, -11, 24, -12), '#e6ede7', 3.3);
  }
  canvas.restore();
  b.alpha = smooth(0, 0.5, k);
  if (k > 0) {
    b.oval(0, 3, stone ? 27 : 35, 4, '#819564', 0.6);
    for (var j = 0; j < 9; j++) {
      final x = -29 + j * 7.0;
      b.line(Path()..moveTo(x, 5)..quadraticBezierTo(x - 2, 0, x - 4, -3 - (j % 3) * 2), '#658155', 1.4);
      b.oval(x + 1, 1, 3.2, 1.4, '#94aa6b');
    }
  }
}

class _PropInk {
  _PropInk(this.canvas, this.light);
  final Canvas canvas;
  final List<double> light;
  double alpha = 1;

  Color color(String hex, [double opacity = 1]) {
    final rgb = hexRgb(hex);
    return Color.fromRGBO((rgb[0] * light[0] / 255).round().clamp(0, 255),
      (rgb[1] * light[1] / 255).round().clamp(0, 255),
      (rgb[2] * light[2] / 255).round().clamp(0, 255), clamp01(alpha * opacity));
  }
  void oval(double x, double y, double rx, double ry, String hex, [double opacity = 1]) {
    canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
        Paint()..color = color(hex, opacity));
  }
  void line(Path path, String hex, double width) => canvas.drawPath(path, Paint()
    ..color = color(hex)..style = PaintingStyle.stroke..strokeWidth = width..strokeCap = StrokeCap.round);
  void path(Path path, String hex) => canvas.drawPath(path, Paint()..color = color(hex));

  void mushroom(double x, double y, double scale) {
    if (scale <= 0) return;
    line(Path()..moveTo(x, y)..lineTo(x, y - 9 * scale), '#d6c4a2', 2.2 * scale);
    oval(x, y - 9 * scale, 6 * scale, 3 * scale, '#bd8b73');
    oval(x - 1.5 * scale, y - 10 * scale, scale, 0.7 * scale, '#ebd4b4');
  }
  void fern(double x, double y, double scale) {
    if (scale <= 0) return;
    canvas.save();canvas.translate(x, y);canvas.scale(scale, scale);
    for (var j = -2; j <= 2; j++) {
      final ex = j * 8.0, ey = -23.0 + j.abs() * 3;
      line(Path()..moveTo(0, 0)..quadraticBezierTo(ex * 0.2, -15, ex, ey), '#597a53', 1.2);
      for (var k = 1; k <= 5; k++) {
        final f = k / 6, xx = ex * f * f, yy = ey * f;
        line(Path()..moveTo(xx - 6 * (1 - f), yy - 3)..lineTo(xx, yy)
          ..lineTo(xx + 6 * (1 - f), yy - 3), '#718e5f', 1.8);
      }
    }
    canvas.restore();
  }
  void flowers(double x, double y, double scale, int seed, int count) {
    final random = mulberry32(seed);
    for (var i = 0; i < count; i++) {
      final xx = x + (random() - 0.5) * 68 * scale;
      final yy = y + (random() - 0.5) * 15 * scale;
      final s = scale * (0.7 + random() * 0.5);
      final hex = const ['#edc5b0', '#e4dfab', '#bbabd0', '#fff1d1'][(random() * 4).floor()];
      line(Path()..moveTo(xx, yy)..quadraticBezierTo(xx + 2 * s, yy - 6 * s, xx, yy - 11 * s), '#628153', s);
      oval(xx - 3 * s, yy - 4 * s, 3 * s, 1.3 * s, '#8fa663');
      for (var petal = 0; petal < 5; petal++) {
        final a = petal * math.pi * 2 / 5;
        oval(xx + math.cos(a) * 2.7 * s, yy - 11 * s + math.sin(a) * 2.7 * s, 2.1 * s, 1.7 * s, hex);
      }
      oval(xx, yy - 11 * s, 1.3 * s, 1.3 * s, '#e7b864');
    }
  }
}
