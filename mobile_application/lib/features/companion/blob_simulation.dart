import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Which physical condition the blob is currently in.
///
/// These are conditions, not timelines. Nothing here is a duration that gets
/// played and then reset; [charged] is simply "the radius is past the charge
/// threshold", and the only timed state is [bursting], which is a particle
/// effect rather than a tween on the body.
enum BlobState {
  /// Resting and drifting on its own.
  idle,

  /// A finger is on it and the skin is being stretched toward that finger.
  pulling,

  /// Held long enough to be filling with air. The radius is growing.
  inflating,

  /// Fully inflated and past the charge radius, so it is shaking.
  charged,

  /// Popped. The body is gone and the droplets are flying.
  bursting,

  /// A fresh small ring, pushing itself back out to full size.
  regrowing,
}

/// A deformable closed ring of points, simulated rather than keyframed.
///
/// This is the whole reason the blob can do what it does. Every visible
/// behaviour is a consequence of the same solver, with no per-behaviour
/// animation code anywhere:
///
///   * pulled          a soft force on one point; the ring deforms locally
///   * stays put       a weaker spring on the centroid out-muscles nothing,
///                     so you get a teat rather than a translation
///   * springs back    the force stops and stored constraint energy settles it
///   * inflates        the pressure target rises and the ring really expands
///   * deflates        the pressure target falls and the ring really shrinks
///   * pops            the ring is discarded
///   * regrows         the re-seeded ring is under-inflated against the
///                     unchanged pressure target, so it pushes itself out
///
/// That last line is the important one. Regrowth is not a separate animation. It
/// is this solver recovering from a smaller initial state, which means it cannot
/// drift out of sync with the physics, because it *is* the physics.
///
/// Deliberately free of Flutter widget code so it can be tested headlessly at a
/// fixed timestep. The widget owns a ticker and calls [step]; the painter reads
/// the exposed fields. Nothing here paints and nothing here rebuilds widgets.
///
/// ## Units
///
/// Accelerations are expressed in **pixels per step squared**, not in physical
/// units. Under a fixed timestep that is a constant factor away from a true
/// acceleration, and keeping it in pixels means every coefficient below can be
/// tuned by reading what it does to the shape, without a mental conversion.
/// A coefficient of 1.0 displaces a point by one pixel in a single step.
class BlobSimulation extends ChangeNotifier {
  BlobSimulation({
    required this.restRadius,
    this.pointCount = 44,
  }) : assert(pointCount >= 8, 'too few points to make a ring') {
    _fillBuffers();
    _seedRing(1.0);
  }

  // ---------------------------------------------------------------- geometry

  /// Radius of the ring when nothing is touching it, in pixels.
  final double restRadius;

  /// Number of points around the ring. Higher is a smoother skin and more cost;
  /// the constraint solve is O(pointCount) per iteration, so this is the one
  /// number that actually affects the frame budget.
  final int pointCount;

  // ------------------------------------------------------------ tunables

  /// Simulation rate. Half the display rate, so the solver gets two steps per
  /// rendered frame. The blob is stiff enough that a single 60 Hz step makes
  /// the wobble visibly coarse.
  static const double fixedDt = 1.0 / 120.0;

  /// Ceiling on steps consumed per frame. Past this the remainder is dropped:
  /// slow motion under load is the correct failure, a frozen app is not. Also
  /// the spiral-of-death guard, since a slow frame otherwise queues more work
  /// and makes the next frame slower still.
  static const int maxSubsteps = 4;

  /// How hard the skin resists being stretched, per constraint iteration.
  /// Low is very jelly. This is the main character control.
  static const double edgeStiffness = 0.55;

  /// Second-neighbour constraint. Stops the skin creasing into corners when it
  /// is pulled hard, without making it rigid.
  static const double bendStiffness = 0.18;

  /// Internal pressure. The defence against the ring folding flat, and the
  /// force that drives both inflation and regrowth.
  static const double pressureStiffness = 0.06;

  /// Centroid spring, per step.
  ///
  /// Deliberately much weaker than [grabStiffness]. That imbalance is the whole
  /// reason pulling stretches the blob instead of sliding it around the screen.
  static const double anchorStiffness = 0.010;

  /// Velocity bleed per step. Below 1 so it is always bleeding; the wobble
  /// settles instead of ringing forever.
  static const double damping = 0.982;

  /// Constraint passes per step. Four is enough that the edges hold under a hard
  /// pull without visibly lagging the finger.
  static const int constraintIterations = 4;

  // ---------------------------------------------------------------- motion

  /// How far the blob is allowed to wander from its resting spot, in pixels.
  /// Small and bounded on purpose: it floats, but it stays anchored to the page.
  static const double wanderAmplitude = 14.0;

  /// Drift speed, radians per second.
  ///
  /// The wander is a sum of sines at mutually irrational frequencies. An
  /// irrational ratio never realigns, so the path has no period and the motion
  /// can never visibly restart. A single sine here would be a loop, which is
  /// exactly the defect this rewrite exists to remove.
  static const double wanderSpeed = 0.06;

  // ---------------------------------------------------------------- touch

  /// Fraction of the remaining distance to the finger closed per solver iteration.
  ///
  /// Not a force. See [_solveAnchor], where this is applied as a bounded
  /// positional correction.
  static const double grabStiffness = 0.35;

  /// How far past the bubble's own edge the grabbed point may be dragged, as a
  /// fraction of [restRadius]. A clamp rather than a spring, so a hard fling
  /// cannot tear the surface and leave a permanently ragged edge.
  ///
  /// Small on purpose. This is the reach of the teat the finger pulls out, and
  /// at 0.85 the point could travel further than the bubble is wide, which reads
  /// as the shape coming apart rather than as stretch.
  static const double grabRadiusLimit = 0.55;

/// Seconds of sustained over-pressure needed to pop.
  ///
  /// Kept comfortably longer than the fill takes to reach [chargeRadius], so a
  /// deliberate hold passes through the whole shaking phase before it bursts. Any
  /// shorter and the pop lands so quickly after the shake starts that there is
  /// no chance to see it, which would make the shaking pointless.
  static const double chargeDuration = 1.5;

  // --------------------------------------------------------------- charging

  /// Radius, as a multiple of rest, at which the shake begins.
  static const double chargeRadius = 1.55;

  /// Radius, as a multiple of rest, that a fully pressed hold tops out at.
  static const double inflateRadius = 1.9;

  

  /// Wobble amplitude once charged, in pixels.
  static const double shakeAmplitude = 2.4;

  /// How small a fresh ring starts after a pop, as a fraction of rest. Small
  /// enough to read as a new bubble, not a stutter.
  static const double respawnScale = 0.35;

  // ----------------------------------------------------------------- state

  final List<Offset> _points = [];
  final List<Offset> _previous = [];

  final List<double> _restEdges = [];
  final List<double> _restSkip = [];

  /// Fills the four ring buffers to their final length.
  ///
  /// Sized once rather than on every seed, because the ring is re-seeded on
  /// every pop and reallocating four lists each time would churn the heap
  /// inside the frame the burst is being drawn.
  void _fillBuffers() {
    for (var i = 0; i < pointCount; i++) {
      _points.add(Offset.zero);
      _previous.add(Offset.zero);
      _restEdges.add(0);
      _restSkip.add(0);
    }
  }

  /// Droplets thrown off by the last pop. Purely visual, but they are integrated
  /// here because they need the same clock as everything else.
  final List<_Droplet> _droplets = [];

  BlobState _state = BlobState.idle;

  /// Where the blob is trying to be. Moves on the wander path; the centroid is
  /// sprung toward it.
  Offset _anchor = Offset.zero;

  /// Monotonic seconds since construction. Never wrapped, never reset, so no
  /// derived quantity can discontinuously jump the way a looping phase does.
  double _time = 0.0;

  /// Accumulated over-pressure, in seconds. Drives the pop.
  double _charge = 0.0;

  bool _grabbed = false;
  int _grabIndex = 0;
  Offset _grabTarget = Offset.zero;

  bool _pressHeld = false;

  /// How big the bubble is *trying* to be, as a multiple of rest.
  ///
  /// Deliberately separate from [inflation], which is what the ring has actually
  /// achieved. Conflating the two is what stops inflation from working at all:
  /// if the pressure target tracked the measured radius then a ring sitting at
  /// its own target would feel no net force and could never grow.
  ///
  /// Both the skin's natural circumference and the enclosed-area target are
  /// driven from this one number, so the bubble fills the way a balloon does.
  /// There is no separate "grow" animation anywhere.
  double _targetScale = 1.0;

  // Outward-facing values the painter and widget read.

  /// The live ring, in local coordinates around the origin. The widget decides
  /// where that origin sits on screen.
  List<Offset> get points => List<Offset>.unmodifiable(_points);

  /// Droplets currently flying, for the painter.
  ///
  /// Pairs of position and opacity. Opacity is carried alongside rather than
  /// recomputed by the painter, because the fade is a function of age and the
  /// painter should not have to know what age means.
  List<({Offset position, double opacity})> get droplets =>
      List<({Offset position, double opacity})>.unmodifiable(
        _droplets.map((d) => (position: d.position, opacity: d.opacity)),
      );

  /// Radius as a multiple of rest. The painter scales its colour layers inward by
  /// this so every layer keeps tracking the same deforming outline.
  double get radiusScale => inflation;

  BlobState get state => _state;

  /// What the ring has actually achieved, as a multiple of rest radius. 1.0 is
  /// resting, ~1.9 fully inflated.
  ///
  /// Measured from the geometry every step rather than assumed from the target,
  /// so the charge threshold triggers on real shape and not on the intention.
  double get inflation {
    var sum = 0.0;
    for (final p in _points) {
      sum += p.distance;
    }
    return sum / _points.length / restRadius;
  }

  /// How close the pop is, 0 to 1. Zero unless inflated past [chargeRadius].
  ///
  /// Exposed so the rim can brighten as pressure builds. Hiding this would make
  /// the pop feel arbitrary.
  double get chargeFraction => (_charge / chargeDuration).clamp(0.0, 1.0);

  /// Signed area of the ring, for the painter's internal density shading.
  double enclosedArea() {
    var sum = 0.0;
    for (var i = 0; i < pointCount; i++) {
      final a = _points[i];
      final b = _points[(i + 1) % pointCount];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum / 2;
  }

  /// The area the bubble is trying to enclose: a circle at the *target* radius.
  ///
  /// Normalising pressure against this rather than the measured area is what
  /// drives both inflation and regrowth, because a ring that is smaller than its
  /// target has a genuine deficit to close.
  double get _targetArea =>
      math.pi * restRadius * restRadius * _targetScale * _targetScale;

  // ------------------------------------------------------------------ input

  /// A finger has landed on the blob at [local] and is moving it.
  void grab(Offset local) {
    if (_state == BlobState.bursting) return;
    _grabbed = true;
    _grabTarget = local;
    _recomputeGrabIndex();
    // A touch that begins inflating is already inflating. Deciding purely from
    // the gesture meant a finger that landed and held went through a frame of
    // "pulling" before switching, which read as a hitch in the fill.
    _state = _pressHeld ? _inflatedState() : BlobState.pulling;
    notifyListeners();
  }

  /// The finger has moved to [local].
  void dragTo(Offset local) {
    if (!_grabbed || _state == BlobState.bursting) return;
    _grabTarget = local;
    _recomputeGrabIndex();
  }

  /// The finger has lifted.
  void release() {
    _grabbed = false;
    _pressHeld = false;
    // Not snapping the radius down is what makes letting go read as air
    // escaping; the target decays in step() and the ring shrinks to meet it.
    _state = inflation > 1.02 ? BlobState.charged : BlobState.idle;
    notifyListeners();
  }

  /// The hold has passed the long-press threshold, so the blob starts filling
  /// with air. Grabbing stays live, so an inflated bubble can still be yanked.
  void beginInflate() {
    if (_state == BlobState.bursting) return;
    _pressHeld = true;
    _state = _inflatedState();
    notifyListeners();
  }

  // ------------------------------------------------------------------- step

  /// Feeds the simulation the wall-clock time since the last call, and it
  /// consumes as many fixed steps as that covers.
  ///
  /// Split from [step] so the widget owns the clock. The simulation has no
  /// opinion about frame rate, and the widget has no opinion about physics.
  void advance(double frameSeconds) {
    // A frame that arrives very late is cut down to something sane rather than
    // integrated whole: a long hitch would otherwise arrive as one enormous
    // step, and a stiff solver answers a large step by exploding.
    final capped = frameSeconds.clamp(0.0, 0.25);
    _carry = math.min(_carry + capped, _maxCarry);
    while (_carry >= fixedDt) {
      step();
      _carry -= fixedDt;
    }
  }

  /// Unconsumed time carried into the next frame.
  double _carry = 0;

  /// Ceiling on carried time. A backlog that grows without limit is the spiral
  /// of death: a slow frame queues more work, which makes the next frame slower
  /// still. Dropping the excess gives slow motion under load instead.
  static const double _maxCarry = fixedDt * maxSubsteps;

  /// Advances the simulation by exactly one fixed step.
  ///
  /// Fixed-step on purpose. A stiff constraint solver run on a variable dt feels
  /// twice as stiff at 120 Hz as at 60 Hz, and can detonate on a single dropped
  /// frame. Determinism also makes this testable: the same input sequence
  /// produces the same output, every run.
  void step() {
    _time += fixedDt;

    _updateAnchor();

    // Air goes in while held and leaks out once released. Asymmetric rates, so
    // the release is slower than the fill and reads as a sigh rather than a
    // snap. This is a *target*, never an assigned radius: the ring is still only
    // pulled toward it by pressure, so it always arrives by physics.
    final wanted = _pressHeld ? inflateRadius : 1.0;
    final rate = switch (_state) {
      // A new bubble opens faster than a held one deflates. It is the
      // reassurance beat after the pop, so it should feel immediate rather than
      // like waiting for something to settle.
      BlobState.regrowing => 3.4,
      _ => _pressHeld ? 2.4 : 1.7,
    };
    _targetScale += (wanted - _targetScale) * (1 - math.exp(-rate * fixedDt));

    _updateCharge();

    // The state follows the measured shape, not the gesture. Without this the
    // blob would sit reporting "inflating" for a whole hold and never register
    // that it had reached the pressure to shake.
    if (_state != BlobState.bursting && _state != BlobState.regrowing) {
      _state = _pressHeld
          ? (inflation > chargeRadius ? BlobState.charged : BlobState.inflating)
          : (inflation > 1.02 ? BlobState.charged : BlobState.idle);
      if (!_pressHeld && !_grabbed) _state = BlobState.idle;
    }

    if (_state == BlobState.bursting) {
      _stepDroplets();
      notifyListeners();
      return;
    }

    _integrate();
    for (var i = 0; i < constraintIterations; i++) {
      _solveEdges();
      _solveBending();
    }
    _solveAnchor();
    _clampGrabbed();

    if (_state == BlobState.regrowing && inflation > 0.985) {
      // Back to normal size by pushing itself out, not by an animation
      // finishing. Only now does it become interactive again.
      _state = BlobState.idle;
    }

    notifyListeners();
  }

  // ------------------------------------------------------------- internals

  /// Moves the resting anchor along a non-repeating path.
  void _updateAnchor() {
    final t = _time * wanderSpeed;
    // sqrt(2) and sqrt(3) against each other: no shared period, so the
    // combined path never closes.
    final x = math.sin(t) * 0.62 + math.sin(t * math.sqrt2) * 0.38;
    final y =
        math.cos(t * 0.83) * 0.55 + math.sin(t * math.sqrt(3)) * 0.30;
    _anchor = Offset(x, y) * wanderAmplitude;
  }

  /// Accumulates over-pressure time and pops when it runs out.
  ///
  /// Reads the measured [inflation], so the pop is a consequence of the shape
  /// the user actually produced rather than of how long they happened to hold.
  void _updateCharge() {
    if (_pressHeld && inflation > chargeRadius) {
      _charge += fixedDt;
      if (_charge >= chargeDuration) {
        _burst();
      }
    } else if (!_pressHeld) {
      // Leaks away while deflated, so a second hold does not resume a charge
      // the user never finished.
      _charge = math.max(0.0, _charge - fixedDt * 1.4);
    }
  }

  BlobState _inflatedState() {
    return inflation > chargeRadius ? BlobState.charged : BlobState.inflating;
  }

  /// Discards the ring and re-seeds a small one.
  ///
  /// Rest edge lengths and the pressure target are deliberately left at their
  /// resting values, which is what makes the new ring inflate itself back to
  /// full size.
  void _burst() {
    _droplets
      ..clear()
      ..addAll(_spawnDroplets());

    _seedRing(respawnScale);
    _charge = 0;
    _pressHeld = false;
    _grabbed = false;
    _state = BlobState.regrowing;

    // The target starts where the new ring starts, not at full size.
    //
    // Setting it straight to 1.0 asks 44 edges to each jump from 2.9 px to
    // 8.3 px within four solver iterations, and a ring that small cannot absorb
    // that: it buckles, folds through itself, and settles inverted and collapsed
    // (signed area goes negative and stays there). Starting the target at the
    // seed's own size and letting it walk back up means the rest circumference is
    // always only just larger than the current one, so the ring opens as a
    // circle instead of collapsing.
    //
    // The ring still reaches full size because the target does, and the ring
    // still gets there by being pushed by pressure and pulled by skin tension
    // rather than by anything assigning its radius.
    _targetScale = respawnScale;
  }

  /// Rebuilds the ring as a circle of [scale] times the resting radius, with no
  /// stored velocity so it does not inherit the old ring's motion.
  void _seedRing(double scale) {
    final radius = restRadius * scale;
    for (var i = 0; i < pointCount; i++) {
      final a = (i / pointCount) * 2 * math.pi;
      final p = Offset(math.cos(a) * radius, math.sin(a) * radius);
      _points[i] = p;
      _previous[i] = p;
    }
    // Natural lengths captured once, at full size, and never re-derived from
    // the seed. They are the skin's *unstretched* circumference, rescaled at
    // solve time by the current target — the way a balloon's skin stretches as
    // it takes air. Deriving them from the seed instead would mean a re-seeded
    // ring was already at its own rest length and had nothing to grow into.
    // Natural lengths are captured exactly once, from the full-size seed, and
    // never re-derived. Re-deriving them here on every pop meant the fresh
    // ring was handed a rest circumference sized to itself, so it sat already
    // at its own rest length with nothing to grow into, and it stayed a small
    // bubble forever.
    if (_sized) return;
    _sized = true;
    for (var i = 0; i < pointCount; i++) {
      _restEdges[i] =
          (_points[(i + 1) % pointCount] - _points[i]).distance;
      _restSkip[i] =
          (_points[(i + 2) % pointCount] - _points[i]).distance;
    }
  }

  /// Guards the one-time capture of the skin's natural lengths.
  bool _sized = false;

  /// Applies pressure, anchor, shake and grab, then advances the ring one step.
  void _integrate() {
    // Signed the same way as the ring's winding so an inverted ring pushes
    // inward rather than exploding outward.
    final signed = enclosedArea();
    final winding = signed < 0 ? -1.0 : 1.0;

    // Pressure, as the fractional shortfall against the target area. Normalising
    // by the target rather than the measured area keeps the coefficient
    // independent of the blob's size on screen.
    final deficit = (_targetArea - signed.abs()) / _targetArea;
    final pressure = pressureStiffness * deficit * winding;

    final shaking = _state == BlobState.charged;
    final shakeX = shaking
        ? math.sin(_time * 41.0) * shakeAmplitude
        : 0.0;
    final shakeY = shaking
        ? math.sin(_time * 37.0 + 1.1) * shakeAmplitude
        : 0.0;

    for (var i = 0; i < pointCount; i++) {
      final p = _points[i];
      final prev = _previous[i];

      var vx = (p.dx - prev.dx) * damping;
      var vy = (p.dy - prev.dy) * damping;

      // Pressure along the outward normal of this edge, approximated by the
      // perpendicular of the tangent to the neighbouring points.
      final a = _points[(i - 1 + pointCount) % pointCount];
      final b = _points[(i + 1) % pointCount];
      final tangent = b - a;
      final len = tangent.distance;
      var nx = 0.0;
      var ny = 0.0;
      if (len > 1e-6) {
        nx = tangent.dy / len * winding;
        ny = -tangent.dx / len * winding;
      }

      // Pressure and shake only. Neither the anchor nor the grab belongs here.
      //
      // The anchor is a centripetal force if applied per point, so it crushes
      // the ring toward its own centre instead of moving the blob; it is a
      // whole-ring translation in _solveAnchor.
      //
      // The grab is worse as a force. The gap between finger and skin can be
      // well over 100 px, and multiplying that by any stiffness large enough to
      // feel responsive produces an acceleration the constraint solver cannot
      // keep up with. The grabbed point rips away, drags its neighbours with
      // it, and the whole ring contracts instead of forming a teat.
      var ax = nx * pressure + shakeX;
      var ay = ny * pressure + shakeY;

      _previous[i] = p;
      _points[i] = Offset(
        p.dx + vx + ax * fixedDt * fixedDt,
        p.dy + vy + ay * fixedDt * fixedDt,
      );
    }
  }

  /// Pulls each edge back toward its rest length, scaled by the target.
  void _solveEdges() {
    for (var i = 0; i < pointCount; i++) {
      final j = (i + 1) % pointCount;
      _constrain(i, j, _restEdges[i] * _targetScale, edgeStiffness);
    }
  }

  /// Pulls each second-neighbour pair together, which is what keeps the skin
  /// smooth when it is stretched hard instead of kinking.
  void _solveBending() {
    for (var i = 0; i < pointCount; i++) {
      final j = (i + 2) % pointCount;
      _constrain(i, j, _restSkip[i] * _targetScale, bendStiffness);
    }
  }

  /// One distance constraint, applied symmetrically so it adds no net momentum.
  void _constrain(int i, int j, double rest, double stiffness) {
    final a = _points[i];
    final b = _points[j];
    final d = b - a;
    final dist = d.distance;
    if (dist < 1e-6) return;
    final correction = (dist - rest) / dist * stiffness;
    final shift = d * correction;
    _points[i] = a + shift;
    _points[j] = b - shift;
  }

  /// Springs the ring's centroid back toward the drifting anchor.
  ///
  /// This is what makes the blob anchored rather than free-floating. It is
  /// applied as a whole-ring translation after the shape constraints, so it
  /// cannot fight them into a shear.
  void _solveAnchor() {
    final c = _centroid();
    final shift = (_anchor - c) * anchorStiffness;
    for (var i = 0; i < pointCount; i++) {
      _points[i] = _points[i] + shift;
    }

    // The grab, applied here as a bounded correction rather than as a force in
    // _integrate.
    //
    // This is the difference between stretching the blob and tearing it. A force
    // scaled by the finger-to-skin gap grows without limit as the finger moves
    // away, and a stiff solver handed a very large step responds by flinging
    // points: the grabbed point rips off, its neighbours are dragged inside it,
    // and the ring shrinks instead of growing a teat.
    //
    // Moving a fixed fraction of the remaining distance per iteration instead
    // bounds the correction by construction. The finger pulls as hard as it
    // likes, the skin just follows at the solver's own pace, and the edges stay
    // taut between them. This is the standard way to drag a soft body: control
    // the constraint, not the forces.
    if (_grabbed) {
      // The target is bounded, not just the resulting point.
      //
      // Clamping the point afterwards is too late: four iterations of a 0.35
      // move toward a finger 1400 px away throw it most of the way there before
      // anything gets a chance to intervene, dragging its neighbours inside it on
      // the way. Bounding the target means the solver is only ever asked to move
      // the point somewhere it could legitimately be.
      final reach = restRadius * inflation;
      final maxReach = reach + restRadius * grabRadiusLimit;
      var target = _grabTarget;
      final from = _points[_grabIndex];
      final delta = target - from;
      if (delta.distance > maxReach) {
        target = from + delta * (maxReach / delta.distance);
      }
      _points[_grabIndex] =
          Offset.lerp(_points[_grabIndex], target, grabStiffness)!;
    }
  }

  /// Caps how far the grabbed point may leave the blob, so a fast fling cannot
  /// tear a ragged notch that never heals.
  /// Caps the total distance the grabbed point may sit from the ring's centre.
  ///
  /// A backstop only. The real bound is applied to the grab *target* inside
  /// [_solveAnchor], before the solver ever sees it; this catches the case where
  /// pressure or a fling carries the point outward past the target's own reach.
  ///
  /// Scaled by the bubble's measured size, not its resting size, so an inflated
  /// bubble is not yanked back down to rest while being pulled.
  void _clampGrabbed() {
    if (!_grabbed) return;
    final limit = restRadius * (inflation + grabRadiusLimit);
    final p = _points[_grabIndex];
    final d = p.distance;
    if (d > limit) {
      _points[_grabIndex] = p * (limit / d);
    }
  }

  Offset _centroid() {
    var x = 0.0;
    var y = 0.0;
    for (final p in _points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pointCount, y / pointCount);
  }

  /// Re-targets the grab at whichever point is currently nearest the finger, so
  /// sliding along the surface hands the pull from point to point the way it
  /// would on a real membrane.
  void _recomputeGrabIndex() {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < pointCount; i++) {
      final d = (_points[i] - _grabTarget).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    _grabIndex = best;
  }

  /// Throws droplets outward from the ring that just popped.
  ///
  /// Directions come from a fixed-seed LCG rather than [math.Random] so the
  /// burst is reproducible and a determinism test can assert on it.
  List<_Droplet> _spawnDroplets() {
    final out = <_Droplet>[];
    var seed = 0x2F6E2B1;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return seed / 0x7FFFFFFF;
    }

    for (var i = 0; i < 14; i++) {
      final src = _points[(i * 3) % pointCount];
      final angle = (i / 14) * 2 * math.pi + next() * 0.4;
      final speed = 0.9 + next() * 1.5;
      out.add(
        _Droplet(
          position: src,
          velocity: Offset(math.cos(angle), math.sin(angle)) * speed,
          size: restRadius * (0.05 + next() * 0.06),
          age: 0.0,
        ),
      );
    }
    return out;
  }

  void _stepDroplets() {
    for (var i = _droplets.length - 1; i >= 0; i--) {
      final d = _droplets[i];
      d.age += fixedDt;
      if (d.age > 0.9) {
        _droplets.removeAt(i);
        continue;
      }
      // Drag-damped outward drift. No gravity: it is a bubble in nothing, and
      // gravity here would read as the droplets falling out of the blob.
      d.velocity = d.velocity * 0.94;
      d.position = d.position + d.velocity * fixedDt * 60;
    }
  }
}

/// One droplet thrown off by a pop.
class _Droplet {
  _Droplet({
    required this.position,
    required this.velocity,
    required this.size,
    required this.age,
  });

  Offset position;
  Offset velocity;
  double size;
  double age;

  /// 1 at birth, 0 by the time it is culled.
  double get opacity => (1.0 - age / 0.9).clamp(0.0, 1.0);
}