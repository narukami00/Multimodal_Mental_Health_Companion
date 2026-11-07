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
  _Puff(this.x, this.y, this.rx, this.ry);
  final double x, y, rx, ry;
}

class _Cloud {
  _Cloud(this.x0, this.y, this.s, this.low, this.puffs, this.rank);
  final double x0, y, s, rank;
  final bool low;
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
  const positions = [85.0, 245.0, 378.0, 5.0, 530.0, 655.0, 95.0, 247.0, 360.0, 465.0, 580.0, 12.0];
  final clouds = List.generate(12, (i) {
    final rnd = mulberry32(212 + i * 593), low = i >= 6;
    final puffs = List.generate(12, (j) {
      final swell = math.sin(j / 11 * math.pi);
      return _Puff(25 + j * 14.0, 52 - swell * (6 + rnd() * 16), 12 + rnd() * 20, 5 + swell * (6 + rnd() * 16));
    });
    return _Cloud(positions[i], low ? 218 + rnd() * 84 : 66 + rnd() * 128, low ? 0.63 + rnd() * 0.32 : 0.85 + rnd() * 0.5, low, puffs, i / 12);
  });
  clouds.sort((a, b) => (b.low ? 1 : 0).compareTo(a.low ? 1 : 0));
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
  WorldHit(this.rect, this.finishedIndex, {required this.base, required this.scale, this.shear = 0});
  final Rect rect;
  final Offset base;
  final double scale, shear;

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
  double camX = 0, camV = 0, zoom = 1, lift = 0;
  double? camTargetX;
  ({double x, double zoom, double lift})? _from, _destination;
  double _flightTime = 0;
  bool dragging = false;
  int? focusedTree;
  bool get isFlying => _destination != null;
  final _blockers = <int>{};
  final _treeAlpha = <int, double>{};
  final _treeOutlines = <int, ui.Path>{};
  final _pins = <({Rect bounds, WorldHit tree})>[];
  final _pinLabels = <int, ui.Paragraph>{};

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
  List<double> _sceneLight = const [255, 255, 255];
  final _treeImages = <int, ui.Image?>{};
  final _cloudImages = <_Cloud, ui.Image>{};
  ({Color soft, Color shadow, Color rim})? _cloudPalette;
  final _stampPaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
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

  /// Fits the tree inside the clear space to the left of the activity panel.
  void focusOnTree(int index, Size size, double panelLeft) {
    final slot = index < 0 ? const Slot(0, mainZ) : slotOf(index);
    final (scale, dy) = fit(size);
    final (halfW, height, treeScale) = _treeMetrics(index);
    final lane = panelLeft / scale;
    final x = lane / 2;
    final factor = math.min((x - 14) / (halfW * treeScale), (size.height / scale * 0.41) / (height * treeScale));
    final targetZoom = (1 + (factor - 1) / (1 - 0.48 * slot.z)).clamp(0.55, 4.0);
    final zf = _zf(slot.z, targetZoom);
    final ground = size.height / scale * 0.48 - dy + height * treeScale * zf * 0.42;
    focusedTree = index;
    _blockers.clear();
    _flyTo(slot.x - (x - _cx) / (depthParallax(slot.z) * zf), targetZoom, ground - _projectY(depthY(slot.z), slot.z, targetZoom, 0));
  }

  /// Eases back to the tree being grown, at the normal zoom.
  void goHome() {
    clearFocus();
    _flyTo(0, 1, 0);
  }

  void clearFocus() {
    focusedTree = null;
    _blockers.clear();
  }

  void beginGesture() {
    clearFocus();
    _destination = null;
    dragging = true;
    camTargetX = null;
    camV = 0;
  }

  void endGesture(double velocity) {
    dragging = false;
    camV = reducedMotion ? 0 : velocity;
    if (zoom < 1) _flyTo(camX, 1, 0);
  }

  void _flyTo(double x, double z, double y) {
    _from = (x: camX, zoom: zoom, lift: lift);
    _destination = (x: x, zoom: z, lift: y);
    _flightTime = 0;
    camTargetX = null;
    camV = 0;
  }

  bool get isAway => focusedTree != null || camX.abs() > 40 || (zoom - 1).abs() > 0.08 || lift.abs() > 8;

  double _zf(double z, [double? atZoom]) => 1 + ((atZoom ?? zoom) - 1) * (1 - 0.48 * clamp01(z));
  double _projectY(double y, double z, [double? atZoom, double? atLift]) => 455 + (y - 455) * _zf(z, atZoom) + (atLift ?? lift);

  Offset screenOf(double wx, double z) {
    final zf = _zf(z);
    return Offset(_cx + (wx - camX) * depthParallax(z) * zf, _projectY(depthY(z), z));
  }

  (double, double, double) _treeMetrics(int index) {
    final geo = geometryFor(index < 0 ? species : finished[index].species);
    if (index >= 0) return (geo.halfW + 12, geo.height + 10, depthScale(slotOf(index).z));
    final rv = revealAt(dispS);
    final youngHeight = lerp(19, 79, clamp01((dispS - 1) / 2));
    return (math.max(28, (geo.halfW + 12) * rv.sc), math.max(youngHeight, (geo.height + 10) * rv.sc), 1);
  }

  WorldHit _treeHit(int index, Offset base, double z, double shear) {
    final (w, h, scale) = _treeMetrics(index);
    final sc = scale * _zf(z);
    return WorldHit(Rect.fromLTRB(base.dx - w * sc, base.dy - h * sc, base.dx + w * sc, base.dy + 10 * sc), index,
        base: base, scale: sc, shear: shear);
  }

  double _alphaFor(WorldHit tree, double z, Rect? focus, double focusDepth) {
    final index = tree.finishedIndex;
    if (focus != null && z < focusDepth && tree.rect.overlaps(focus)) _blockers.add(index);
    final a = lerp(_treeAlpha[index] ?? 1, _blockers.contains(index) ? 0.12 : 1, _fadeStep);
    if (a > 0.998) {
      _treeAlpha.remove(index);
      return 1;
    }
    return _treeAlpha[index] = a;
  }

  double _fadeStep = 1;
  int _skyMinute = -1;
  ForestWeather? _skyWeather;

  // ---- stepping ----
  void update(double dt) {
    dt = math.min(0.05, dt);
    t += dt * _motion;
    final minute = (hour * 60).floor();
    if (_skyMinute != minute || _skyWeather != weather) {
      _skyMinute = minute;
      _skyWeather = weather;
      sky = skyState(hour, weather);
      _sceneLight = _quantised(mixRgb(sky.treeLight, [255, 255, 255], sky.night * 0.34));
    }
    final sk = sky;
    _fadeStep = reducedMotion ? 1 : math.min(1, dt * 8);
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
    final dest = _destination;
    if (dest != null) {
      final from = _from!;
      _flightTime += dt;
      final progress = reducedMotion ? 1.0 : clamp01(_flightTime / 0.68);
      final k = _easeInOut(progress);
      camX = lerp(from.x, dest.x, k);
      zoom = lerp(from.zoom, dest.zoom, k);
      lift = lerp(from.lift, dest.lift, k);
      if (progress == 1) _destination = null;
      return;
    }
    if (focusedTree != null) return;
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
      final picture = recorder.endRecording();
      try {
        image = picture.toImageSync((w * res).ceil(), (h * res).ceil());
      } finally {
        picture.dispose();
      }
    } catch (_) {
      image = null;
    }
    return _treeImages[sp] = image;
  }

  void _stamp(ui.Canvas c, int sp, double x, double y, double sc, double shear, [double alpha = 1]) {
    final spec = treeSpecies[sp];
    c.save();
    c.translate(x, y);
    c.transform(_shear(shear));
    c.scale(sc, sc);
    final image = _treeImage(sp);
    if (image == null) {
      paintTree(c, geometryFor(sp), spec, 7, light: _light, opacity: alpha);
    } else {
      const pad = 26.0;
      final w = spec.width + pad * 2, h = spec.height + pad * 2 + 10;
      _stampPaint.color = Color.fromRGBO(255, 255, 255, alpha);
      c.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Rect.fromLTWH(-w / 2, -(h - pad), w, h), _stampPaint);
    }
    c.restore();
  }

  double _treeSway(double phase) {
    final amp = 0.010 + sky.wind * 0.030;
    final gust = 0.6 + 0.4 * math.sin(t * 0.23 + phase * 0.3);
    return (math.sin(t * 0.75 + phase) * amp * gust + sky.wind * amp * 0.6) * _motion;
  }

  void _shadow(ui.Canvas c, double x, double y, double halfW, double scale, [double alpha = 1]) {
    final dayA = (1 - sky.night * 0.7) * alpha;
    c.drawOval(Rect.fromCenter(center: Offset(x, y + 2), width: 2 * math.max(10, halfW * 0.5 * scale), height: 12 * scale), ui.Paint()..color = Color.fromRGBO(20, 30, 15, 0.16 * dayA));
    if (sky.shadow > 0.3 && sky.sun.a > 0.05) {
      final dir = x > sky.sun.x ? 1.0 : -1.0, len = sky.shadow * 46 * scale + halfW * 0.25 * scale;
      c.drawOval(Rect.fromCenter(center: Offset(x + dir * len * 0.7, y + 3), width: 2 * (len + halfW * 0.3 * scale), height: 14 * scale), ui.Paint()..color = Color.fromRGBO(30, 25, 40, 0.1 * clamp01(sky.shadow / 2) * sky.sun.a * alpha));
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
    if (size.isEmpty) return;
    final (scale, dy) = fit(size);
    final sk = sky;
    final newLight = _sceneLight;
    if (newLight[0] != _light[0] || newLight[1] != _light[1] || newLight[2] != _light[2]) {
      _light = newLight;
      for (final i in _treeImages.values) {
        i?.dispose();
      }
      _treeImages.clear();
      _mainPic?.dispose();
      _mainPic = null;
      _mainStage = -1;
    }

    canvas.save();
    // The scenery deliberately overscans. Keep it inside the route during push/pop.
    canvas.clipRect(Offset.zero & size);
    canvas.scale(scale, scale);
    canvas.translate(0, dy);
    final top = -dy - 10, bottom = designH + dy + 10;
    final t = this.t;

    _drawSky(canvas, sk, top, bottom);
    if (flash > 0) {
      canvas.drawCircle(Offset(_flashX, 300), 260, ui.Paint()..shader = ui.Gradient.radial(Offset(_flashX, 300), 260, [Color.fromRGBO(235, 235, 255, 0.28 * flash), const Color(0x00EBEBFF)]));
    }
    _drawNightSky(canvas, sk, t);
    _drawClouds(canvas, sk, t, top);
    _drawBirds(canvas, sk);
    _drawBat(canvas);
    _drawHills(canvas, sk);
    _drawGround(canvas, sk, bottom);

    // trees far to near, with grass layered between depths
    final items = <({double z, void Function() draw})>[];
    final newHits = <WorldHit>[];
    final selection = focusedTree;
    final target = selection == null ? null : selection < 0 ? const Slot(0, mainZ) : slotOf(selection);
    final focus = target == null ? null : _treeHit(selection!, screenOf(target.x, target.z), target.z, 0).rect;
    final focusDepth = target?.z ?? 0.0;
    for (var i = 0; i < finished.length; i++) {
      if (i == hideFinished) continue;
      final tr = finished[i], slot = slotOf(i), sp = treeSpecies[tr.species];
      final p = screenOf(slot.x, slot.z), sc = depthScale(slot.z) * _zf(slot.z);
      final index = i;
      final shear = _treeSway(index * 7.0 + 3);
      final hit = _treeHit(index, p, slot.z, shear);
      final alpha = _alphaFor(hit, slot.z, focus, focusDepth);
      if (hit.rect.right < -25 || hit.rect.left > designW + 25 || hit.rect.top > bottom) continue;
      items.add((
        z: slot.z,
        draw: () {
          final geo = geometryFor(tr.species);
          _shadow(canvas, p.dx, p.dy, geo.halfW, sc, alpha);
          _stamp(canvas, tr.species, p.dx, p.dy, sc, shear, alpha);
          newHits.add(hit);
          if (alpha > 0.7 && _motion > 0 && (sp.touch == 'blossom' || sp.touch == 'autumn' || sk.wind > 0.8) && _rnd.nextDouble() < 0.016 * (sp.touch == 'blossom' || sp.touch == 'autumn' ? 0.5 : 0.2) * (0.5 + sk.wind)) {
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
      final shear = _treeSway(1) * smooth(1, 5, dispS);
      final hit = _treeHit(-1, mp, mainZ, shear);
      final alpha = _alphaFor(hit, mainZ, focus, focusDepth) * seedFade;
      items.add((
        z: mainZ,
        draw: () {
          canvas.save();
          canvas.translate(mp.dx, mp.dy);
          canvas.scale(1.3 * mz, 1.3 * mz);
          paintSoil(canvas, dispS, wet, light: _light, opacity: alpha * (selection != null && selection >= 0 ? 0.34 : 1));
          canvas.restore();
          final rv = revealAt(dispS), geo = geometryFor(species);
          if (dispS > 3) _shadow(canvas, mp.dx, mp.dy, geo.halfW * rv.sc, mz, alpha);
          _refreshMain();
          final pic = _mainPic;
          if (pic != null) {
            final fading = alpha < 0.998;
            canvas.save();
            if (fading) canvas.saveLayer(hit.rect.inflate(24), ui.Paint()..color = Color.fromRGBO(255, 255, 255, clamp01(alpha)));
            canvas.translate(mp.dx, mp.dy);
            canvas.scale(mz, mz);
            canvas.transform(_shear(shear));
            canvas.drawPicture(pic);
            if (fading) canvas.restore();
            canvas.restore();
          }
          newHits.add(hit);
          if (alpha > 0.7 && _motion > 0 && dispS > 6.5 && (mainSp.touch == 'blossom' || mainSp.touch == 'autumn') && _rnd.nextDouble() < 0.01) {
            final cl = geo.clumps.isEmpty ? null : geo.clumps[_rnd.nextInt(geo.clumps.length)];
            if (cl != null) {
              _spawnDrift(mp.dx + cl.x * mz, mp.dy + cl.y * mz, mp.dy + 8 + _rnd.nextDouble() * 30, mainSp.touch == 'blossom' ? const Color(0xFFF7C3D2) : const Color(0xFFE9772C), mainSp.touch == 'blossom');
            }
          }
        },
      ));
    }
    items.sort((a, b) => b.z.compareTo(a.z));
    final tufts = _grass;
    var zPrev = 1.01;
    for (final it in items) {
      _drawGrass(canvas, sk, t, tufts, it.z, zPrev, bottom, focus, focusDepth);
      zPrev = it.z;
      it.draw();
    }
    _drawGrass(canvas, sk, t, tufts, -3, zPrev, bottom, focus, focusDepth);
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
    _drawPins(canvas, bottom);
    canvas.restore();
  }

  void _refreshMain() {
    final stage = (dispS * 100).round() / 100;
    if (_mainPic != null && _mainStage == stage && _mainSpecies == species) return;
    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    paintTree(c, geometryFor(species), treeSpecies[species], stage, light: _light);
    _mainPic?.dispose();
    _mainPic = recorder.endRecording();
    _mainStage = stage;
    _mainSpecies = species;
  }

  void _drawSky(ui.Canvas c, SkyState sk, double top, double bottom) {
    final horizon = _farY(_horizon);
    final paint = ui.Paint()
      ..shader = ui.Gradient.linear(Offset(0, math.min(0, top)), Offset(0, math.max(270, horizon)), [
        _col(shadeRgb(sk.skyTop, -0.12)), _col(sk.skyMid), _col(mixRgb(sk.skyMid, sk.skyBot, 0.84)), _col(sk.skyBot),
      ], [0, 0.47, 0.87, 1]);
    c.drawRect(Rect.fromLTRB(-10, top, designW + 10, bottom), paint);
    final s = sk.sun;
    if (s.a > 0.01) {
      final col = mixRgb([255, 251, 221], [255, 171, 106], s.warm);
      final r = 90 + s.warm * 120;
      final center = Offset(s.x, s.y);
      paint.shader = ui.Gradient.radial(center, r, [_col(col, 0.79 * s.a), _col(col, 0.32 * s.a), _col(col, 0)], [0, 0.33, 1]);
      c.drawCircle(center, r, paint);
      paint.shader = ui.Gradient.linear(Offset(0, s.y - 13), Offset(0, s.y + 13), [_col([255, 250, 222], s.a), _col(col, s.a)]);
      c.drawCircle(center, 13, paint);
    }
    paint.shader = ui.Gradient.linear(Offset(0, horizon - 128), Offset(0, horizon + 25), [
      _col(sk.skyBot, 0), _col(sk.skyBot, 0.45 + 0.28 * sk.fog), _col(sk.skyBot, 0.60),
    ], [0, 0.83, 1]);
    c.drawRect(Rect.fromLTRB(-10, horizon - 128, designW + 10, horizon + 25), paint);
  }

  ui.Image _cloudImage(_Cloud cloud, Color soft, Color shadow, Color rim) {
    return _cloudImages.putIfAbsent(cloud, () {
      const bounds = Rect.fromLTWH(-26, -10, 277, 120);
      final recorder = ui.PictureRecorder(), paint = ui.Paint();
      final c = ui.Canvas(recorder);
      c.scale(2, 2);
      c.translate(26, 10);
      c.saveLayer(bounds, ui.Paint());
      for (final puff in cloud.puffs) {
        c.save();
        c.translate(puff.x, puff.y + 10);
        c.scale(1, puff.ry * 1.32 / puff.rx);
        final r = puff.rx * 1.45;
        paint.shader = ui.Gradient.radial(Offset.zero, r, const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)], const [0, 0.52, 1]);
        c.drawCircle(Offset.zero, r, paint);
        c.restore();
      }
      paint
        ..blendMode = ui.BlendMode.srcIn
        ..shader = ui.Gradient.linear(const Offset(0, 20), const Offset(0, 86), [rim, Color.lerp(soft, rim, 0.52)!, soft, shadow], [0, 0.43, 0.76, 1]);
      c.drawRect(bounds, paint);
      paint.blendMode = ui.BlendMode.srcATop;
      for (final puff in cloud.puffs) {
        c.save();
        c.translate(puff.x - puff.rx * 0.13, puff.y - puff.ry * 0.12);
        c.scale(1, puff.ry / puff.rx);
        final r = puff.rx * 1.15;
        paint.shader = ui.Gradient.radial(Offset.zero, r, [rim.withValues(alpha: 0.52), rim.withValues(alpha: 0)]);
        c.drawCircle(Offset.zero, r, paint);
        c.restore();
      }
      c.restore();
      final picture = recorder.endRecording();
      try {
        return picture.toImageSync(554, 240);
      } finally {
        picture.dispose();
      }
    });
  }

  void _drawClouds(ui.Canvas c, SkyState sk, double t, double top) {
    final coverage = sk.cover * sk.cover;
    final haze = ui.Paint()..shader = ui.Gradient.linear(Offset(0, math.min(4, top)), const Offset(0, 345), [
      _col(shadeRgb(sk.cloudCol, -0.22), coverage * 0.55), _col(sk.cloudCol, coverage * 0.23), _col(sk.cloudCol, 0),
    ], [0, 0.78, 1]);
    c.drawRect(Rect.fromLTRB(-10, top, designW + 10, 345), haze);
    final base = _quantised(sk.cloudCol), light = mixRgb([255, 255, 248], [255, 209, 170], sk.sun.warm * sk.day * 0.65);
    final soft = mixRgb(base, [148, 157, 178], sk.weather.grey * 0.38);
    final shadow = shadeRgb(soft, -0.13 - sk.weather.dim * 0.52);
    final rim = mixRgb(soft, light, sk.day * (0.8 - sk.weather.grey * 0.56));
    final palette = (soft: _col(_quantised(soft)), shadow: _col(_quantised(shadow)), rim: _col(_quantised(rim)));
    if (palette != _cloudPalette) {
      for (final image in _cloudImages.values) {
        image.dispose();
      }
      _cloudImages.clear();
      _cloudPalette = palette;
    }
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.low;
    for (final cl in _scenery.$2) {
      final vis = cl.rank == 0 ? 0.76 : smooth(cl.rank - 0.06, cl.rank + 0.15, sk.cover);
      if (vis < 0.02) continue;
      final speed = (cl.low ? 3 : 5) * (0.35 + sk.wind * 1.15);
      final x = (cl.x0 + t * speed - camX * (cl.low ? 0.08 : 0.17) + 200) % 780 - 200;
      final s = cl.s * (1 + sk.cover * 0.23 + (zoom - 1) * 0.06);
      final y = cl.y + lift * (cl.low ? 0.31 : 0.19) + top * 0.40;
      final dest = Rect.fromLTWH(x - 138 * s, y - 60 * s, 277 * s, 120 * s * (cl.low ? 0.69 : 1));
      if (dest.right < 0 || dest.left > designW) continue;
      final image = _cloudImage(cl, palette.soft, palette.shadow, palette.rim);
      paint.color = Color.fromRGBO(255, 255, 255, vis * (cl.low ? 0.61 : 0.89) * (1 - sk.fog * 0.45));
      c.drawImageRect(image, const Rect.fromLTWH(0, 0, 554, 240), dest, paint);
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

  double _farY(double y) => _projectY(y, 1);

  void _drawHills(ui.Canvas c, SkyState sk) {
    final snowy = snowCover * 0.7;
    for (final h in _hills) {
      final base = switch (h.key) { 'far' => sk.hillFar, 'mid' => sk.hillMid, _ => sk.hillNear };
      final col = mixRgb(base, [236, 240, 244], snowy * (h.key == 'far' ? 0.8 : 1) * (1 - sk.night * 0.6));
      final floor = math.max(designH + 400, _farY(_horizon) + 400);
      final path = ui.Path()..moveTo(-10, floor);
      for (var x = -10.0; x <= designW + 10; x += 8) {
        path.lineTo(x, _farY(h.y(x + camX * h.pf)));
      }
      path.lineTo(designW + 10, floor);
      path.close();
      c.drawPath(path, ui.Paint()..color = _col(col));
      if (h.trees) {
        final dark = ui.Paint()..color = _col(shadeRgb(col, -0.14));
        final pf = h.pf, step = h.key == 'near' ? 19.0 : 13.0, x0 = ((camX * pf - 20) / step).floor();
        for (var i = x0; i < x0 + designW / step + 3; i++) {
          final r = mulberry32(i * 31 + (h.key == 'near' ? 7 : 3));
          if (r() < 0.45) continue;
          final wx = i * step + r() * step, x = wx - camX * pf, y = _farY(h.y(wx)) + 2, sz = (h.key == 'near' ? 6 : 4) * (0.7 + r() * 0.6);
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
      ui.Paint()..shader = ui.Gradient.linear(Offset(0, yh), Offset(0, math.max(yh + 1, bottom)), [_col(topC), _col(botC)]),
    );
    if (puddles > 0.02) {
      final paint = ui.Paint()..color = _col(mixRgb(sk.skyMid, [120, 140, 160], 0.4), 0.35 * puddles);
      for (final p in const [[-120.0, 590.0, 34.0], [95.0, 612.0, 26.0], [260.0, 575.0, 30.0], [-300.0, 600.0, 28.0], [430.0, 620.0, 36.0]]) {
        final pos = screenOf(p[0], (536 - p[1]) / 162);
        final x = pos.dx;
        if (x < -60 || x > designW + 60) continue;
        c.drawOval(Rect.fromCenter(center: pos, width: 2 * p[2] * puddles * zoom, height: 10 * puddles * zoom), paint);
      }
    }
  }

  // A seamless world tile. The rows extend past the original ground so tall
  // screens and a zoomed camera still have grass to the bottom edge.
  static const _grassTile = 1080.0;
  static final _grass = <_Tuft>[
    for (var row = 0; row < 35; row++) ...[
      for (var cell = 0; cell < (row < 10 ? 54 : 72); cell++) _grassTuft(row, cell),
    ],
  ];

  static _Tuft _grassTuft(int row, int cell) {
    final r = mulberry32(6619 + row * 34567 + cell * 7349);
    return _Tuft(0.98 - row * 0.092 + (r() - 0.5) * 0.082, (cell + r()) * (row < 10 ? 20 : 15), r(), r());
  }

  ui.Image? _grassSprite;
  static const _grassSource = Rect.fromLTWH(0, 0, 40, 40);

  ui.Image get _grassStamp {
    final existing = _grassSprite;
    if (existing != null) return existing;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(2, 2);
    final path = ui.Path();
    for (final (spread, height) in const [(-5.0, 8.0), (-2.0, 13.0), (0.0, 15.0), (3.0, 12.0), (6.0, 8.0)]) {
      final root = 10 + spread * 0.18;
      path
        ..moveTo(root, 17)
        ..quadraticBezierTo(10 + spread * 0.44, 12, 10 + spread, 17 - height)
        ..quadraticBezierTo(10 + spread * 0.60, 14, root + 0.86, 17)
        ..close();
    }
    canvas.drawPath(path, ui.Paint()..color = const Color(0xFFFFFFFF));
    final picture = recorder.endRecording();
    try {
      return _grassSprite = picture.toImageSync(40, 40);
    } finally {
      picture.dispose();
    }
  }

  void _drawGrass(ui.Canvas c, SkyState sk, double t, List<_Tuft> tufts, double zMin, double zMax, double bottom, Rect? focus, double focusDepth) {
    final sway = (0.010 + sk.wind * 0.030) * 8 * _motion;
    final ground = mixRgb(sk.groundBot, [156, 174, 184], snowCover * 0.78);
    final tones = [shadeRgb(ground, -0.36), shadeRgb(ground, -0.16), shadeRgb(ground, 0.12)];
    final colors = [
      for (final a in const [0.84, 0.22])
        for (final tone in tones) _col(tone, a),
    ];
    final transforms = <ui.RSTransform>[], rects = <Rect>[], tints = <Color>[];
    final top = _farY(_horizon);
    final tileLeft = camX - _grassTile / 2;
    final flower = ui.Paint()..color = _col(mixRgb([247, 234, 182], [76, 107, 89], sk.night), 0.85);
    for (final tf in tufts) {
      final z = tf.z;
      if (z < zMin || z >= zMax) continue;
      final worldX = (tf.wx - tileLeft) % _grassTile + tileLeft;
      final zf = _zf(z);
      final x = _cx + (worldX - camX) * depthParallax(z) * zf;
      if (x < -20 || x > designW + 20) continue;
      final y = _projectY(depthY(z), z);
      if (y < top || y > bottom + 24) continue;
      final s = lerp(1.55, 0.43, clamp01((z + 0.56) / 1.55)) * (0.66 + tf.side * 0.52) * math.sqrt(zf);
      final turn = math.sin(t * 0.9 + worldX * 0.035) * sway;
      final muted = focus != null && z < focusDepth && x > focus.left && x < focus.right && y > focus.top && y - 21 * s < focus.bottom;
      transforms.add(ui.RSTransform.fromComponents(rotation: turn, scale: s / 2, anchorX: 20, anchorY: 34, translateX: x, translateY: y));
      rects.add(_grassSource);
      tints.add(colors[(tf.side * 3).floor() + (muted ? 3 : 0)]);
      if (!muted && tf.fl < 0.026 && z < 0.5 && snowCover < 0.45) {
        c.drawOval(Rect.fromCenter(center: Offset(x + turn * 13 * s, y - 13 * s), width: 3.6 * s, height: 2.7 * s), flower);
      }
    }
    if (transforms.isNotEmpty) {
      c.drawAtlas(_grassStamp, transforms, rects, tints, ui.BlendMode.modulate, null, ui.Paint()..filterQuality = ui.FilterQuality.low);
    }
  }

  void _drawButterflies(ui.Canvas c) {
    for (final b in _butterflies) {
      if (b.a <= 0.01) continue;
      final zf = _zf(0.3);
      final x = _cx + (b.ax - camX) * zf + math.sin(b.p * 0.31) * 60 + math.sin(b.p * 0.83) * 14;
      final y = _projectY(b.ay + math.sin(b.p * 0.47) * 26 + math.cos(b.p * 1.1) * 6, 0.3);
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

  void _drawNightSky(ui.Canvas c, SkyState sk, double t) {
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
  }

  void _drawLight(ui.Canvas c, SkyState sk, double top, double bottom, double t) {
    final wash = Rect.fromLTRB(-10, top, designW + 10, bottom);
    if (sk.tintA > 0.005) c.drawRect(wash, ui.Paint()..color = _col(sk.tint, sk.tintA * (1 - 0.25 * sk.night)));
    c.drawRect(wash, ui.Paint()..shader = ui.Gradient.radial(const Offset(_cx, 380), 520, [const Color(0x000A0F1E), Color.fromRGBO(10, 15, 30, 0.22 + sk.night * 0.2)], [220 / 520, 1]));

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

  void _drawPins(ui.Canvas c, double bottom) {
    _pins.clear();
    if (focusedTree != null || isFlying || slideK >= 0) return;
    final paint = ui.Paint();
    for (final h in hits) {
      final index = h.finishedIndex;
      if (index < 0 || h.base.dx < 13 || h.base.dx > designW - 13 || h.base.dy > bottom - 112) continue;
      if (!hits.any((other) => other != h && other.rect.overlaps(h.rect))) continue;
      var center = h.base + const Offset(0, 17);
      // Keep pins from covering one another when two trunks nearly line up.
      while (_pins.any((pin) => pin.bounds.contains(center))) {
        center += const Offset(0, 24);
      }
      if (center.dy > bottom - 95) continue;
      final bounds = Rect.fromCenter(center: center, width: 31, height: 23);
      final chip = ui.RRect.fromRectAndRadius(bounds, const ui.Radius.circular(12));
      c.drawRRect(chip, paint..color = const Color(0xDD253F34));
      c.drawRRect(chip.deflate(0.5), paint
        ..style = ui.PaintingStyle.stroke
        ..color = const Color(0xB8F1F6E6));
      paint.style = ui.PaintingStyle.fill;
      final label = _pinLabels.putIfAbsent(index, () {
        final text = (finished[index].index + 1).toString().padLeft(2, '0');
        return (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: 10, fontWeight: ui.FontWeight.w700))
              ..pushStyle(ui.TextStyle(color: const Color(0xFFF7F9E9)))
              ..addText(text))
            .build()..layout(const ui.ParagraphConstraints(width: 31));
      });
      c.drawParagraph(label, Offset(bounds.left, center.dy - label.height / 2));
      _pins.add((bounds: bounds.inflate(3), tree: h));
    }
  }

  /// A visible crown wins before a forgiving hit near a trunk or planting spot.
  WorldHit? hitTest(Offset p) {
    for (final pin in _pins.reversed) {
      if (pin.bounds.contains(p)) return pin.tree;
    }
    WorldHit? nearby;
    var nearest = double.infinity;
    for (final h in hits.reversed) {
      if (_blockers.contains(h.finishedIndex) || !h.rect.inflate(9).contains(p)) continue;
      final delta = (p - h.base) / h.scale;
      final local = Offset(delta.dx - delta.dy * h.shear, delta.dy);
      if (h.finishedIndex >= 0) {
        final sp = finished[h.finishedIndex].species;
        final outline = _treeOutlines.putIfAbsent(sp, () => matureTreeOutline(geometryFor(sp)));
        if (outline.contains(local)) return h;
      } else if (dispS < 3.8 && local.dx.abs() < 17 && local.dy < 7 && local.dy > -lerp(13, 78, clamp01((dispS - 1) / 2))) {
        return h;
      } else if (dispS >= 3.8) {
        final rv = revealAt(dispS);
        if (matureTreeOutline(geometryFor(species), rv).contains(local / rv.sc)) return h;
      }
      final distance = (p - h.base).distance;
      final reach = h.finishedIndex < 0 && dispS < 3.8 ? 49.0 : 33.0;
      if (distance < reach && distance < nearest) {
        nearby = h;
        nearest = distance;
      }
    }
    return nearby;
  }

  void dispose() {
    for (final i in _treeImages.values) {
      i?.dispose();
    }
    _treeImages.clear();
    for (final image in _cloudImages.values) {
      image.dispose();
    }
    _cloudImages.clear();
    _mainPic?.dispose();
    _grassSprite?.dispose();
  }
}
