import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'blob_simulation.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// The companion, as a body of liquid rather than a picture of one.
///
/// It is a translucent thing you can touch. Nothing here plays an animation and
/// then resets: every visible property is read straight off a [BlobSimulation],
/// which is integrated continuously and has no period. That is what stops it
/// visibly restarting, and it is why the pull, the swell and the collapse all
/// share one mechanism instead of three separate effects.
///
/// The colours are the app's own amber and coral, layered rather than mixed, so
/// the page reads through it. See [_JellyPainter] for why screen-blending those
/// layers is the right choice here and multiplying them is not.
class CompanionBlob extends StatefulWidget {
  const CompanionBlob({
    this.diameter = 92,
    this.onTap,
    this.animate = true,
    this.semanticLabel = 'Talk to Solace',
    super.key,
  });

  /// Diameter of the resting shape, not of the box.
  ///
  /// The box is derived from this, and has to be wide enough for the shape at its
  /// most inflated *and* for the aura around it. Sizing it to the resting shape
  /// clipped the swell, and a clipped translucent shape shows as a hard edge.
  final double diameter;

  /// Opens a brand-new conversation.
  final VoidCallback? onTap;

  /// Off in tests and for reduced motion, where an endless simulation would hang
  /// `pumpAndSettle` or make the screen restless. The shape still responds to
  /// touch when this is false.
  final bool animate;

  final String semanticLabel;

  /// The layout box a blob of [diameter] is drawn into.
  ///
  /// Public because the Home page positions the shape by where the *shape* should
  /// land, and to do that it has to know how much bigger the box is than the
  /// shape. That relationship used to be private to this file, so callers had to
  /// guess it — and guessed wrong, moving the bubble the wrong way twice.
  static double boxExtentFor(double diameter) =>
      diameter * BlobSimulation.inflateRadius * 1.15;

  @override
  State<CompanionBlob> createState() => _CompanionBlobState();
}

class _CompanionBlobState extends State<CompanionBlob>
    with SingleTickerProviderStateMixin {
  /// The resting radius. The blob is drawn at this size and the physics is
  /// solved around it.
  double get _restRadius => widget.diameter * 0.5;

  /// The box the shape and its glow are drawn into.
  ///
  /// Sized to the resting diameter scaled by the same factor the simulation
  /// inflates to, so the box and the physics cannot disagree about how big the
  /// blob gets. Anything less and the swell is clipped at the moment it is most
  /// visible.
  double get _boxExtent => CompanionBlob.boxExtentFor(widget.diameter);

  late final BlobSimulation _simulation =
      BlobSimulation(restRadius: _restRadius);

  late final Ticker _ticker;

  Duration? _lastElapsed;

  /// Set while the system asks for reduced motion. The ticker stops, but touch
  /// still works: turning off the ambient drift is the accessibility requirement,
  /// removing the response to a deliberate gesture is not.
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.animate && !_isTestEnvironment) {
      _ticker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant CompanionBlob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    final shouldRun = widget.animate && !_isTestEnvironment && !_reducedMotion;
    if (shouldRun && !_ticker.isActive) {
      // Restarted from scratch rather than resumed, so the first frame's dt is
      // measured from now instead of from whenever the ticker was last stopped.
      _lastElapsed = null;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _simulation.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == null) return;

    // Clamped because a frame can arrive arbitrarily late after a stall, and a
    // stiff solver handed a huge dt answers it by exploding. The simulation does
    // its own fixed-step subdivision from here.
    final dt =
        ((elapsed - previous).inMicroseconds / 1000000.0).clamp(0.0, 0.25);

    _simulation.advance(dt);
    // No setState. The simulation is a Listenable and the painter subscribes to
    // it directly, so a frame of wobble costs one repaint rather than a rebuild
    // of every widget this sits inside. On Home that is the whole check-in card.
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: GestureDetector(
        // Opaque, because the drawn shape is smaller than this box and the empty
        // corners should still belong to the blob.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanDown: (d) => _simulation.grab(_local(d.localPosition)),
        onPanUpdate: (d) => _simulation.dragTo(_local(d.localPosition)),
        onPanEnd: (_) => _simulation.release(),
        onPanCancel: _simulation.release,
        // A hold, rather than a pan, is what fills it with air. Deliberately not
        // onLongPress: that has a fixed threshold of its own and cannot report
        // the finger moving while the fill is under way, which is the case that
        // matters here, because an inflated bubble has to stay pullable.
        onLongPressStart: (d) {
          _simulation.grab(_local(d.localPosition));
          _simulation.beginInflate();
        },
        onLongPressMoveUpdate: (d) =>
            _simulation.dragTo(_local(d.localPosition)),
        onLongPressEnd: (_) => _simulation.release(),
        onLongPressCancel: _simulation.release,
        child: RepaintBoundary(
          child: SizedBox(
            width: _boxExtent,
            height: _boxExtent,
            child: CustomPaint(
              painter: _JellyPainter(
                simulation: _simulation,
                // The light sits above and to the left and stays there. Orbiting
                // it as the current blob does makes the shape read as spinning
                // rather than as sitting still, and the specular highlight
                // wandering across the skin is the giveaway.
                light: const Alignment(-0.42, -0.52),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Converts a point in the widget's box into the simulation's own coordinates,
  /// which are centred on the origin and in the same pixel scale.
  Offset _local(Offset inBox) {
    final extent = _boxExtent;
    return Offset(inBox.dx - extent / 2, inBox.dy - extent / 2);
  }
}

/// Paints the simulated ring as a translucent, layered jelly.
///
/// Every layer is built from the *same* live point list at a different scale, so
/// the whole thing deforms as one body. Giving each layer its own wobble looks
/// like several objects in a bag rather than one object with depth.
class _JellyPainter extends CustomPainter {
  _JellyPainter({required this.simulation, required this.light})
      : super(repaint: simulation);

  final BlobSimulation simulation;

  /// Direction of the key light, in the painter's own coordinate space.
  final Alignment light;

  // The app's own accents. Layered in the same family as the check-in card
  // rather than introduced fresh, so the blob still reads as part of this page.
  static const _amber = Color(0xFFFFB534);
  static const _coral = Color(0xFFFF7F50);
  static const _deep = Color(0xFFE86034);
  static const _cream = Color(0xFFFFF3D6);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);

    final droplets = simulation.droplets;
    final body = _outline(simulation.points, 1.0);
    // The ring is still present during a burst; it is the body that is withheld.
    // Hiding it for those few frames is what makes a pop read as the shape
    // leaving rather than as something drawn on top of it.
    final visible = simulation.state != BlobState.bursting;

    if (visible) {
      _paintAura(canvas);
      _paintBody(canvas, body);
    }

    _paintDroplets(canvas, droplets);
    canvas.restore();
  }

  /// The soft light the bubble sits in, so it reads as suspended rather than
  /// pasted onto the page.
  void _paintAura(Canvas canvas) {
    final reach = simulation.restRadius * simulation.inflation;
    canvas.drawCircle(
      Offset.zero,
      reach * 1.5,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          reach * 1.5,
          [
            _amber.withValues(alpha: 0.22),
            _coral.withValues(alpha: 0.10),
            _coral.withValues(alpha: 0.0),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  /// Membrane, inner layers, sheen and rim, in that order.
  void _paintBody(Canvas canvas, Path body) {
    final reach = simulation.restRadius * simulation.inflation;
    final charge = simulation.chargeFraction;

    // Overlapping translucent shapes compound: three 40% layers composite to
    // about 78%, not 40%, and the overlaps go muddy. Everything inside this
    // layer is drawn opaque and flattened once at the end, so the body's actual
    // translucency is the single alpha here and nothing doubles up.
    canvas.saveLayer(_boundsOf(simulation.points), Paint());

    // 1. The membrane itself: a thin, even skin. Most of the see-through
    //    character comes from this being far lighter than the solid blob it
    //    replaces.
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          _offsetTo(light, reach * 0.30),
          reach * 1.15,
          [
            _cream.withValues(alpha: 0.62),
            _amber.withValues(alpha: 0.50),
            _coral.withValues(alpha: 0.44),
            _deep.withValues(alpha: 0.46),
          ],
          const [0.0, 0.38, 0.74, 1.0],
        ),
    );

    // 2. A brighter inner layer, screen-blended.
    //
    //    Screen, not multiply. The call screen's orb composites its inner layer
    //    with multiply because that orb is opaque, and darkening is what makes a
    //    solid object look dense. Here the page has to read through the shape,
    //    and multiply over a cream page produces mud rather than translucency.
    //    Screen brightens instead, so overlaps intensify the colour the way
    //    backlit jelly actually does.
    canvas.drawPath(
      _outline(simulation.points, 0.80),
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.radial(
          _offsetTo(light, reach * 0.16),
          reach * 0.8,
          [
            _cream.withValues(alpha: 0.34),
            _amber.withValues(alpha: 0.26),
            _amber.withValues(alpha: 0.0),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );

    // 3. The dense heart. Smaller again, and hotter, so there is a warm core for
    //    the eye to settle on rather than an even wash of colour.
    canvas.drawPath(
      _outline(simulation.points, 0.46),
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.radial(
          _offsetTo(light, reach * 0.10),
          reach * 0.5,
          [
            _coral.withValues(alpha: 0.30),
            _deep.withValues(alpha: 0.20),
            _deep.withValues(alpha: 0.0),
          ],
          const [0.0, 0.6, 1.0],
        ),
    );

    // 4. Where the light catches the wet surface. Not orbiting, and not blurred:
    //    a sharp small highlight is what makes a shape look wet rather than
    //    merely pale.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawOval(
      Rect.fromCenter(
        center: _offsetTo(light, reach * 0.40),
        width: reach * 0.52,
        height: reach * 0.30,
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          _offsetTo(light, reach * 0.40),
          reach * 0.34,
          [
            Colors.white.withValues(alpha: 0.72),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.0),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();

    canvas.restore();

    // 5. The rim.
    //
    //    Not optional. A translucent shape with no edge dissolves into a pale
    //    page, and the previous blob measured roughly 1.2:1 contrast without one.
    //    It also brightens as the charge builds, so the surface reports the
    //    pressure before the pop lands and the burst arrives having been
    //    telegraphed.
    final rim = Color.lerp(
      Colors.white.withValues(alpha: 0.55 + charge * 0.4),
      _cream.withValues(alpha: 0.75 + charge * 0.25),
      charge,
    )!;
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 + charge * 1.4
        ..color = rim,
    );

    // 6. A deeper fringe just inside the rim, which is what gives the skin
    //    visible thickness. Real translucent jelly separates colour at its
    //    edge; without this it reads as a flat wash.
    canvas.drawPath(
      _outline(simulation.points, 0.93),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _deep.withValues(alpha: 0.20),
    );
  }

  /// The droplets thrown off by a pop, fading as they spread.
  void _paintDroplets(
    Canvas canvas,
    List<({Offset position, double radius, double opacity})> droplets,
  ) {
    for (final d in droplets) {
      // Radius comes from the simulation rather than being derived here from
      // opacity, so a droplet shrinks as it fades instead of fading at a fixed
      // size. At a fixed size its last visible frame is still a full-radius disc
      // at low alpha, which reads as a smudge left on the page rather than as
      // something that has gone.
      if (d.opacity <= 0.002) continue;
      canvas.drawCircle(
        d.position,
        d.radius + 1.2,
        Paint()
          ..color = _cream.withValues(alpha: 0.55 * d.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );
    }
  }

  /// The live ring, optionally drawn at [scale] of its own radius.
  ///
  /// Scaled radially about the ring's centre rather than as a box. A box scale
  /// applied to an off-centre outline skews it, which reads as the shape shearing.
  Path _outline(List<Offset> ring, double scale) {
    if (ring.length < 3) return Path();

    var cx = 0.0;
    var cy = 0.0;
    for (final p in ring) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= ring.length;
    cy /= ring.length;

    // A closed midpoint-quadratic spline, so the curve is smooth through the
    // joints. Joining 44 points with straight lines leaves visible corners, which
    // is the giveaway that this is a polygon rather than a liquid.
    final points = <Offset>[
      for (final p in ring)
        Offset(cx + (p.dx - cx) * scale, cy + (p.dy - cy) * scale),
    ];

    final mid = List<Offset>.generate(points.length, (i) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    });

    final path = Path()..moveTo(mid.last.dx, mid.last.dy);
    for (var i = 0; i < points.length; i++) {
      path.quadraticBezierTo(
        points[i].dx,
        points[i].dy,
        mid[i].dx,
        mid[i].dy,
      );
    }
    return path..close();
  }

  /// A box that contains the whole ring, with a little slack for its stroke.
///
/// Measured from the live points rather than derived from the nominal radius.
/// A ring under a pull or a swell reaches well past `restRadius`, and sizing the
/// layer from the radius clipped the shape with a dead straight edge — which on a
/// translucent fill reads as a rendering fault rather than as an edge.
Rect _boundsOf(List<Offset> ring) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final p in ring) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    const slack = 4.0;
    return Rect.fromLTRB(
      minX - slack,
      minY - slack,
      maxX + slack,
      maxY + slack,
    );
  }

  /// An [Alignment] placed at [distance] from the centre, for gradient foci.
  Offset _offsetTo(Alignment a, double distance) {
    return Offset(a.x * distance, a.y * distance);
  }

  @override
  bool shouldRepaint(covariant _JellyPainter oldDelegate) =>
      oldDelegate.simulation != simulation || oldDelegate.light != light;
}