import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/day_key.dart';
import '../../domain/forest/forest_garden.dart';
import '../../domain/forest/forest_sky.dart';
import '../../domain/forest/tree_geometry.dart';
import 'forest_controller.dart';
import 'forest_world.dart';

const _stageNames = ['A new seed', 'Seed planted', 'Sprouting', 'Seedling', 'Sapling', 'Young tree', 'Mature tree', 'Fully grown'];
const _kindText = {
  WaterKind.text: 'You did a check-in',
  WaterKind.journal: 'You recorded a journal',
  WaterKind.task: 'You did something kind for yourself',
  WaterKind.goal: 'You met a phone goal',
};
const _kindShort = {
  WaterKind.text: 'Check-in',
  WaterKind.journal: 'Voice or video journal',
  WaterKind.task: 'Self-care activity',
  WaterKind.goal: 'Phone goal',
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
  final _world = ForestWorld(weather: ForestWeather.partly);

  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// Everything that moves is read by the painter on every frame, so frames only repaint the scene, not the whole page.
  final _frame = ValueNotifier<int>(0);
  String _caption = '';
  Timer? _captionExpiry;
  int _stageIndex = 0;
  int _count = 0;
  bool _away = false;
  int? _focus;
  bool _storyVisible = false;
  bool _darkSky = false;
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
    final story = _focus != null && !_world.isFlying;
    final darkSky = _world.sky.night > 0.35 || _world.sky.weather.dim > 0.25;
    if (index != _stageIndex || away != _away || story != _storyVisible || darkSky != _darkSky) {
      setState(() {
        _stageIndex = index;
        _away = away;
        _storyVisible = story;
        _darkSky = darkSky;
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _captionExpiry?.cancel();
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

  void _say(String text, {bool settle = false}) {
    if (_disposed) return;
    _captionExpiry?.cancel();
    setState(() => _caption = text);
    if (settle) {
      _captionExpiry = Timer(const Duration(seconds: 3), () {
        setState(() => _caption = '');
      });
    }
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
            _say(_stageLines[now]);
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
    _say(_settled[widget.controller.now.millisecond % _settled.length], settle: true);
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
    if (_focus != null) _home();
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
    _world.beginGesture();
    if (_focus != null) setState(() { _focus = null; _storyVisible = false; });
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final (scale, _) = _world.fit(_size);
    final (lo, hi) = _world.camBounds;
    final raw = _world.camX - d.focalPointDelta.dx / (scale * _world.zoom);
    _world.camX = lerp(raw.clamp(lo, hi), raw, 0.4);
    if (d.pointerCount > 1) _world.zoom = (_startZoom * d.scale).clamp(0.8, 4.0);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final (scale, _) = _world.fit(_size);
    _world.endGesture((-d.velocity.pixelsPerSecond.dx / (scale * _world.zoom) * 0.5).clamp(-500, 500));
  }

  double get _panelWidth => math.min(_size.width * 0.40, 272);
  static const _panelRight = 12.0;
  static const _panelGap = 9.0;

  void _onTapUp(Offset local) {
    final (scale, dy) = _world.fit(_size);
    final hit = _world.hitTest(Offset(local.dx / scale, local.dy / scale - dy));
    if (hit == null) {
      if (_focus != null) _home();
      return;
    }
    final index = hit.finishedIndex;
    if (_focus == index) return;
    _world.focusOnTree(index, _size, _size.width - _panelWidth - _panelRight - _panelGap);
    setState(() {
      _focus = index;
      _storyVisible = false;
    });
  }

  void _home() {
    _world.goHome();
    setState(() {
      _focus = null;
      _storyVisible = false;
    });
  }

  Widget _breakdown(FinishedTree? tree) {
    final garden = _shown;
    final species = tree?.species ?? garden.currentSpecies;
    final index = tree?.index ?? garden.currentIndex;
    final byDay = <String, List<AppliedWater>>{};
    for (final w in tree?.waters ?? garden.currentWaters) {
      if (w.grown > 0) byDay.putIfAbsent(dayKey(w.event.at), () => []).add(w);
    }
    const ink = Color(0xFFFFFDF3), soft = Color(0xFFE5EDD8), line = Color(0x47FFFFFF);
    const detail = TextStyle(fontSize: 12, height: 1.3, color: soft);
    return RepaintBoundary(
      child: DecoratedBox(
        key: const ValueKey('tree-breakdown'),
        decoration: BoxDecoration(
          color: const Color(0xCC1A3028),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x70FFFFFF)),
          boxShadow: const [BoxShadow(color: Color(0x44202F24), blurRadius: 12, offset: Offset(0, 5))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('WHAT GREW IT', style: TextStyle(fontSize: 9, letterSpacing: 1.25, fontWeight: FontWeight.w800, color: soft)),
                const SizedBox(height: 4),
                Text('Tree ${index + 1} · ${treeSpecies[species].name}', style: const TextStyle(fontSize: 16, height: 1.14, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 5),
                Text(tree == null
                    ? '${garden.currentProgress} of ${garden.config.watersPerTree} waters'
                    : 'Fully grown · ${_dayLabel(tree.finishedAt)}', style: detail),
                const SizedBox(height: 7),
                if (byDay.isEmpty)
                  const Text('A check-in, a journal or something kind will water it.', style: detail)
                else
                  for (final entry in byDay.entries) ...[
                    const Divider(color: line, height: 12),
                    Text(_dayLabel(DateTime.parse(entry.key)), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 4),
                    for (final water in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(_kindShort[water.event.kind]!, style: detail)),
                            const SizedBox(width: 5),
                            Text('+${water.grown}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFD7EAB4))),
                          ],
                        ),
                      ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final overlay = (_darkSky ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      systemNavigationBarColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF5AAAE8),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          final storyTop = math.max(top + 108, _size.height * 0.33);
          final focus = _focus;
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
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: overlay,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('forest-scene'),
                        painter: _WorldPainter(_world, repaint: _frame),
                        willChange: true,
                      ),
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
                if (_away || focus != null)
                  Positioned(
                    right: 19,
                    top: top + 70,
                    child: Material(
                      color: const Color(0xE6FFFFFF),
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: const ValueKey('forest-home'),
                        tooltip: 'Back to forest',
                        onPressed: _home,
                        constraints: const BoxConstraints.tightFor(width: 46, height: 46),
                        icon: const Icon(Icons.park_rounded, color: Color(0xFF4F8A52), size: 26),
                      ),
                    ),
                  ),
                if (focus != null)
                  Positioned(
                    top: storyTop,
                    right: _panelRight,
                    width: _panelWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: math.max(0, math.min(_size.height * 0.55, _size.height - storyTop - bottom - 14))),
                      child: AnimatedSwitcher(
                        duration: _world.reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
                        child: _storyVisible ? _breakdown(focus < 0 ? null : _world.finished[focus]) : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                if (focus == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: bottom + 16,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: _world.reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
                            child: _caption.isEmpty
                                ? const SizedBox.shrink()
                                : Padding(
                                    key: ValueKey(_caption),
                                    padding: const EdgeInsets.only(bottom: 9),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0xE6FBF9E9),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 280),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          child: Semantics(
                                            key: const ValueKey('forest-watering-caption'),
                                            liveRegion: true,
                                            child: Text(
                                              _caption,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 12.5, height: 1.25, color: Color(0xFF314838)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          _GrowthStamp(stage: _stageIndex),
                        ],
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

class _GrowthStamp extends StatelessWidget {
  const _GrowthStamp({required this.stage});

  final int stage;

  @override
  Widget build(BuildContext context) {
    final name = _stageNames[stage];
    return Semantics(
      label: '$name, growth step $stage of 7',
      excludeSemantics: true,
      child: DecoratedBox(
        key: const ValueKey('forest-growth-stamp'),
        decoration: BoxDecoration(
          color: const Color(0xEEFBF9E9),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xA8FFFFF8)),
          boxShadow: const [BoxShadow(color: Color(0x252E4828), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFFE7EDD6), shape: BoxShape.circle),
                child: Padding(
                  padding: const EdgeInsets.all(5.5),
                  child: CustomPaint(painter: _GrowthMarkPainter(stage), size: const Size.square(24)),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  name,
                  key: const ValueKey('forest-stage'),
                  style: const TextStyle(fontFamily: 'serif', fontSize: 16, height: 1.15, fontWeight: FontWeight.w600, color: Color(0xFF314838)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrowthMarkPainter extends CustomPainter {
  const _GrowthMarkPainter(this.stage);

  final int stage;

  // The approved 24-unit marks, from seed through the mature canopy.
  static final _marks = <Path>[
    Path()
      ..moveTo(10, 17)
      ..cubicTo(7, 13, 12, 7, 18, 6)
      ..cubicTo(18, 12, 15, 18, 10, 17)
      ..close()
      ..moveTo(11, 16)
      ..lineTo(16, 9),
    Path()
      ..moveTo(5, 18)
      ..cubicTo(10, 15, 14, 15, 19, 18)
      ..moveTo(10, 13)
      ..cubicTo(10, 10, 12, 8, 15, 8)
      ..cubicTo(15, 10, 14, 12, 12, 13),
    Path()
      ..moveTo(12, 20)
      ..lineTo(12, 12)
      ..moveTo(12, 14)
      ..cubicTo(8, 14, 5, 11, 5, 8)
      ..cubicTo(9, 8, 12, 10, 12, 14)
      ..close()
      ..moveTo(12, 12)
      ..cubicTo(12, 9, 14, 7, 18, 7)
      ..cubicTo(18, 10, 16, 12, 12, 12)
      ..close(),
    Path()
      ..moveTo(12, 21)
      ..lineTo(12, 7)
      ..moveTo(12, 18)
      ..cubicTo(7, 18, 5, 15, 5, 12)
      ..cubicTo(9, 12, 11, 14, 12, 17)
      ..moveTo(12, 14)
      ..cubicTo(13, 10, 15, 8, 19, 8)
      ..cubicTo(18, 12, 16, 14, 12, 14)
      ..close()
      ..moveTo(12, 9)
      ..cubicTo(9, 8, 9, 5, 11, 3)
      ..cubicTo(13, 5, 13, 7, 12, 9)
      ..close(),
    Path()
      ..moveTo(7, 21)
      ..lineTo(17, 21)
      ..moveTo(12, 21)
      ..lineTo(12, 14)
      ..moveTo(7, 10)
      ..lineTo(12, 15)
      ..lineTo(17, 9)
      ..moveTo(7, 10)
      ..cubicTo(4, 10, 3, 8, 3, 6)
      ..cubicTo(6, 5, 8, 7, 7, 10)
      ..close()
      ..moveTo(17, 9)
      ..cubicTo(17, 6, 19, 4, 22, 5)
      ..cubicTo(22, 7, 20, 9, 17, 9)
      ..close(),
    Path()
      ..moveTo(7, 21)
      ..lineTo(17, 21)
      ..moveTo(12, 21)
      ..lineTo(12, 14)
      ..moveTo(7, 11)
      ..lineTo(12, 15)
      ..lineTo(17, 10)
      ..moveTo(7, 12)
      ..cubicTo(2.8, 12, 2.8, 6, 7, 6)
      ..cubicTo(8, 1, 14, 1, 15, 4)
      ..cubicTo(18, 2, 22, 5.2, 20, 9)
      ..cubicTo(19, 11, 17, 12, 15, 11)
      ..cubicTo(13, 13, 10, 13, 7, 12)
      ..close(),
    Path()
      ..moveTo(6, 21)
      ..lineTo(18, 21)
      ..moveTo(12, 21)
      ..lineTo(12, 13)
      ..moveTo(8, 13)
      ..lineTo(12, 17)
      ..lineTo(16, 13)
      ..moveTo(6, 14)
      ..cubicTo(1, 14, 2, 8, 5, 8)
      ..cubicTo(5, 4, 9, 3, 12, 5)
      ..cubicTo(14, 2, 19, 4, 19, 7)
      ..cubicTo(23, 8, 23, 14, 19, 14)
      ..cubicTo(17, 16, 14, 16, 12, 14)
      ..cubicTo(10, 16, 7, 16, 6, 14)
      ..close(),
  ];

  static final _shine = Path()
    ..moveTo(8, 7)
    ..lineTo(8, 11)
    ..moveTo(6, 9)
    ..lineTo(10, 9)
    ..moveTo(16, 6)
    ..lineTo(16, 10)
    ..moveTo(14, 8)
    ..lineTo(18, 8);

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = const Color(0xFF436A43)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_marks[math.min(stage, _marks.length - 1)], brush);
    if (stage == 7) canvas.drawPath(_shine, brush..color = const Color(0xFFBD7D39));
  }

  @override
  bool shouldRepaint(_GrowthMarkPainter oldDelegate) => oldDelegate.stage != stage;
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
