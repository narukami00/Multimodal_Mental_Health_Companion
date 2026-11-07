import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/day_key.dart';
import '../../domain/forest/forest_garden.dart';
import '../../domain/forest/tree_geometry.dart';
import 'forest_controller.dart';
import 'forest_world.dart';

const _stageNames = ['A new seed', 'Seed planted', 'Sprouting', 'Seedling', 'Sapling', 'Young tree', 'Mature tree', 'Fully grown'];
const _kindText = {
  WaterKind.text: 'You did a check-in',
  WaterKind.journal: 'You recorded a journal',
  WaterKind.task: 'You did something kind for yourself',
};
const _kindShort = {
  WaterKind.text: 'A check-in',
  WaterKind.journal: 'A voice or video journal',
  WaterKind.task: 'Something kind for yourself',
};
const _settled = ['That is all it needed for now.', 'Slow and steady.', 'Rest well. It grows while you do.', 'A little more rooted than before.'];
const _stageLines = ['', 'The seed is tucked into the soil.', 'A first green shoot.', 'Its first true leaves.', 'A little trunk of its own now.', 'Branches reaching out.', 'Strong roots, a wide crown.', ''];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// The forest: the tree being grown, the trees finished before it, the sky and weather of the hour, with creatures, grass and
/// parallax. On opening it pours, one at a time, the waters earned today that have not been watched yet, grows the tree a
/// little for each, and then settles. Pinch to zoom, drag to look around, tap a tree to fly in and see what grew it.
class ForestPage extends StatefulWidget {
  const ForestPage({required this.controller, super.key});

  final ForestController controller;

  @override
  State<ForestPage> createState() => _ForestPageState();
}

class _ForestPageState extends State<ForestPage> with TickerProviderStateMixin {
  late Garden _shown = widget.controller.garden;
  final _world = ForestWorld();

  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// Everything that moves is read by the painter on every frame, so frames only repaint the scene, not the whole page.
  final _frame = ValueNotifier<int>(0);
  String _caption = '';
  int _stageIndex = 0;
  int _count = 0;
  bool _away = false;
  bool _disposed = false;
  Size _size = Size.zero;
  double _startZoom = 1;

  @override
  void initState() {
    super.initState();
    _world
      ..setFinished(_shown.finished)
      ..species = _shown.currentSpecies
      ..dispS = _shown.stage;
    _stageIndex = _shown.stage.floor().clamp(0, 7);
    _count = _shown.finished.length;
    _ticker = createTicker(_onFrame)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _world.reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  void _onFrame(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final now = widget.controller.now;
    _world
      ..hour = now.hour + now.minute / 60 + now.second / 3600
      ..update(dt);
    _frame.value++;
    final index = _world.dispS.floor().clamp(0, 7);
    final away = _world.isAway;
    if (index != _stageIndex || away != _away) {
      setState(() {
        _stageIndex = index;
        _away = away;
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _active.toList()) {
      _active.remove(c);
      c.dispose();
    }
    _ticker?.dispose();
    _frame.dispose();
    _world.dispose();
    super.dispose();
  }

  int _ms(int ms) => _world.reducedMotion ? (ms / 5).round() : ms;

  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: _ms(ms)));

  /// Runs [apply] with 0..1 over [ms] (eased).
  Future<void> _tween(int ms, void Function(double t) apply, {Curve curve = Curves.easeInOut}) async {
    if (_disposed) return;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: _ms(ms)));
    _active.add(c);
    final curved = CurvedAnimation(parent: c, curve: curve);
    curved.addListener(() {
      if (!_disposed) apply(curved.value);
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

  void _say(String text) {
    if (!_disposed) setState(() => _caption = text);
  }

  int _total(Garden g) => g.finished.length * g.config.watersPerTree + g.currentProgress;

  Future<void> _growTo(double target, int ms) {
    final from = _world.dispS;
    return _tween((ms * math.max(0.6, math.min(1.6, (target - from).abs()))).round(), (t) => _world.dispS = lerp(from, target, t));
  }

  Future<void> _play() async {
    final controller = widget.controller;
    final waiting = controller.waiting;
    if (waiting.isEmpty) return;
    var prev = controller.garden;
    _world.camTargetX = 0;
    await _wait(900);
    for (var i = 1; i <= waiting.length && !_disposed; i++) {
      final after = controller.gardenAfter(i);
      final grew = _total(after) - _total(prev);
      _say(_kindText[waiting[i - 1].kind] ?? '');
      await _wait(800);
      if (_disposed) return;

      // the can tips and pours over the tree
      _world.canShower = _world.dispS >= 4;
      unawaited(_tween(2800, (t) => _world.canK = t, curve: Curves.linear));
      await _wait(1900);
      if (_disposed) return;

      if (grew == 0) {
        _say('It still counts. The tree is resting for today.');
        await _wait(2200);
      } else {
        final finishes = after.finished.length > prev.finished.length;
        final before = _world.dispS.floor();
        await _growTo(finishes ? 7.0 : after.stage, 4800);
        if (_disposed) return;
        if (finishes) {
          await _celebrate(after);
        } else {
          setState(() => _shown = after);
          final now = _world.dispS.floor().clamp(0, 7);
          if (now > before) {
            final p = _world.crownPoint();
            _world
              ..glowTarget = 0.8
              ..sparkleBurst(p.dx, p.dy, 14, _world.crownRadius);
            _say('${_stageNames[now]}. ${_stageLines[now]}');
            await _wait(1700);
            _world.glowTarget = 0;
            await _wait(1100);
          } else {
            _say('A little taller.');
          }
        }
      }
      _world.canK = -1;
      prev = after;
      await _wait(1500);
    }
    if (_disposed) return;
    await _wait(1500);
    _say(_settled[widget.controller.now.millisecond % _settled.length]);
    await widget.controller.markWatched();
  }

  /// A finished tree: a soft glow and sparkles, then it walks back to its place in the forest and a new seed appears.
  Future<void> _celebrate(Garden after) async {
    final done = after.finished.last;
    final sp = treeSpecies[done.species];
    _world
      ..glowTarget = 1
      ..bigGlow = 1;
    _say('Fully grown, with ${_touchText(sp.touch)}. It stays in your forest for good.');
    for (var w = 0; w < 3; w++) {
      final p = _world.crownPoint();
      _world.sparkleBurst(p.dx, p.dy, 16, _world.crownRadius * 1.1);
      await _wait(1300);
    }
    _world.glowTarget = 0;
    await _wait(1300);
    if (_disposed) return;
    // the finished tree walks back to its place while a new seed is set in the planting spot
    _world
      ..setFinished(after.finished)
      ..hideFinished = after.finished.length - 1
      ..slideSpecies = done.species
      ..slideTo = _world.slotOf(after.finished.length - 1)
      ..species = after.currentSpecies
      ..dispS = after.stage
      ..seedFade = 0
      ..bigGlow = 0
      ..camTargetX = _world.slotOf(after.finished.length - 1).x * 0.3;
    setState(() {
      _shown = after;
      _count = after.finished.length;
    });
    await _tween(3200, (t) => _world.slideK = t, curve: Curves.linear);
    if (_disposed) return;
    _world
      ..slideK = -1
      ..hideFinished = -1
      ..camTargetX = 0;
    await _tween(1600, (t) => _world.seedFade = t);
    _say('A new seed, waiting in the soil.');
    await _wait(1400);
  }

  String _touchText(String touch) => switch (touch) {
        'acorns' => 'a few acorns',
        'catkins' => 'catkins',
        'blossom' => 'blossom',
        'cones' => 'cones',
        'fronds' => 'long golden fronds',
        'autumn' => 'autumn colour',
        'fruit' => 'apples',
        _ => 'its finishing touch',
      };

  // ---- touch: drag to look around, pinch to zoom, tap a tree to fly in ----
  void _onScaleStart(ScaleStartDetails d) {
    _startZoom = _world.zoom;
    _world
      ..dragging = true
      ..camTargetX = null
      ..zoomTarget = null
      ..focusTarget = null
      ..camV = 0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final (scale, _) = _world.fit(_size);
    final zf = _world.zoom;
    final (lo, hi) = _world.camBounds;
    var cam = _world.camX - d.focalPointDelta.dx / (scale * zf);
    if (cam < lo) cam = lo - (lo - cam) * 0.4;
    if (cam > hi) cam = hi + (cam - hi) * 0.4;
    _world.camX = cam;
    if (d.pointerCount > 1) _world.zoom = (_startZoom * d.scale).clamp(0.8, 3.0);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final (scale, _) = _world.fit(_size);
    _world
      ..dragging = false
      ..camV = (-d.velocity.pixelsPerSecond.dx / (scale * _world.zoom) * 0.5).clamp(-500, 500);
    if (_world.zoom < 1) _world.zoomTarget = 1;
  }

  void _onTapUp(Offset local) {
    final (scale, dy) = _world.fit(_size);
    final hit = _world.hitTest(Offset(local.dx / scale, local.dy / scale - dy));
    if (hit == null) return;
    if (hit.finishedIndex >= 0) {
      final slot = _world.slotOf(hit.finishedIndex);
      _world.focusOnTree(slot.x, slot.z, zoomTo: 2.0);
      unawaited(_showBreakdown(_world.finished[hit.finishedIndex]));
    } else {
      _world.focusOnTree(0, mainZ, zoomTo: 1.8);
      unawaited(_showBreakdown(null));
    }
  }

  void _home() => _world.goHome();

  Future<void> _showBreakdown(FinishedTree? tree) async {
    await _wait(650); // let the camera fly in first
    if (_disposed || !mounted) return;
    final garden = _shown;
    final species = tree == null ? garden.currentSpecies : tree.species;
    final waters = [for (final w in (tree?.waters ?? garden.currentWaters)) if (w.grown > 0) w];
    final sp = treeSpecies[species];
    final byDay = <String, List<AppliedWater>>{};
    for (final w in waters) {
      byDay.putIfAbsent(dayKey(w.event.at), () => []).add(w);
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFAF0),
      barrierColor: const Color(0x22000000),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            key: const ValueKey('tree-breakdown'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tree == null ? 'Tree ${garden.currentIndex + 1} · ${sp.name}' : 'Tree ${tree.index + 1} · ${sp.name}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF3D3226)),
              ),
              const SizedBox(height: 4),
              Text(
                tree == null
                    ? 'Still growing: ${garden.currentProgress} of ${garden.config.watersPerTree} waters so far.'
                    : 'Fully grown on ${_dayLabel(tree.finishedAt)}.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF85766A)),
              ),
              const SizedBox(height: 14),
              const Text('WHAT GREW IT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: Color(0xFFA69883))),
              const SizedBox(height: 8),
              if (byDay.isEmpty)
                const Text('Nothing yet. A check-in, a journal or something kind will water it.', style: TextStyle(fontSize: 13, color: Color(0xFF85766A)))
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in byDay.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 4),
                            child: Text(_dayLabel(DateTime.parse(entry.key)), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF3D3226))),
                          ),
                          for (final w in entry.value)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  const Icon(Icons.water_drop_rounded, size: 14, color: Color(0xFF5FB4E0)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_kindShort[w.event.kind]}${w.grown > 1 ? ' (${w.grown} waters)' : ''}',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6C5E50)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // closing the sheet flies the camera back out
    if (!_disposed) _world.goHome();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xFF5AAAE8),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onTapUp: (d) => _onTapUp(d.localPosition),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('forest-scene'),
                      painter: _WorldPainter(_world, repaint: _frame),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
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
                          Semantics(
                            label: _count == 1 ? '1 tree grown' : '$_count trees grown',
                            child: _CountBadge(key: const ValueKey('forest-count'), count: _count),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: top + 70,
                  child: AnimatedScale(
                    scale: _away ? 1 : 0,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    child: IgnorePointer(
                      ignoring: !_away,
                      child: Tooltip(
                        message: 'Back to my tree',
                        child: GestureDetector(
                          key: const ValueKey('forest-home'),
                          onTap: _home,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xE6FFFFFF),
                              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
                            ),
                            child: const Icon(Icons.park_rounded, color: Color(0xFF4F8A52), size: 26),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.paddingOf(context).bottom + 16,
                  child: IgnorePointer(
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
                                _stageNames[_stageIndex],
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
                                      color: i < _stageIndex ? const Color(0xFF9CCF6A) : const Color(0xFFE3D8BF),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              _caption.isEmpty ? 'Tap a tree to see what grew it. Pinch to zoom.' : _caption,
                              key: ValueKey(_caption),
                              style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: Color(0xFF85766A)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// How many trees have been grown: a round green badge with a leaf, and just the number.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9CCF6A), Color(0xFF5FA84A)]),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1)),
          ),
          const Positioned(
            top: -2,
            right: 0,
            child: Icon(Icons.eco_rounded, size: 20, color: Color(0xFFE8F6D2), shadows: [Shadow(color: Color(0x66000000), blurRadius: 3)]),
          ),
        ],
      ),
    );
  }
}

class _WorldPainter extends CustomPainter {
  _WorldPainter(this.world, {required Listenable repaint}) : super(repaint: repaint);

  final ForestWorld world;

  @override
  void paint(Canvas canvas, Size size) => world.paint(canvas, size);

  @override
  bool shouldRepaint(covariant _WorldPainter old) => false;
}
