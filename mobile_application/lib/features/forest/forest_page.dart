import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/forest/forest_garden.dart';
import '../../domain/forest/tree_geometry.dart';
import 'forest_card_scene.dart';
import 'forest_controller.dart';
import 'tree_painter.dart';

const _stageNames = ['A new seed', 'Seed planted', 'Sprouting', 'Seedling', 'Sapling', 'Young tree', 'Mature tree', 'Fully grown'];
const _kindText = {
  WaterKind.text: 'You did a check-in',
  WaterKind.journal: 'You recorded a journal',
  WaterKind.task: 'You did something kind for yourself',
};
const _settled = ['That is all it needed for now.', 'Slow and steady.', 'Rest well. It grows while you do.'];

/// Where the finished tree number [i] stands in the forest, and how big it is compared with the one being grown.
({double dx, double base, double scale}) _slotFor(int i, double w, double h) {
  final r = mulberry32(9001 + i * 131);
  final side = i.isEven ? 1.0 : -1.0, ring = i ~/ 2;
  final depth = .15 + r() * .8;
  return (
    dx: side * (w * .36 + ring * w * .22 + r() * w * .1),
    base: h * (.55 + (1 - depth) * .17),
    scale: lerp(.62, .34, depth),
  );
}

class _Drop {
  _Drop(this.x, this.delay);
  final double x, delay;
}

class _Spark {
  _Spark(this.angle, this.dist);
  final double angle, dist;
}

/// The forest: the tree being grown, the trees finished before it, the sky of the hour. On opening it pours, one at a time,
/// the waters earned today that have not been watched yet, grows the tree a little for each, and then settles.
class ForestPage extends StatefulWidget {
  const ForestPage({required this.controller, super.key});

  final ForestController controller;

  @override
  State<ForestPage> createState() => _ForestPageState();
}

class _ForestPageState extends State<ForestPage> with TickerProviderStateMixin {
  late Garden _shown = widget.controller.garden;
  late double _stage = _shown.stage;
  late List<FinishedTree> _forest = _shown.finished;

  Ticker? _ticker;
  double _time = 0;
  double _pan = 0;
  double _wet = 0, _glow = 0, _canAlpha = 0, _canTilt = 0, _pour = -1, _slide = -1, _spark = -1;
  String _caption = '';
  bool _disposed = false;
  List<_Drop> _drops = const [];
  final _sparks = List.generate(18, (i) => _Spark(i * math.pi * 2 / 18 + (i % 3) * .2, 50 + (i * 37 % 70).toDouble()));
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      if (!_disposed && mounted) setState(() => _time = d.inMilliseconds / 1000);
    })..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _active.toList()) {
      _active.remove(c);
      c.dispose();
    }
    _ticker?.dispose();
    super.dispose();
  }

  int _ms(int ms) => _reduced ? (ms / 5).round() : ms;

  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: _ms(ms)));

  /// Runs [apply] with 0..1 over [ms] (eased), updating the page on every frame.
  Future<void> _tween(int ms, void Function(double t) apply, {Curve curve = Curves.easeInOut}) async {
    if (_disposed) return;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: _ms(ms)));
    _active.add(c);
    final curved = CurvedAnimation(parent: c, curve: curve);
    curved.addListener(() {
      if (!_disposed && mounted) setState(() => apply(curved.value));
    });
    try {
      await c.forward().orCancel;
    } on TickerCanceled {
      // the page went away mid-animation
    } finally {
      if (_active.remove(c)) c.dispose();
    }
  }

  /// The animations still running, so leaving the page can stop them all.
  final _active = <AnimationController>{};

  int _total(Garden g) => g.finished.length * g.config.watersPerTree + g.currentProgress;

  Future<void> _play() async {
    final controller = widget.controller;
    final waiting = controller.waiting;
    if (waiting.isEmpty) return;
    var prev = controller.garden;
    for (var i = 1; i <= waiting.length && !_disposed; i++) {
      final after = controller.gardenAfter(i);
      final grew = _total(after) - _total(prev);
      setState(() => _caption = _kindText[waiting[i - 1].kind] ?? '');
      await _wait(1100);
      if (_disposed) return;

      // the can tips and pours; the soil darkens
      _drops = [for (var k = 0; k < 9; k++) _Drop(-6 + (k * 7 % 13).toDouble(), k * .07)];
      unawaited(_tween(500, (t) => _canAlpha = t));
      await _tween(500, (t) => _canTilt = -.38 * t);
      unawaited(_tween(1900, (t) => _pour = t, curve: Curves.linear));
      await _tween(1700, (t) => _wet = math.min(1, t * 1.6));
      if (_disposed) return;

      if (grew == 0) {
        setState(() => _caption = 'It still counts. The tree is resting for today.');
      } else {
        final finishes = after.finished.length > prev.finished.length;
        final from = _stage, to = finishes ? 7.0 : after.stage;
        await _tween(finishes ? 3200 : 3800, (t) => _stage = lerp(from, to, t));
        if (finishes) {
          setState(() => _caption = 'This tree is fully grown. It joins your forest.');
          unawaited(_tween(2600, (t) => _glow = math.sin(t * math.pi)));
          await _tween(2400, (t) => _spark = t, curve: Curves.easeOut);
          _spark = -1;
          await _tween(2600, (t) => _slide = t, curve: Curves.easeInOutCubic);
          if (_disposed) return;
          setState(() {
            _shown = after;
            _forest = after.finished;
            _stage = after.stage;
            _slide = -1;
            _caption = 'A new seed. Take it at your own pace.';
          });
        } else {
          setState(() => _shown = after);
        }
      }
      unawaited(_tween(900, (t) => _canAlpha = 1 - t));
      final wetNow = _wet;
      await _tween(900, (t) {
        _canTilt = -.38 * (1 - t);
        _wet = wetNow * (1 - t * .5);
      });
      _pour = -1;
      prev = after;
      await _wait(1300);
    }
    if (_disposed) return;
    final wetNow = _wet;
    await _tween(1800, (t) => _wet = wetNow * (1 - t));
    if (_disposed) return;
    setState(() => _caption = _settled[widget.controller.now.millisecond % _settled.length]);
    await widget.controller.markWatched();
  }

  double get _limit {
    final w = MediaQuery.sizeOf(context).width;
    return w * .3 + (_forest.length / 2).ceil() * w * .22;
  }

  @override
  Widget build(BuildContext context) {
    final palette = ForestPalette.forHour(widget.controller.now.hour);
    final stageIndex = _stage.floor().clamp(0, 7);
    return Scaffold(
      backgroundColor: palette.skyB,
      body: GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() => _pan = (_pan + d.delta.dx).clamp(-_limit, _limit)),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ForestScenePainter(
                  palette: palette,
                  species: _shown.currentSpecies,
                  stage: _stage,
                  finished: _forest,
                  pan: _pan,
                  time: _time,
                  wet: _wet,
                  glow: _glow,
                  canAlpha: _canAlpha,
                  canTilt: _canTilt,
                  pour: _pour,
                  drops: _drops,
                  slide: _slide,
                  spark: _spark,
                  sparks: _sparks,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('forest-back'),
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const Expanded(
                      child: Text(
                        'YOUR FOREST',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.8, shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)]),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xD9FFFFFF), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        _forest.length == 1 ? '1 tree grown' : '${_forest.length} trees grown',
                        key: const ValueKey('forest-count'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF3D3226)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_pan.abs() > 20)
              Positioned(
                right: 16,
                top: MediaQuery.paddingOf(context).top + 56,
                child: ElevatedButton(
                  key: const ValueKey('forest-home'),
                  onPressed: () => setState(() => _pan = 0),
                  child: const Text('Back to my tree'),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: BoxDecoration(
                  color: const Color(0xE6FFFAF0),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _stageNames[stageIndex],
                          key: const ValueKey('forest-stage'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF3D3226)),
                        ),
                        Text('Tree ${_shown.currentIndex + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF85766A))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Container(
                              height: 6,
                              margin: EdgeInsets.only(right: i == 6 ? 0 : 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                color: i < stageIndex ? const Color(0xFF9CCF6A) : const Color(0xFFE3D8BF),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _caption.isEmpty ? 'Check in, journal or try something kind, and your tree gets a little water.' : _caption,
                        key: ValueKey(_caption),
                        style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: Color(0xFF85766A)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForestScenePainter extends CustomPainter {
  _ForestScenePainter({
    required this.palette,
    required this.species,
    required this.stage,
    required this.finished,
    required this.pan,
    required this.time,
    required this.wet,
    required this.glow,
    required this.canAlpha,
    required this.canTilt,
    required this.pour,
    required this.drops,
    required this.slide,
    required this.spark,
    required this.sparks,
  });

  final ForestPalette palette;
  final int species;
  final double stage, pan, time, wet, glow, canAlpha, canTilt, pour, slide, spark;
  final List<FinishedTree> finished;
  final List<_Drop> drops;
  final List<_Spark> sparks;

  double _sway(double phase) => math.sin(time * .75 + phase) * .012;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, p = palette;
    final horizon = h * .46;

    // sky, stars, sun or moon
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, horizon + 10), [p.skyB, p.skyA]),
    );
    if (p.stars > 0) {
      final star = Paint();
      for (var i = 0; i < 70; i++) {
        final r = mulberry32(i * 31 + 5);
        final tw = .55 + .45 * math.sin(time * 1.4 + i);
        star.color = Colors.white.withValues(alpha: p.stars * tw);
        canvas.drawCircle(Offset(r() * w, r() * horizon * .85), .6 + r() * 1.1, star);
      }
    }
    final sunFrac = switch (p.name) { 'day' => .2, 'golden' => .55, 'dusk' => .8, _ => .22 };
    final sx = w * .78 + pan * .08, sy = horizon * (.12 + .78 * sunFrac);
    canvas.drawCircle(Offset(sx, sy), 70, Paint()..shader = ui.Gradient.radial(Offset(sx, sy), 70, [p.glow, const Color(0x00FFFFFF)]));
    canvas.drawCircle(Offset(sx, sy), p.name == 'night' ? 15 : 18, Paint()..color = p.sun);
    if (p.name == 'night') canvas.drawCircle(Offset(sx + 6, sy - 3), 13, Paint()..color = p.skyB.withValues(alpha: .95));

    // soft clouds drifting
    final cloud = Paint()..color = Colors.white.withValues(alpha: p.name == 'night' ? .08 : .55);
    for (var i = 0; i < 4; i++) {
      final x = ((time * (4 + i) + i * 140) % (w + 200)) - 100;
      final y = horizon * (.2 + i * .17);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 90, height: 24), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(x + 22, y - 8), width: 56, height: 22), cloud);
    }

    // hills move less than the ground when you look around
    Path hill(double amp, double shift) => Path()
      ..moveTo(-40, horizon + 10)
      ..quadraticBezierTo(w * .25 + shift, horizon - amp, w * .55 + shift, horizon - amp * .2)
      ..quadraticBezierTo(w * .85 + shift, horizon - amp * 1.1, w + 40, horizon - amp * .1)
      ..lineTo(w + 40, h)
      ..lineTo(-40, h)
      ..close();
    canvas.drawPath(hill(46, pan * .12), Paint()..color = Color.lerp(p.ground[0], p.skyA, .35)!);
    canvas.drawPath(hill(26, pan * .3), Paint()..color = Color.lerp(p.ground[0], p.ground[1], .3)!);
    canvas.drawRect(
      Rect.fromLTWH(0, horizon + 8, w, h),
      Paint()..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, h), [p.ground[0], p.ground[1]]),
    );
    if (p.tint != null) canvas.drawRect(Offset.zero & size, Paint()..color = p.tint!);

    // the trees, far to near, with the light of the hour over them only
    canvas.saveLayer(Offset.zero & size, Paint());
    final mainBase = h * .79, mainScale = _scaleFor(treeSpecies[species], w, h);
    final order = <int>[for (var i = 0; i < finished.length; i++) i]
      ..sort((a, b) => _slotFor(a, w, h).base.compareTo(_slotFor(b, w, h).base));
    for (final i in order) {
      final sp = treeSpecies[finished[i].species];
      final slot = _slotFor(i, w, h);
      var x = w / 2 + pan + slot.dx, y = slot.base, sc = _scaleFor(sp, w, h) * slot.scale;
      if (slide >= 0 && i == finished.length - 1) {
        final t = slide;
        x = lerp(w / 2 + pan, x, t);
        y = lerp(mainBase, y, t);
        sc = lerp(_scaleFor(sp, w, h), sc, t);
      }
      _shadow(canvas, x, y, sc * sp.width * .3, p);
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(sc, sc);
      canvas.transform(Matrix4.skew(_sway(i * 1.3), 0).storage);
      paintTree(canvas, geometryFor(finished[i].species), sp, 7);
      canvas.restore();
    }
    if (slide < 0) {
      final sp = treeSpecies[species];
      _shadow(canvas, w / 2 + pan, mainBase, mainScale * (30 + 60 * clamp01((stage - 2) / 4.5)), p);
      canvas.save();
      canvas.translate(w / 2 + pan, mainBase);
      canvas.scale(mainScale, mainScale);
      final young = stage < 4.2 ? lerp(1.5, 1, stage / 4.2) : 1.0;
      canvas.scale(young, young);
      if (stage > 3.5) canvas.transform(Matrix4.skew(_sway(0), 0).storage);
      paintTree(canvas, geometryFor(species), sp, stage, soil: true, wet: wet);
      canvas.restore();
    }
    if (p.treeTint != null) {
      canvas.drawRect(Offset.zero & size, Paint()
        ..color = p.treeTint!
        ..blendMode = BlendMode.srcATop);
    }
    canvas.restore();

    // watering can, drops, glow and sparkles around the tree being grown
    final cx = w / 2 + pan, topY = mainBase - treeSpecies[species].height * mainScale * .9 * clamp01(stage / 6) - 30;
    if (canAlpha > 0 && slide < 0) {
      canvas.save();
      canvas.translate(cx + 74, topY);
      canvas.rotate(canTilt);
      canvas.scale(1.4, 1.4);
      paintWateringCan(canvas, alpha: canAlpha);
      canvas.restore();
    }
    if (pour >= 0) {
      final drop = Paint();
      for (final d in drops) {
        final t = clamp01((pour - d.delay) / .55);
        if (t <= 0 || t >= 1) continue;
        final x = cx + 40 + d.x - t * 30, y = topY + 10 + t * (mainBase - topY - 30);
        drop.color = const Color(0xFF8FD0EE).withValues(alpha: math.sin(t * math.pi));
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 5, height: 8), drop);
      }
    }
    if (glow > 0.01) {
      final c = Offset(cx, mainBase - h * .16);
      canvas.drawCircle(c, h * .26, Paint()..shader = ui.Gradient.radial(c, h * .26, [const Color(0xFFFFF6C8).withValues(alpha: .7 * glow), const Color(0x00FFF6C8)]));
    }
    if (spark >= 0) {
      final c = Offset(cx, mainBase - h * .16);
      for (final s in sparks) {
        final t = spark;
        final pt = c + Offset(math.cos(s.angle), math.sin(s.angle)) * (s.dist * 1.8 * t);
        canvas.drawCircle(pt, 3 * (1 - t) + .5, Paint()..color = const Color(0xFFFFD36B).withValues(alpha: 1 - t));
      }
    }
  }

  void _shadow(Canvas canvas, double x, double y, double halfW, ForestPalette p) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x - p.shadowLength * .25, y + 3), width: math.max(24, halfW * 2), height: math.max(8, halfW * .28)),
      Paint()..color = const Color(0xFF162018).withValues(alpha: p.shadowAlpha),
    );
  }

  double _scaleFor(TreeSpecies sp, double w, double h) => math.min((h * .38) / (sp.height + 30), (w * .8) / (sp.width + 30));

  @override
  bool shouldRepaint(covariant _ForestScenePainter old) => true;
}
