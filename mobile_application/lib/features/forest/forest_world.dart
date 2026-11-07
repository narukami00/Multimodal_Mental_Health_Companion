import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Rect, Size;

import '../../domain/forest/forest_garden.dart';
import '../../domain/forest/forest_sky.dart';
import '../../domain/forest/tree_geometry.dart';
import 'forest_card_scene.dart' show geometryFor;
import 'tree_painter.dart' hide Rgb;

/// The forest scene, ported from the approved prototype: the sky of the hour, clouds, hills, ground, grass, the trees at
/// their depths, birds, butterflies, fireflies, drifting petals, weather, and a camera you can pan and zoom, with parallax so
/// near things move more than far ones. Everything is drawn in the prototype's 380 x 680 design space.
const double designW = 380, designH = 680, _cx = 190, _horizon = 360;
const double mainZ = 0.10;
const double _tau = math.pi * 2;

double depthY(double z) => lerp(536, 374, z);
double depthScale(double z) => lerp(0.9, 0.3, z);
double depthParallax(double z) => lerp(1, 0.58, z);

double _easeInOut(double t) => 0.5 - 0.5 * math.cos(math.pi * clamp01(t));
Color _col(Rgb c, [double a = 1]) => Color.fromRGBO(c[0].round().clamp(0, 255), c[1].round().clamp(0, 255), c[2].round().clamp(0, 255), clamp01(a));

/// A shear matrix (x += y * shear) as the 4x4 list Canvas.transform wants.
Float64List _shear(double shear) => Float64List.fromList([1, 0, 0, 0, shear, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

class Slot {
  const Slot(this.x, this.z);
  final double x, z;
}

/// Where each finished tree stands: deterministic and non-overlapping, each placed with the earlier ones in mind.
Slot forestSlot(List<Slot> existing) {
  final i = existing.length, r = mulberry32(9001 + i * 131);
  for (var attempt = 0; attempt < 80; attempt++) {
    final side = (i + attempt) % 2 == 1 ? -1.0 : 1.0;
    final ring = i ~/ 2 + attempt ~/ 8;
    final z = 0.2 + r() * 0.78;
    final x = side * (110 + ring * 62 + r() * 46) / depthParallax(z);
    final sx = x * depthParallax(z), sc = depthScale(z);
    if (z < 0.5 && sx.abs() < 150) continue;
    final ok = existing.every((o) {
      final osx = o.x * depthParallax(o.z);
      return (osx - sx).abs() > (sc + depthScale(o.z)) * 62 || (o.z - z).abs() > 0.32;
    });
    if (ok) return Slot(x, z);
  }
  return Slot((i % 2 == 1 ? -1 : 1) * (240.0 + i * 40), 0.6);
}

class _Star {
  _Star(this.x, this.y, this.r, this.p);
  final double x, y, r, p;
}

class _Puff {
  _Puff(this.dx, this.dy, this.r);
  final double dx, dy, r;
}

class _Cloud {
  _Cloud(this.x0, this.y, this.s, this.depth, this.puffs, this.rank);
  final double x0, y, s, depth, rank;
  final List<_Puff> puffs;
}

class _Hill {
  const _Hill(this.base, this.a, this.f, this.p, this.pf, this.key, {this.trees = false});
  final double base, pf;
  final List<double> a, f, p;
  final String key;
  final bool trees;
  double y(double wx) => base + a[0] * math.sin(wx * f[0] + p[0]) + a[1] * math.sin(wx * f[1] + p[1]) + a[2] * math.sin(wx * f[2] + p[2]);
}

const _hills = [
  _Hill(312, [16, 9, 4], [0.0045, 0.013, 0.031], [1, 2.3, 0.7], 0.1, 'far'),
  _Hill(333, [12, 7, 3], [0.006, 0.017, 0.04], [2.1, 0.4, 1.9], 0.22, 'mid', trees: true),
  _Hill(350, [8, 5, 2], [0.008, 0.021, 0.05], [0.3, 1.7, 2.6], 0.4, 'near', trees: true),
];

// the prototype draws stars and clouds from one generator, in this order
final (List<_Star>, List<_Cloud>) _scenery = () {
  final r = mulberry32(77);
  final stars = List.generate(80, (_) {
    final x = r() * designW, y = r() * 250, rr = 0.5 + r() * 1.1, p = r() * _tau;
    return _Star(x, y, rr, p);
  });
  final clouds = List.generate(10, (i) {
    final depth = r(), n = 5 + (r() * 4).floor();
    final puffs = <_Puff>[];
    for (var k = 0; k < n; k++) {
      final dx = (k - n / 2) * 15 + r() * 8;
      final dy = -math.sin((k / (n - 1)) * math.pi) * (8 + r() * 10);
      puffs.add(_Puff(dx, dy, 12 + r() * 12));
    }
    final x0 = r() * 800;
    final y = 50 + depth * 170 + r() * 30;
    return _Cloud(x0, y, 0.6 + depth * 0.7, depth, puffs, i / 10);
  });
  return (stars, clouds);
}();

class _Drift {
  _Drift(this.x, this.y, this.ty, this.vx, this.vy, this.rot, this.vr, this.col, this.blossom, this.ph, this.max);
  double x, y, vx, vy, rot, life = 0;
  final double ty, vr, ph, max;
  final Color col;
  final bool blossom;
}

class _Drop {
  _Drop(this.x, this.y, this.vx, this.vy, this.ty, {this.faint = false});
  double x, y, vx, vy;
  final double ty;
  final bool faint;
  bool dead = false;
}

class _Spark {
  _Spark(this.x, this.y, this.v, this.life, this.max, this.r, this.ph);
  double x, y, life;
  final double v, max, r, ph;
}

class _Rain {
  _Rain(this.x, this.y, this.v, this.len, this.ty);
  double x, y, v, len, ty;
}

class _Snow {
  _Snow(this.x, this.y, this.v, this.r, this.p, this.ty);
  double x, y, v, r, p, ty;
}

class _Splash {
  _Splash(this.x, this.y, this.t, {this.small = false});
  final double x, y;
  double t;
  final bool small;
}

class _Bird {
  _Bird(this.x, this.y, this.v, this.p, this.f, this.s);
  double x, y, p;
  final double v, f, s;
}

class _Butterfly {
  _Butterfly(this.ax, this.ay, this.p, this.col);
  final double ax, ay;
  double p, a = 0;
  final Color col;
}

class _Firefly {
  _Firefly(this.wx, this.y, this.p, this.f);
  final double wx, y, f;
  double p, a = 0;
}

class _Tuft {
  _Tuft(this.z, this.wx, this.fl, this.side);
  final double z, wx, fl, side;
}

/// What the tap landed on: a finished tree (by index) or the tree being grown.
class WorldHit {
  WorldHit(this.rect, this.finishedIndex);
  final Rect rect;

  /// -1 for the tree being grown.
  final int finishedIndex;
}

class ForestWorld {
  ForestWorld({this.weather = ForestWeather.clear, this.reducedMotion = false});

  ForestWeather weather;
  bool reducedMotion;
  double get _motion => reducedMotion ? 0 : 1;

  // time
  double hour = 12, t = 0;
  SkyState sky = skyState(12, ForestWeather.clear);

  // camera: x in world units, zoom (1 = the whole scene), and the design-space y that stays still while zooming
  double camX = 0, camV = 0, zoom = 1, focusY = 470;
  double? camTargetX, zoomTarget, focusTarget;
  bool dragging = false;

  // what is shown
  List<FinishedTree> finished = const [];
  final List<Slot> slots = [];
  int species = 0;
  double dispS = 0, wet = 0, glow = 0, glowTarget = 0, bigGlow = 0, seedFade = 1;
  int hideFinished = -1;

  /// The watering can's progress 0..1 (-1: away) and whether it also showers the crown.
  double canK = -1;
  bool canShower = false;

  /// A finished tree walking back to its place: progress 0..1 (-1: none), which kind, and where it goes.
  double slideK = -1;
  int slideSpecies = 0;
  Slot? slideTo;

  /// Where things were drawn on the last frame, for tapping (design space).
  List<WorldHit> hits = const [];

  final _rnd = math.Random(11);
  final _rain = <_Rain>[], _snow = <_Snow>[], _splash = <_Splash>[], _drift = <_Drift>[], _drops = <_Drop>[], _sparks = <_Spark>[];
  double snowCover = 0, puddles = 0, flash = 0, _flashT = -1, _nextFlash = 8, _flashX = 190;

  // creatures
  final _birds = <_Bird>[];
  double _birdWait = 4, _batWait = 10;
  ({double x, double y, double v, double p})? _bat;
  final _butterflies = [
    _Butterfly(-70, 470, 1.3, const Color(0xFFFFF1A8)),
    _Butterfly(0, 484, 41.7, const Color(0xFFF6F2FF)),
    _Butterfly(70, 498, 77.1, const Color(0xFFBFE0FF)),
  ];
  late final List<_Firefly> _flies = () {
    final r = math.Random(5);
    return List.generate(22, (_) => _Firefly((r.nextDouble() - 0.5) * 700, 400 + r.nextDouble() * 150, r.nextDouble() * 100, 0.5 + r.nextDouble() * 0.5));
  }();

  // caches that depend on the light
  List<double> _light = const [255, 255, 255];
  final _treeImages = <int, ui.Image?>{};
  ui.Picture? _mainPic;
  double _mainStage = -1;
  int _mainSpecies = -1;

  void setFinished(List<FinishedTree> trees) {
    finished = trees;
    if (trees.isNotEmpty) slotOf(trees.length - 1);
  }

  Slot slotOf(int index) {
    while (slots.length <= index) {
      slots.add(forestSlot(slots));
    }
    return slots[math.max(0, index)];
  }

  // ---- camera ----
  (double, double) get camBounds {
    var lo = -60.0, hi = 60.0;
    for (final s in slots.take(finished.length)) {
      lo = math.min(lo, s.x - 80);
      hi = math.max(hi, s.x + 80);
    }
    return (lo, hi);
  }

  /// Eases the camera to look at a tree at world x [wx] and depth [z], zoomed to [zoomTo].
  void focusOnTree(double wx, double z, {double zoomTo = 1.9}) {
    camTargetX = wx;
    zoomTarget = zoomTo;
    focusTarget = depthY(z) - 70;
    camV = 0;
  }

  /// Eases back to the tree being grown, at the normal zoom.
  void goHome() {
    camTargetX = 0;
    zoomTarget = 1;
    focusTarget = 470;
    camV = 0;
  }

  bool get isAway => camX.abs() > 50 || zoom > 1.15;

  double _zf(double z) => math.pow(zoom, lerp(1.0, 0.55, z)).toDouble();

  Offset screenOf(double wx, double z) {
    final zf = _zf(z);
    return Offset(_cx + (wx - camX) * depthParallax(z) * zf, focusY + (depthY(z) - focusY) * zf);
  }

  // ---- stepping ----
  void update(double dt) {
    dt = math.min(0.05, dt);
    t += dt * _motion;
    final sk = sky = skyState(hour, weather);
    _updateCamera(dt);
    _updateParticles(dt, sk);
    _updateCreatures(dt, sk);
    glow += (glowTarget - glow) * math.min(1, dt * 1.2);
    if (sk.weather.flash > 0 && _motion > 0) {
      _nextFlash -= dt;
      if (_nextFlash <= 0) {
        _flashT = 0;
        _nextFlash = 16 + _rnd.nextDouble() * 18;
        _flashX = 40 + _rnd.nextDouble() * 300;
      }
    }
    if (_flashT >= 0) {
      _flashT += dt;
      flash = _flashT < 0.35 ? smooth(0, 0.35, _flashT) : 1 - smooth(0.35, 2.2, _flashT);
      if (_flashT > 2.2) _flashT = -1;
    } else {
      flash = 0;
    }
  }

  void _updateCamera(double dt) {
    if (!dragging && camTargetX == null) {
      camX += camV * dt;
      camV *= math.pow(0.04, dt).toDouble();
      final (lo, hi) = camBounds;
      if (camX < lo) camX += (lo - camX) * math.min(1, dt * 4);
      if (camX > hi) camX += (hi - camX) * math.min(1, dt * 4);
    }
    final ease = math.min(1.0, dt * (reducedMotion ? 20 : 2.6));
    if (camTargetX != null) {
      camX += (camTargetX! - camX) * ease;
      if ((camTargetX! - camX).abs() < 0.4) {
        camX = camTargetX!;
        camTargetX = null;
      }
    }
    if (zoomTarget != null) {
      zoom += (zoomTarget! - zoom) * ease;
      if ((zoomTarget! - zoom).abs() < 0.004) {
        zoom = zoomTarget!;
        zoomTarget = null;
      }
    }
    if (focusTarget != null) {
      focusY += (focusTarget! - focusY) * ease;
      if ((focusTarget! - focusY).abs() < 0.4) {
        focusY = focusTarget!;
        focusTarget = null;
      }
    }
  }

  void _updateParticles(double dt, SkyState sk) {
    final w = sk.weather, windX = (sk.wind - 0.25) * 60;
    final wantRain = _motion > 0 ? math.min(170, w.rain) : 0;
    while (_rain.length < wantRain) {
      _rain.add(_newRain(w.rain));
    }
    if (_rain.length > wantRain) _rain.length = wantRain;
    for (final d in _rain) {
      d.y += d.v * dt;
      d.x += windX * 0.8 * dt;
      if (d.y >= d.ty) {
        if (_splash.length < 40) _splash.add(_Splash(d.x, d.ty, 0));
        final n = _newRain(w.rain);
        d
          ..x = n.x
          ..v = n.v
          ..len = n.len
          ..ty = n.ty
          ..y = -20 - _rnd.nextDouble() * 40;
      }
    }
    for (final s in _splash) {
      s.t += dt;
    }
    _splash.removeWhere((s) => s.t >= 0.6);
    puddles = clamp01(puddles + (w.rain > 0 ? dt / 40 : -dt / 120));

    final wantSnow = _motion > 0 ? math.min(140, w.snow) : 0;
    while (_snow.length < wantSnow) {
      _snow.add(_newSnow());
    }
    if (_snow.length > wantSnow) _snow.length = wantSnow;
    for (final f in _snow) {
      f.y += f.v * dt;
      f.p += dt * 0.9;
      f.x += (math.sin(f.p) * 14 + windX * 0.6) * dt;
      if (f.y >= f.ty) {
        final n = _newSnow();
        f
          ..x = n.x
          ..v = n.v
          ..r = n.r
          ..p = n.p
          ..ty = n.ty
          ..y = -10;
      }
      if (f.x < -10) f.x += designW + 20;
      if (f.x > designW + 10) f.x -= designW + 20;
    }
    snowCover = clamp01(snowCover + (w.snow > 0 ? dt / 50 : -dt / 160));

    for (final p in _drift) {
      p.life += dt;
      if (p.y < p.ty) {
        p.vy = math.min(p.vy + 6 * dt, 26);
        p.x += (p.vx + windX + math.sin(p.life * 1.4 + p.ph) * 10) * dt;
        p.y += p.vy * dt;
        p.rot += p.vr * dt;
      }
    }
    _drift.removeWhere((p) => p.life >= p.max);

    for (final d in _drops) {
      d.vy += 260 * dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      if (d.y >= d.ty) {
        d.dead = true;
        wet = math.min(1, wet + 0.035);
        if (_splash.length < 40) _splash.add(_Splash(d.x, d.ty, 0.1, small: true));
      }
    }
    _drops.removeWhere((d) => d.dead);
    wet = math.max(0, wet - dt / 45);

    for (final s in _sparks) {
      s.life += dt;
      s.y -= s.v * dt;
      s.x += math.sin(s.life * 1.3 + s.ph) * 6 * dt;
    }
    _sparks.removeWhere((s) => s.life >= s.max);
  }

  _Rain _newRain(int base) => _Rain(
        _rnd.nextDouble() * (designW + 80) - 40,
        -20 - _rnd.nextDouble() * 300,
        330 + _rnd.nextDouble() * 120 + base,
        9 + _rnd.nextDouble() * 8,
        _horizon + 10 + math.pow(_rnd.nextDouble(), 0.7) * 300,
      );

  _Snow _newSnow() => _Snow(
        _rnd.nextDouble() * designW,
        -10 - _rnd.nextDouble() * 400,
        16 + _rnd.nextDouble() * 22,
        1 + _rnd.nextDouble() * 1.8,
        _rnd.nextDouble() * _tau,
        _horizon + 10 + _rnd.nextDouble() * 300,
      );

  void _spawnDrift(double x, double y, double ty, Color col, bool blossom) {
    if (_motion == 0 || _drift.length >= 26) return;
    _drift.add(_Drift(x, y, ty, (_rnd.nextDouble() - 0.5) * 8, 6 + _rnd.nextDouble() * 6, _rnd.nextDouble() * _tau, (_rnd.nextDouble() - 0.5) * 2.4, col, blossom, _rnd.nextDouble() * _tau, 9 + _rnd.nextDouble() * 5));
  }

  /// A burst of sparkles around (x, y) in design space.
  void sparkleBurst(double x, double y, int n, double spread) {
    for (var i = 0; i < n && _sparks.length < 46; i++) {
      final a = _rnd.nextDouble() * _tau, d = math.sqrt(_rnd.nextDouble()) * spread;
      _sparks.add(_Spark(x + math.cos(a) * d, y + math.sin(a) * d * 0.7, 6 + _rnd.nextDouble() * 12, -_rnd.nextDouble() * 1.2, 2.6 + _rnd.nextDouble() * 2, 1.2 + _rnd.nextDouble() * 1.8, _rnd.nextDouble() * _tau));
    }
  }

  bool _flying(SkyState sk) => sk.weather.rain == 0 && sk.weather.snow == 0;

  void _updateCreatures(double dt, SkyState sk) {
    for (final b in _birds) {
      b.x += b.v * dt;
      b.p += dt * b.f;
      b.y += math.sin(b.p * 0.13) * 3 * dt;
    }
    _birds.removeWhere((b) => b.x < -60 || b.x > designW + 60);
    _birdWait -= dt;
    if (_motion > 0 && _birdWait <= 0 && _birds.isEmpty && sk.day > 0.6 && _flying(sk)) {
      final dir = _rnd.nextBool() ? 1.0 : -1.0, y = 90 + _rnd.nextDouble() * 120, n = 2 + _rnd.nextInt(3);
      for (var i = 0; i < n; i++) {
        _birds.add(_Bird(dir > 0 ? -20.0 - i * 22 : designW + 20.0 + i * 22, y + (i % 2) * 10 + _rnd.nextDouble() * 6, dir * (22 + _rnd.nextDouble() * 6), _rnd.nextDouble() * 10, 4.2 + _rnd.nextDouble(), 0.8 + _rnd.nextDouble() * 0.4));
      }
      _birdWait = 18 + _rnd.nextDouble() * 24;
    }
    final butterfliesOn = sk.day > 0.7 && _flying(sk) && sk.wind < 0.9 && sk.cover < 0.9 && _motion > 0;
    for (final b in _butterflies) {
      b.p += dt;
      b.a = clamp01(b.a + (butterfliesOn ? dt : -dt) * 0.4);
    }
    final bat = _bat;
    if (bat != null) {
      final nx = bat.x + bat.v * dt;
      _bat = (x: nx, y: bat.y, v: bat.v, p: bat.p + dt * 7);
      if (nx < -40 || nx > designW + 40) _bat = null;
    }
    _batWait -= dt;
    if (_motion > 0 && _bat == null && _batWait <= 0 && sk.night > 0.7 && _flying(sk)) {
      final dir = _rnd.nextBool() ? 1.0 : -1.0;
      _bat = (x: dir > 0 ? -30.0 : designW + 30, y: 120 + _rnd.nextDouble() * 100, v: dir * 34, p: 0.0);
      _batWait = 30 + _rnd.nextDouble() * 30;
    }
    final on = sk.night > 0.35 && _flying(sk) ? 1.0 : 0.0;
    for (final f in _flies) {
      f.p += dt * _motion;
      f.a = clamp01(f.a + (on - f.a) * dt * 0.3);
    }
  }

  // ---- light-dependent caches ----
  List<double> _quantised(Rgb l) => [for (final v in l) (v / 6).round() * 6.0];

  ui.Image? _treeImage(int sp) {
    if (_treeImages.containsKey(sp)) return _treeImages[sp];
    ui.Image? image;
    try {
      const pad = 26.0, res = 2.0;
      final spec = treeSpecies[sp];
      final w = spec.width + pad * 2, h = spec.height + pad * 2 + 10;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(res, res);
      canvas.translate(w / 2, h - pad);
      paintTree(canvas, geometryFor(sp), spec, 7, light: _light);
      image = recorder.endRecording().toImageSync((w * res).ceil(), (h * res).ceil());
    } catch (_) {
      image = null;
    }
    return _treeImages[sp] = image;
  }

  void _stamp(ui.Canvas c, int sp, double x, double y, double sc, double shear) {
    final spec = treeSpecies[sp];
    c.save();
    c.translate(x, y);
    c.transform(_shear(shear));
    c.scale(sc, sc);
    final image = _treeImage(sp);
    if (image == null) {
      paintTree(c, geometryFor(sp), spec, 7, light: _light);
    } else {
      const pad = 26.0;
      final w = spec.width + pad * 2, h = spec.height + pad * 2 + 10;
      c.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Rect.fromLTWH(-w / 2, -(h - pad), w, h), ui.Paint()..filterQuality = ui.FilterQuality.medium);
    }
    c.restore();
  }

  double _treeSway(double phase) {
    final amp = 0.010 + sky.wind * 0.030;
    final gust = 0.6 + 0.4 * math.sin(t * 0.23 + phase * 0.3);
    return (math.sin(t * 0.75 + phase) * amp * gust + sky.wind * amp * 0.6) * _motion;
  }

  void _shadow(ui.Canvas c, double x, double y, double halfW, double scale) {
    final dayA = 1 - sky.night * 0.7;
    c.drawOval(Rect.fromCenter(center: Offset(x, y + 2), width: 2 * math.max(10, halfW * 0.5 * scale), height: 12 * scale), ui.Paint()..color = Color.fromRGBO(20, 30, 15, 0.16 * dayA));
    if (sky.shadow > 0.3 && sky.sun.a > 0.05) {
      final dir = x > sky.sun.x ? 1.0 : -1.0, len = sky.shadow * 46 * scale + halfW * 0.25 * scale;
      c.drawOval(Rect.fromCenter(center: Offset(x + dir * len * 0.7, y + 3), width: 2 * (len + halfW * 0.3 * scale), height: 14 * scale), ui.Paint()..color = Color.fromRGBO(30, 25, 40, 0.1 * clamp01(sky.shadow / 2) * sky.sun.a));
    }
  }

  /// The converter between the screen and the design space the scene is drawn in.
  (double scale, double dy) fit(Size size) {
    final scale = size.width / designW;
    return (scale, (size.height / scale - designH) / 2);
  }

  // ---- drawing ----
  /// Paints the scene into [canvas] for a screen of [size]: the design space is scaled to the width and centred
  /// vertically, with the sky and ground extended to fill the rest.
  void paint(ui.Canvas canvas, Size size) {
    final (scale, dy) = fit(size);
    final sk = sky;
    final newLight = _quantised(sk.treeLight);
    if (newLight[0] != _light[0] || newLight[1] != _light[1] || newLight[2] != _light[2]) {
      _light = newLight;
      for (final i in _treeImages.values) {
        i?.dispose();
      }
      _treeImages.clear();
      _mainPic = null;
      _mainStage = -1;
    }

    canvas.save();
    canvas.scale(scale, scale);
    canvas.translate(0, dy);
    final top = -dy - 10, bottom = designH + dy + 10;
    final t = this.t;

    _drawSky(canvas, sk, top);
    if (flash > 0) {
      canvas.drawCircle(Offset(_flashX, 300), 260, ui.Paint()..shader = ui.Gradient.radial(Offset(_flashX, 300), 260, [Color.fromRGBO(235, 235, 255, 0.28 * flash), const Color(0x00EBEBFF)]));
    }
    _drawClouds(canvas, sk, t);
    _drawBirds(canvas, sk);
    _drawBat(canvas);
    _drawHills(canvas, sk);
    _drawGround(canvas, sk, bottom);

    // trees far to near, with grass layered between depths
    final items = <({double z, void Function() draw})>[];
    final newHits = <WorldHit>[];
    for (var i = 0; i < finished.length; i++) {
      if (i == hideFinished) continue;
      final tr = finished[i], slot = slotOf(i), sp = treeSpecies[tr.species];
      final p = screenOf(slot.x, slot.z), sc = depthScale(slot.z) * _zf(slot.z);
      if (p.dx + sp.width * 0.5 * sc < -30 || p.dx - sp.width * 0.5 * sc > designW + 30) continue;
      final index = i;
      items.add((
        z: slot.z,
        draw: () {
          final geo = geometryFor(tr.species);
          _shadow(canvas, p.dx, p.dy, geo.halfW, sc);
          _stamp(canvas, tr.species, p.dx, p.dy, sc, _treeSway(index * 7.0 + 3));
          newHits.add(WorldHit(Rect.fromLTRB(p.dx - sp.width * sc * 0.42, p.dy - sp.height * sc, p.dx + sp.width * sc * 0.42, p.dy + 10 * sc), index));
          if (_motion > 0 && (sp.touch == 'blossom' || sp.touch == 'autumn' || sk.wind > 0.8) && _rnd.nextDouble() < 0.016 * (sp.touch == 'blossom' || sp.touch == 'autumn' ? 0.5 : 0.2) * (0.5 + sk.wind)) {
            final cl = geo.clumps.isEmpty ? null : geo.clumps[_rnd.nextInt(geo.clumps.length)];
            if (cl != null) {
              final col = sp.touch == 'blossom'
                  ? const Color(0xFFF7C3D2)
                  : sp.touch == 'autumn'
                      ? const [Color(0xFFD9542B), Color(0xFFF08A2E), Color(0xFFF2B13C)][0]
                      : _col(rgbFromHex(sp.leaf[1]));
              _spawnDrift(p.dx + cl.x * sc, p.dy + cl.y * sc, p.dy + 4 + _rnd.nextDouble() * 10, col, sp.touch == 'blossom');
            }
          }
        },
      ));
    }
    if (slideK >= 0 && slideTo != null) {
      final k = _easeInOut(slideK), to = slideTo!;
      final z = lerp(mainZ, to.z, k), x = lerp(0, to.x, k);
      final p = screenOf(x, z), sc = lerp(1, depthScale(to.z), k) * _zf(z);
      items.add((
        z: z,
        draw: () {
          _shadow(canvas, p.dx, p.dy, geometryFor(slideSpecies).halfW, sc);
          _stamp(canvas, slideSpecies, p.dx, p.dy, sc, _treeSway(3));
        },
      ));
    }
    final mainSp = treeSpecies[species];
    final mp = screenOf(0, mainZ), mz = _zf(mainZ);
    if (slideK < 0 || seedFade > 0) {
      items.add((
        z: mainZ,
        draw: () {
          canvas.save();
          canvas.translate(mp.dx, mp.dy);
          canvas.scale(1.3 * mz, 1.3 * mz);
          paintSoil(canvas, dispS, wet, light: _light);
          canvas.restore();
          final rv = revealAt(dispS), geo = geometryFor(species);
          if (dispS > 3) _shadow(canvas, mp.dx, mp.dy, geo.halfW * rv.sc, mz);
          _refreshMain();
          final pic = _mainPic;
          if (pic != null) {
            final fading = seedFade < 1;
            canvas.save();
            if (fading) canvas.saveLayer(null, ui.Paint()..color = Color.fromRGBO(255, 255, 255, clamp01(seedFade)));
            canvas.translate(mp.dx, mp.dy);
            canvas.scale(mz, mz);
            canvas.transform(_shear(_treeSway(1) * smooth(1, 5, dispS)));
            canvas.drawPicture(pic);
            if (fading) canvas.restore();
            canvas.restore();
          }
          final grown = clamp01(dispS / 6);
          final ht = math.max(50.0, geo.height * rv.sc * mz * math.max(grown, 0.25)), wd = math.max(60.0, geo.halfW * 2 * rv.sc * mz * 0.9);
          newHits.add(WorldHit(Rect.fromLTRB(mp.dx - wd / 2, mp.dy - ht - 8, mp.dx + wd / 2, mp.dy + 14 * mz), -1));
          if (_motion > 0 && dispS > 6.5 && (mainSp.touch == 'blossom' || mainSp.touch == 'autumn') && _rnd.nextDouble() < 0.01) {
            final cl = geo.clumps.isEmpty ? null : geo.clumps[_rnd.nextInt(geo.clumps.length)];
            if (cl != null) {
              _spawnDrift(mp.dx + cl.x * mz, mp.dy + cl.y * mz, mp.dy + 8 + _rnd.nextDouble() * 30, mainSp.touch == 'blossom' ? const Color(0xFFF7C3D2) : const Color(0xFFE9772C), mainSp.touch == 'blossom');
            }
          }
        },
      ));
    }
    items.sort((a, b) => b.z.compareTo(a.z));
    final tufts = _tufts();
    var zPrev = 1.01;
    for (final it in items) {
      _drawGrass(canvas, sk, t, tufts, it.z, zPrev);
      zPrev = it.z;
      it.draw();
    }
    _drawGrass(canvas, sk, t, tufts, -1, zPrev);
    hits = newHits;
    _drawButterflies(canvas);

    // the watering can and its drops
    if (canK >= 0 && canK < 1) {
      final k = canK;
      final tilt = -0.55 * smooth(0.1, 0.3, k) * (1 - smooth(0.78, 0.95, k)), a = smooth(0, 0.12, k) * (1 - smooth(0.88, 1, k));
      final cxp = mp.dx + 46 * mz, cyp = mp.dy - 78 * mz;
      canvas.save();
      canvas.translate(cxp, cyp);
      canvas.scale(mz, mz);
      canvas.rotate(tilt);
      paintWateringCan(canvas, alpha: a);
      canvas.restore();
      if (tilt < -0.4 && _motion > 0) {
        for (var i = 0; i < 2; i++) {
          final sx = cxp + (math.cos(tilt) * -31 - math.sin(tilt) * -12.5) * mz, sy = cyp + (math.sin(tilt) * -31 + math.cos(tilt) * -12.5) * mz;
          _drops.add(_Drop(sx + (_rnd.nextDouble() - 0.5) * 3, sy, -30 - _rnd.nextDouble() * 22, 10 + _rnd.nextDouble() * 20, mp.dy - 2 + _rnd.nextDouble() * 6));
        }
      }
      if (canShower && _motion > 0 && _rnd.nextDouble() < 0.5) {
        final geo = geometryFor(species), rv = revealAt(dispS), hw = geo.halfW * rv.sc * 0.8 * mz, topY = mp.dy - geo.height * rv.sc * mz - 20;
        _drops.add(_Drop(mp.dx + (_rnd.nextDouble() - 0.5) * 2 * hw, topY, 0, 40, mp.dy - 4 + _rnd.nextDouble() * 10, faint: true));
      }
    }
    for (final d in _drops) {
      canvas.drawLine(
        Offset(d.x, d.y),
        Offset(d.x - d.vx * 0.012, d.y - d.vy * 0.02),
        ui.Paint()
          ..color = d.faint ? const Color(0x80BEE1F5) : const Color(0xE6AAD7F0)
          ..strokeWidth = d.faint ? 1.2 : 1.8
          ..strokeCap = ui.StrokeCap.round,
      );
    }

    for (final p in _drift) {
      final a = 1 - smooth(p.max - 2, p.max, p.life);
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rot);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: (p.blossom ? 2.4 : 3.2) * 2, height: (p.blossom ? 1.6 : 2.0) * 2), ui.Paint()..color = p.col.withValues(alpha: a));
      canvas.restore();
    }
    _drawWeather(canvas, sk, t);
    _drawLight(canvas, sk, top, bottom, t);
    canvas.restore();
  }

  void _refreshMain() {
    if (_mainPic != null && (_mainStage - dispS).abs() < 0.002 && _mainSpecies == species) return;
    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    paintTree(c, geometryFor(species), treeSpecies[species], dispS, light: _light);
    _mainPic = recorder.endRecording();
    _mainStage = dispS;
    _mainSpecies = species;
  }

  void _drawSky(ui.Canvas c, SkyState sk, double top) {
    c.drawRect(
      Rect.fromLTRB(-10, top, designW + 10, _horizon + 30),
      ui.Paint()..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, _horizon), [_col(sk.skyTop), _col(sk.skyMid), _col(sk.skyBot)], [0, 0.6, 1]),
    );
    if (top < 0) c.drawRect(Rect.fromLTRB(-10, top, designW + 10, 0), ui.Paint()..color = _col(sk.skyTop));
    final s = sk.sun;
    if (s.a > 0.01 && s.y < _horizon) {
      final col = mixRgb([255, 244, 200], [255, 160, 90], s.warm);
      final r = 70 + s.warm * 70;
      c.drawCircle(Offset(s.x, s.y), r, ui.Paint()..shader = ui.Gradient.radial(Offset(s.x, s.y), r, [_col(col, 0.6 * s.a), _col(col, 0)]));
      c.drawCircle(Offset(s.x, s.y), 17, ui.Paint()..color = _col(mixRgb([255, 250, 225], [255, 190, 120], s.warm), s.a));
    }
  }

  void _drawClouds(ui.Canvas c, SkyState sk, double t) {
    final base = sk.cloudCol;
    final cz = 1 + (zoom - 1) * 0.08;
    for (final cl in _scenery.$2) {
      final vis = smooth(cl.rank - 0.05, cl.rank + 0.1, sk.cover);
      if (vis <= 0.01) continue;
      final speed = (4 + cl.depth * 6) * (0.4 + sk.wind * 1.6) * _motion;
      const span = designW + 360;
      final x = ((cl.x0 + t * speed - camX * (0.04 + cl.depth * 0.08)) % span + span) % span - 180;
      final s = cl.s * (1 + sk.cover * 0.35) * cz, a = vis * (0.55 + 0.35 * sk.cover);
      final shadow = ui.Paint()..color = _col(shadeRgb(base, -0.12 - sk.weather.grey * 0.15), a);
      for (final p in cl.puffs) {
        c.drawCircle(Offset(x + p.dx * s, cl.y + p.dy * s + 4 * s), p.r * s, shadow);
      }
      final light = ui.Paint()..color = _col(shadeRgb(base, 0.08 * (1 - sk.night)), a);
      for (final p in cl.puffs) {
        c.drawCircle(Offset(x + p.dx * s - 2, cl.y + p.dy * s - 1), p.r * s * 0.85, light);
      }
    }
    if (sk.cover > 0.75) {
      final a = smooth(0.75, 1, sk.cover) * 0.5;
      c.drawRect(const Rect.fromLTWH(-10, 0, designW + 20, 260), ui.Paint()..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, 260), [_col(shadeRgb(base, -0.15), a), _col(base, 0)]));
    }
  }

  void _drawBirds(ui.Canvas c, SkyState sk) {
    if (_birds.isEmpty) return;
    final paint = ui.Paint()
      ..color = _col(mixRgb([60, 62, 70], [30, 32, 44], sk.night), 0.75)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = ui.StrokeCap.round;
    for (final b in _birds) {
      final wing = math.sin(b.p) * 4 * b.s, w = 6 * b.s;
      final path = ui.Path()
        ..moveTo(b.x - w, b.y - wing)
        ..quadraticBezierTo(b.x - w * 0.4, b.y - 1 - wing * 0.3, b.x, b.y)
        ..quadraticBezierTo(b.x + w * 0.4, b.y - 1 - wing * 0.3, b.x + w, b.y - wing);
      c.drawPath(path, paint);
    }
  }

  void _drawBat(ui.Canvas c) {
    final b = _bat;
    if (b == null) return;
    final y = b.y + math.sin(b.p * 0.35) * 10, f = math.sin(b.p) * 3;
    final path = ui.Path()
      ..moveTo(b.x, y)
      ..quadraticBezierTo(b.x - 5, y - 4 - f, b.x - 10, y - 1 - f)
      ..quadraticBezierTo(b.x - 6, y + 1, b.x - 4, y + 3)
      ..quadraticBezierTo(b.x, y + 1, b.x + 4, y + 3)
      ..quadraticBezierTo(b.x + 6, y + 1, b.x + 10, y - 1 - f)
      ..quadraticBezierTo(b.x + 5, y - 4 - f, b.x, y)
      ..close();
    c.drawPath(path, ui.Paint()..color = const Color(0xFF121423));
  }

  double _farY(double y) => focusY + (y - focusY) * _zf(1);

  void _drawHills(ui.Canvas c, SkyState sk) {
    final snowy = snowCover * 0.7;
    final yh = _farY(_horizon), shift = yh - _horizon;
    for (final h in _hills) {
      final base = switch (h.key) { 'far' => sk.hillFar, 'mid' => sk.hillMid, _ => sk.hillNear };
      final col = mixRgb(base, [236, 240, 244], snowy * (h.key == 'far' ? 0.8 : 1) * (1 - sk.night * 0.6));
      final path = ui.Path()..moveTo(-10, _horizon + 400 + shift);
      for (var x = -10.0; x <= designW + 10; x += 8) {
        path.lineTo(x, h.y(x + camX * h.pf) + shift);
      }
      path.lineTo(designW + 10, _horizon + 400 + shift);
      path.close();
      c.drawPath(path, ui.Paint()..color = _col(col));
      if (h.trees) {
        final dark = ui.Paint()..color = _col(shadeRgb(col, -0.14));
        final pf = h.pf, step = h.key == 'near' ? 19.0 : 13.0, x0 = ((camX * pf - 20) / step).floor();
        for (var i = x0; i < x0 + designW / step + 3; i++) {
          final r = mulberry32(i * 31 + (h.key == 'near' ? 7 : 3));
          if (r() < 0.45) continue;
          final wx = i * step + r() * step, x = wx - camX * pf, y = h.y(wx) + 2 + shift, sz = (h.key == 'near' ? 6 : 4) * (0.7 + r() * 0.6);
          if (r() < 0.5) {
            c.drawOval(Rect.fromCenter(center: Offset(x, y - sz), width: sz * 1.5, height: sz * 2), dark);
          } else {
            c.drawPath(ui.Path()
              ..moveTo(x - sz * 0.6, y)
              ..lineTo(x, y - sz * 2.3)
              ..lineTo(x + sz * 0.6, y), dark);
          }
        }
      }
    }
  }

  void _drawGround(ui.Canvas c, SkyState sk, double bottom) {
    final snowy = snowCover * 0.75 * (1 - sk.night * 0.5);
    final topC = mixRgb(sk.groundTop, [238, 242, 246], snowy), botC = mixRgb(sk.groundBot, [214, 222, 230], snowy);
    final yh = _farY(_horizon);
    c.drawPath(
      ui.Path()
        ..moveTo(-10, bottom)
        ..lineTo(-10, yh + 4)
        ..quadraticBezierTo(designW / 2, yh + 2 + math.sin((camX * 0.6) * 0.012) * 3, designW + 10, yh + 4)
        ..lineTo(designW + 10, bottom)
        ..close(),
      ui.Paint()..shader = ui.Gradient.linear(Offset(0, yh), const Offset(0, designH), [_col(topC), _col(botC)]),
    );
    if (bottom > designH) c.drawRect(Rect.fromLTRB(-10, designH - 1, designW + 10, bottom), ui.Paint()..color = _col(botC));
    if (puddles > 0.02) {
      final paint = ui.Paint()..color = _col(mixRgb(sk.skyMid, [120, 140, 160], 0.4), 0.35 * puddles);
      for (final p in const [[-120.0, 590.0, 34.0], [95.0, 612.0, 26.0], [260.0, 575.0, 30.0], [-300.0, 600.0, 28.0], [430.0, 620.0, 36.0]]) {
        final x = _cx + p[0] - camX;
        if (x < -60 || x > designW + 60) continue;
        c.drawOval(Rect.fromCenter(center: Offset(x, p[1]), width: 2 * p[2] * puddles, height: 10 * puddles), paint);
      }
    }
  }

  List<_Tuft> _tufts() {
    const cell = 34.0;
    final i0 = ((camX - _cx - 40) / cell).floor(), i1 = ((camX + _cx + 40) / cell).ceil();
    final out = <_Tuft>[];
    for (var i = i0; i <= i1; i++) {
      final r = mulberry32(i * 7349 + 11);
      for (var k = 0; k < 3; k++) {
        final z = r() * 0.95, wx = i * cell + r() * cell, fl = r(), side = r();
        out.add(_Tuft(z, wx, fl, side));
      }
    }
    return out;
  }

  void _drawGrass(ui.Canvas c, SkyState sk, double t, List<_Tuft> tufts, double zMin, double zMax) {
    final sway = (0.010 + sk.wind * 0.030) * 60 * _motion;
    final dark = ui.Paint()
      ..color = _col(shadeRgb(sk.groundBot, -0.2), 0.8)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = ui.StrokeCap.round;
    final light = ui.Paint()
      ..color = _col(shadeRgb(sk.groundTop, 0.12 * (1 - sk.night)), 0.8)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = ui.StrokeCap.round;
    for (final tf in tufts) {
      if (tf.z < zMin || tf.z >= zMax) continue;
      final p = screenOf(tf.wx, tf.z), zf = _zf(tf.z), s = lerp(1.3, 0.45, tf.z) * zf;
      final x = p.dx, y = p.dy + 6 * zf;
      if (x < -10 || x > designW + 10) continue;
      final sw = math.sin(t * 0.9 + tf.wx * 0.05) * sway * s;
      final path = ui.Path();
      for (final b in const [[-3.0, 7.0], [0.0, 10.0], [3.0, 8.0], [5.0, 5.0]]) {
        path.moveTo(x + b[0] * s, y);
        path.quadraticBezierTo(x + b[0] * s, y - b[1] * s * 0.6, x + b[0] * s * 1.3 + sw, y - b[1] * s);
      }
      c.drawPath(path, tf.side < 0.5 ? dark : light);
      if (tf.fl < 0.16 && snowCover < 0.5) {
        const cols = [Color(0xFFFFF6E8), Color(0xFFFFD9E6), Color(0xFFFFE58A), Color(0xFFD9C6FF)];
        c.drawCircle(Offset(x + 1 * s + sw, y - 10 * s), 1.8 * s, ui.Paint()..color = cols[(tf.fl * 25).floor() % 4].withValues(alpha: 1 - sk.night * 0.5));
      }
    }
  }

  void _drawButterflies(ui.Canvas c) {
    for (final b in _butterflies) {
      if (b.a <= 0.01) continue;
      final zf = _zf(0.3);
      final x = _cx + (b.ax - camX) * zf + math.sin(b.p * 0.31) * 60 + math.sin(b.p * 0.83) * 14;
      final y = focusY + (b.ay + math.sin(b.p * 0.47) * 26 + math.cos(b.p * 1.1) * 6 - focusY) * zf;
      final flap = 0.35 + 0.65 * math.sin(b.p * 7).abs();
      final paint = ui.Paint()..color = b.col.withValues(alpha: b.a * 0.9);
      for (final s in const [-1.0, 1.0]) {
        c.save();
        c.translate(x + s * 3 * flap, y - 1);
        c.rotate(s * 0.5);
        c.drawOval(Rect.fromCenter(center: Offset.zero, width: 6.8 * flap, height: 5.2), paint);
        c.restore();
        c.save();
        c.translate(x + s * 2.4 * flap, y + 2);
        c.rotate(s * 0.3);
        c.drawOval(Rect.fromCenter(center: Offset.zero, width: 4.4 * flap, height: 3.6), paint);
        c.restore();
      }
      c.drawRect(Rect.fromLTWH(x - 0.5, y - 2.5, 1, 5), ui.Paint()..color = const Color(0xFF4A3C30).withValues(alpha: b.a));
    }
  }

  void _drawWeather(ui.Canvas c, SkyState sk, double t) {
    if (_rain.isNotEmpty) {
      final path = ui.Path();
      final slant = (sk.wind - 0.25) * 0.15;
      for (final d in _rain) {
        path.moveTo(d.x, d.y);
        path.lineTo(d.x - slant * d.len * 3, d.y - d.len);
      }
      c.drawPath(
        path,
        ui.Paint()
          ..color = _col(mixRgb([215, 228, 240], [140, 160, 190], sk.night), 0.6)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    for (final s in _splash) {
      final k = s.t / 0.6;
      c.drawOval(
        Rect.fromCenter(center: Offset(s.x, s.y), width: 2 * (1 + k * (s.small ? 4 : 6)), height: 2 * (0.5 + k * (s.small ? 1.2 : 1.8))),
        ui.Paint()
          ..color = Color.fromRGBO(215, 230, 240, 0.5 * (1 - k))
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }
    if (_snow.isNotEmpty) {
      final p = ui.Paint()..color = const Color(0xE6FFFFFF);
      for (final f in _snow) {
        c.drawCircle(Offset(f.x, f.y), f.r, p);
      }
    }
    if (sk.fog > 0.02) {
      final fc = mixRgb([226, 230, 234], [60, 70, 90], sk.night);
      c.drawRect(
        const Rect.fromLTWH(-10, 200, designW + 20, designH - 200),
        ui.Paint()..shader = ui.Gradient.linear(const Offset(0, 200), const Offset(0, designH), [_col(fc, 0.15 * sk.fog), _col(fc, 0.72 * sk.fog), _col(fc, 0.22 * sk.fog)], [0, 0.28, 1]),
      );
      for (var i = 0; i < 5; i++) {
        const span = designW + 400;
        final x = ((i * 190 + t * (5 + i * 2) - camX * (0.3 + i * 0.12)) % span + span) % span - 200, y = 380.0 + i * 45;
        c.save();
        c.translate(x, y);
        c.scale(1, 0.28);
        c.drawCircle(Offset.zero, 200, ui.Paint()..shader = ui.Gradient.radial(Offset.zero, 200, [_col(fc, 0.6 * sk.fog), _col(fc, 0)]));
        c.restore();
      }
    }
  }

  void _drawLight(ui.Canvas c, SkyState sk, double top, double bottom, double t) {
    final wash = Rect.fromLTRB(-10, top, designW + 10, bottom);
    if (sk.tintA > 0.005) c.drawRect(wash, ui.Paint()..color = _col(sk.tint, sk.tintA));
    c.drawRect(wash, ui.Paint()..shader = ui.Gradient.radial(const Offset(_cx, 380), 520, [const Color(0x000A0F1E), Color.fromRGBO(10, 15, 30, 0.22 + sk.night * 0.2)], [220 / 520, 1]));

    if (sk.stars > 0.02) {
      final p = ui.Paint();
      for (final s in _scenery.$1) {
        final a = sk.stars * (0.55 + 0.45 * math.sin(t * 0.5 + s.p)) * (1 - s.y / 330);
        p.color = Color.fromRGBO(255, 255, 240, clamp01(a));
        c.drawCircle(Offset(s.x, s.y), s.r, p);
      }
    }
    final m = sk.moon;
    if (m.a > 0.01 && m.y < 300) {
      c.drawCircle(Offset(m.x, m.y), 80, ui.Paint()..shader = ui.Gradient.radial(Offset(m.x, m.y), 80, [Color.fromRGBO(220, 225, 255, 0.3 * m.a), const Color(0x00DCE1FF)]));
      c.drawCircle(Offset(m.x, m.y), 12, ui.Paint()..color = Color.fromRGBO(246, 242, 222, m.a));
      final crater = ui.Paint()..color = Color.fromRGBO(200, 196, 180, 0.5 * m.a);
      for (final d in const [[-3.0, -2.0, 2.6], [4.0, 3.0, 1.8], [2.0, -5.0, 1.2]]) {
        c.drawCircle(Offset(m.x + d[0], m.y + d[1]), d[2], crater);
      }
    }
    for (final f in _flies) {
      if (f.a < 0.02) continue;
      final x = _cx + (f.wx - camX * 0.9) + math.sin(f.p * 0.21 * f.f) * 30, y = f.y + math.sin(f.p * 0.33 * f.f) * 18;
      if (x < -20 || x > designW + 20) continue;
      final a = f.a * (0.35 + 0.65 * (0.5 + 0.5 * math.sin(f.p * 0.9 + f.wx)));
      c.drawCircle(Offset(x, y), 9, ui.Paint()..shader = ui.Gradient.radial(Offset(x, y), 9, [Color.fromRGBO(250, 255, 180, 0.9 * a), Color.fromRGBO(220, 255, 140, 0.45 * a), const Color(0x00C8FF78)], [0, 0.25, 1]));
    }
    if (glow > 0.01) {
      final geo = geometryFor(species), rv = revealAt(dispS), mp = screenOf(0, mainZ), mz = _zf(mainZ);
      final cy = mp.dy - math.max(30.0, geo.height * rv.sc * 0.55) * mz, r = (90 + 120 * rv.sc + bigGlow * 60) * mz;
      c.drawCircle(Offset(mp.dx, cy), r, ui.Paint()..shader = ui.Gradient.radial(Offset(mp.dx, cy), r, [Color.fromRGBO(255, 240, 190, 0.42 * glow), const Color(0x00FFF0BE)]));
    }
    for (final s in _sparks) {
      if (s.life < 0) continue;
      final a = math.sin(math.pi * clamp01(s.life / s.max)), r = s.r * 4;
      c.drawCircle(Offset(s.x, s.y), r, ui.Paint()..shader = ui.Gradient.radial(Offset(s.x, s.y), r, [Color.fromRGBO(255, 250, 215, 0.95 * a), Color.fromRGBO(255, 225, 150, 0.4 * a), const Color(0x00FFE196)], [0, 0.3, 1]));
    }
  }

  /// Where the crown of the tree being grown is in design space, for the sparkles.
  Offset crownPoint() {
    final geo = geometryFor(species), rv = revealAt(dispS), mp = screenOf(0, mainZ), mz = _zf(mainZ);
    return Offset(mp.dx, mp.dy - (dispS < 3 ? 20 : geo.height * rv.sc * 0.6) * mz);
  }

  double get crownRadius {
    final geo = geometryFor(species), rv = revealAt(dispS);
    return (dispS < 3 ? 26 : geo.halfW * rv.sc * 0.8) * _zf(mainZ);
  }

  /// The tap at design-space point [p]: the tree under it, if any (the one drawn last, in front, wins).
  WorldHit? hitTest(Offset p) {
    for (final h in hits.reversed) {
      if (h.rect.contains(p)) return h;
    }
    return null;
  }

  void dispose() {
    for (final i in _treeImages.values) {
      i?.dispose();
    }
    _treeImages.clear();
  }
}
