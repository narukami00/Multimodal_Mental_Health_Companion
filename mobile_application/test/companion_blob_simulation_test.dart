import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/companion/blob_simulation.dart';

/// Runs the simulation forward by [seconds] of simulated time.
void _advance(BlobSimulation sim, double seconds) {
  final steps = (seconds / BlobSimulation.fixedDt).round();
  for (var i = 0; i < steps; i++) {
    sim.step();
  }
}

/// Runs forward until [when] holds, or fails after [limit] seconds.
///
/// Used wherever a test needs to observe a *transitional* state. Advancing a
/// fixed long enough to guarantee the pop also guarantees stepping past it, so
/// these assertions would otherwise race the very thing they are checking for.
void _advanceUntil(
  BlobSimulation sim,
  bool Function() when, {
  double limit = 12.0,
}) {
  final steps = (limit / BlobSimulation.fixedDt).round();
  for (var i = 0; i < steps; i++) {
    sim.step();
    if (when()) return;
  }
  fail('condition never held within $limit s of simulated time');
}

/// Signed area of the live ring. Absolute value, so an inverted ring still
/// reports a positive area.
double _area(BlobSimulation sim) => sim.enclosedArea().abs();

/// Mean distance of the ring's points from the origin.
double _meanRadius(BlobSimulation sim) {
  var sum = 0.0;
  for (final p in sim.points) {
    sum += p.distance;
  }
  return sum / sim.points.length;
}

Offset _centroid(BlobSimulation sim) {
  var x = 0.0;
  var y = 0.0;
  for (final p in sim.points) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / sim.points.length, y / sim.points.length);
}

bool _isFiniteRing(BlobSimulation sim) {
  return sim.points.every(
    (p) => p.dx.isFinite && p.dy.isFinite,
  );
}

void main() {
  group('stays a coherent shape', () {
    test('the ring never inverts or collapses over a minute of drifting', () {
      final sim = BlobSimulation(restRadius: 58);

      for (var frame = 0; frame < 60 * 60; frame++) {
        sim.step();
        expect(_isFiniteRing(sim), isTrue, reason: 'frame $frame went non-finite');
        // Signed area must stay positive: a negative value means the ring folded
        // through itself, which is the failure mode pressure exists to prevent.
        expect(
          sim.enclosedArea(),
          greaterThan(0),
          reason: 'ring inverted at frame $frame',
        );
      }
    });

    test('enclosed area holds close to the resting circle', () {
      final sim = BlobSimulation(restRadius: 58);
      // Let the ring settle out of its seed before measuring anything.
      _advance(sim, 2.0);

      final ideal = 3.14159265358979 * 58 * 58;
      for (var frame = 0; frame < 60 * 20; frame++) {
        sim.step();
        final ratio = _area(sim) / ideal;
        expect(
          ratio,
          inInclusiveRange(0.75, 1.15),
          reason: 'area drifted to ${ratio.toStringAsFixed(3)} of rest '
              'at frame $frame',
        );
      }
    });

    test('a violent yank produces no NaN and no explosion', () {
      final sim = BlobSimulation(restRadius: 58);
      _advance(sim, 1.0);

      sim.grab(const Offset(58, 0));
      for (var i = 0; i < 240; i++) {
        // Slam the finger back and forth across a far larger distance than the
        // blob is wide, several times a second.
        final t = i * BlobSimulation.fixedDt;
        sim.dragTo(Offset(500 * _sin(t * 9), 400 * _cos(t * 7)));
        sim.step();
      }
      sim.release();

      expect(_isFiniteRing(sim), isTrue);
      expect(_area(sim), greaterThan(0));
      // And it must still recover rather than staying wrecked.
      _advance(sim, 6.0);
      expect(_area(sim), greaterThan(0));
      expect(
        _meanRadius(sim),
        inInclusiveRange(40, 80),
        reason: 'did not recover to roughly its resting size',
      );
    });
  });

  group('pulling stretches rather than drags', () {
    test('a hard pull moves the surface far more than it moves the centre', () {
      final sim = BlobSimulation(restRadius: 58);
      _advance(sim, 2.0);

      final centreBefore = _centroid(sim);
      sim.grab(const Offset(58, 0));
      _advance(sim, 0.6);
      sim.dragTo(const Offset(58 + 40, 0));
      _advance(sim, 0.6);

      final centreAfter = _centroid(sim);
      final travel = (centreAfter - centreBefore).distance;

      // The fingertip moved 40px. The centroid must move a small fraction of
      // that, or the blob is simply being carried around the screen. The bound is
      // a fifth of the pull rather than a hard pixel count, so it stays honest if
      // the anchor tuning changes.
      expect(
        travel,
        lessThan(40 * 0.25),
        reason: 'centre travelled $travel px under a 40 px pull',
      );

      // Meanwhile the grabbed side must actually be visibly deformed.
      var maxStretch = 0.0;
      for (final p in sim.points) {
        if (p.dx > 0) maxStretch = mathMax(maxStretch, p.dx);
      }
      expect(
        maxStretch,
        greaterThan(58 * 1.15),
        reason: 'the pulled side barely deformed (max x $maxStretch)',
      );
    });

    test('the pull is bounded, so a fling cannot tear a notch', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      _advance(sim, 0.4);
      sim.dragTo(const Offset(100000, 100000));
      _advance(sim, 1.0);

      var maxRadius = 0.0;
      for (final p in sim.points) {
        maxRadius = mathMax(maxRadius, p.distance);
      }
      // A fling to (100000, 100000) must still leave the shape recognisable. Stated as
      // an absolute bound rather than as the clamp's own formula, so the assertion
      // says what is actually true of the shape: even flung as hard as the finger
      // can move, it never grows more than half again its resting size.
      expect(
        maxRadius,
        lessThanOrEqualTo(58 * 1.5),
        reason: 'a point reached $maxRadius px from the centre',
      );
    });

    test('a pull does not flatten it', () {
      // Area is the property that a closed ring of fixed edges cannot protect on
      // its own: any shape with the same perimeter satisfies the edge constraints,
      // including a flat oval or a crumpled one. It took treating the enclosed
      // area as a constraint to stop a hard pull dragging the bubble into a thin
      // sliver, so the invariant is asserted directly.
      final sim = BlobSimulation(restRadius: 58);
      _advance(sim, 2.0);
      final resting = _area(sim);

      sim.grab(const Offset(58, 0));
      _advance(sim, 0.6);
      sim.dragTo(const Offset(58 + 46, 0));
      _advance(sim, 1.2);

      expect(
        _area(sim) / resting,
        inInclusiveRange(0.85, 1.15),
        reason: 'the pull changed the enclosed area, so the shape is not a bubble',
      );
    });

    test('releasing settles it back, damped rather than ringing', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.dragTo(const Offset(58 + 38, 10));
      _advance(sim, 0.5);

      sim.release();
      _advance(sim, 8.0);

      expect(
        _meanRadius(sim),
        inInclusiveRange(50, 68),
        reason: 'did not settle near its resting size',
      );
      expect(
        _centroid(sim).distance,
        lessThan(BlobSimulation.wanderAmplitude + 6),
        reason: 'did not settle near its resting spot',
      );
    });

    test('the settled blob stays inside its wander band', () {
      final sim = BlobSimulation(restRadius: 58);
      _advance(sim, 3.0);
      for (var frame = 0; frame < 60 * 30; frame++) {
        sim.step();
        expect(
          _centroid(sim).distance,
          lessThanOrEqualTo(BlobSimulation.wanderAmplitude + 6),
          reason: 'drifted out of band at frame $frame',
        );
      }
    });
  });

  group('inflating and deflating', () {
    test('a hold fills it with air within a bounded time', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      // Past the charge radius but still inside the charge duration, so this
      // asserts the filled-and-shaking state instead of racing past it into the
      // pop. Reaching a big bubble and bursting it are different events.
      _advance(sim, 1.2);

      expect(sim.state, BlobState.charged);
      expect(
        _meanRadius(sim) / 58,
        greaterThan(BlobSimulation.chargeRadius),
        reason: 'never reached the charge radius',
      );
      expect(
        _meanRadius(sim) / 58,
        lessThanOrEqualTo(BlobSimulation.inflateRadius + 0.05),
      );
    });

    test('letting go lets the air out and it settles back', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      _advance(sim, 1.2);
      final inflated = _meanRadius(sim);
      expect(inflated / 58, greaterThan(BlobSimulation.chargeRadius));

      sim.release();
      _advance(sim, 6.0);

      expect(
        _meanRadius(sim),
        inInclusiveRange(48, 66),
        reason: 'did not deflate back to rest',
      );
    });

    test('an inflated bubble can still be pulled around', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      _advance(sim, 1.0);
      expect(sim.state, BlobState.charged);

      // Grabbing and inflating are independent targets, so a long press must not
      // lock out the drag.
      sim.dragTo(const Offset(58 + 30, -12));
      _advance(sim, 0.4);
      expect(_isFiniteRing(sim), isTrue);
      expect(_area(sim), greaterThan(0));
    });
  });

  group('popping', () {
    test('a quick squeeze never pops it', () {
      final sim = BlobSimulation(restRadius: 58);
      // Squeeze hard but briefly: well past the charge radius, nowhere near the
      // charge duration.
      for (var i = 0; i < 20; i++) {
        sim.grab(const Offset(58, 0));
        sim.beginInflate();
        sim.step();
      }
      sim.release();

      expect(sim.state, isNot(BlobState.regrowing));
    });

    test('a sustained hold pops it', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      // Observed at the instant it pops rather than at a fixed deadline. A hold
      // long enough to *guarantee* the pop is also long enough to step past it,
      // and regrowth is itself physics-driven, so by any generous deadline the
      // bubble is already idle again.
      _advanceUntil(sim, () => sim.state == BlobState.regrowing);

      expect(sim.state, BlobState.regrowing);
      expect(sim.droplets, isNotEmpty, reason: 'the pop should throw droplets');
    });

    test('charge is reported as it builds, so the pop is foreshadowed', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();

      double previous = 0.0;
      var sawRise = false;
      for (var i = 0; i < 400; i++) {
        sim.step();
        final f = sim.chargeFraction;
        expect(f, inInclusiveRange(0.0, 1.0));
        if (f > previous) sawRise = true;
        previous = f;
      }
      expect(sawRise, isTrue, reason: 'charge never visibly accumulated');
    });

    test('a new bubble forms and pushes itself back out to full size', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      _advanceUntil(sim, () => sim.state == BlobState.regrowing);

      // This is the requirement that the regrowth is physics and not a
      // timeline: nothing sets the radius. The ring has to inflate itself.
      _advanceUntil(sim, () => sim.state == BlobState.idle);

      expect(sim.state, BlobState.idle);
      expect(
        _meanRadius(sim),
        inInclusiveRange(50, 68),
        reason: 'did not regrow to its resting size',
      );
    });

    test('the bubble is genuinely absent for a moment after a pop', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      _advanceUntil(sim, () => sim.state == BlobState.bursting);

      // The pop frame. The point of the gap is that the eye registers absence;
      // if the ring were still drawn the event would read as a wobble rather than
      // as a burst. The ring is withheld for [BlobSimulation.burstGap] seconds.
      expect(sim.droplets, isNotEmpty);

      // It stays gone: still bursting, not yet reopening, several frames later.
      _advance(sim, BlobSimulation.burstGap * 0.6);
      expect(sim.state, BlobState.bursting);

      _advanceUntil(sim, () => sim.state == BlobState.regrowing);
    });

    test('the re-seeded ring starts small', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      _advanceUntil(sim, () => sim.state == BlobState.regrowing);

      // Sampled the first frame after the gap, when the ring starts to open. It
      // should be the small one, not the inflated shape it was a moment ago.
      final opening = _meanRadius(sim);
      expect(
        opening,
        lessThan(58 * 1.1),
        reason: 'the new ring did not start small',
      );

      // And it grows from there, rather than appearing at full size.
      _advance(sim, 0.25);
      expect(_meanRadius(sim), greaterThan(opening));
    });

    test('it is interactive again after regrowing', () {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      sim.beginInflate();
      _advanceUntil(sim, () => sim.state == BlobState.regrowing);
      _advanceUntil(sim, () => sim.state == BlobState.idle);

      sim.grab(const Offset(58, 0));
      sim.dragTo(const Offset(80, 0));
      _advance(sim, 0.5);
      expect(_isFiniteRing(sim), isTrue);
    });

    test('a second pop works the same way as the first', () {
      final sim = BlobSimulation(restRadius: 58);

      // Twice through. The second cycle is the one that would fail if the burst
      // left the ring in a state it could not recover from, which is exactly the
      // bug that a single cycle hides.
      for (var cycle = 0; cycle < 2; cycle++) {
        sim.grab(const Offset(58, 0));
        sim.beginInflate();
        _advanceUntil(sim, () => sim.state == BlobState.regrowing);
        _advanceUntil(sim, () => sim.state == BlobState.idle);
      }
    });
  });

  test('the same input sequence produces the same output', () {
    BlobSimulation run() {
      final sim = BlobSimulation(restRadius: 58);
      sim.grab(const Offset(58, 0));
      for (var i = 0; i < 400; i++) {
        sim.dragTo(
          Offset(
            58 + 40 * _sin(i * 0.05),
            30 * _cos(i * 0.031),
          ),
        );
        sim.step();
      }
      sim.beginInflate();
      for (var i = 0; i < 600; i++) {
        sim.step();
      }
      return sim;
    }

    final a = run();
    final b = run();

    expect(a.points.length, b.points.length);
    for (var i = 0; i < a.points.length; i++) {
      expect(a.points[i].dx, closeTo(b.points[i].dx, 1e-9));
      expect(a.points[i].dy, closeTo(b.points[i].dy, 1e-9));
    }
    expect(a.state, b.state);
  });
}

double _sin(double x) => math.sin(x);

double _cos(double x) => math.cos(x);

double mathMax(double a, double b) => math.max(a, b);