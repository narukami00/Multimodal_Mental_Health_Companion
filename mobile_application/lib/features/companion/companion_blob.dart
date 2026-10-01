import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// The companion, as a shape rather than an icon.
///
/// Deliberately has no words on it. Tap opens a new conversation; press and
/// hold reveals actions. Because it carries no label, the affordances have to
/// come from elsewhere: a cast shadow so it reads as a surface rather than a
/// printed circle, an inner rim so it has a silhouette against a pale page, and
/// a slow breath so it reads as alive rather than as decoration.
class CompanionBlob extends StatefulWidget {
  const CompanionBlob({
    this.diameter = 92,
    this.onTap,
    this.onLongPress,
    this.animate = true,
    this.semanticLabel = 'Talk to Solace',
    super.key,
  });

  final double diameter;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Off in tests and for reduced-motion, where an endless animation would hang
  /// `pumpAndSettle` or make the screen restless.
  final bool animate;

  final String semanticLabel;

  @override
  State<CompanionBlob> createState() => _CompanionBlobState();
}

class _CompanionBlobState extends State<CompanionBlob>
    with TickerProviderStateMixin {
  // Two slow cycles at different speeds, so the shape never visibly loops.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 14000),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5500),
  );

  /// Where the shape has been dragged to. Dragging it plays with it, the way
  /// you would push a drop of water around; letting go springs it home.
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.animate && !_isTestEnvironment) {
      _morph.repeat();
      _breathe.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the system's reduce-motion setting, as the rest of the app does.
    if (!_isTestEnvironment && MediaQuery.disableAnimationsOf(context)) {
      _morph.stop();
      _breathe.stop();
      _morph.value = 0.35;
      _breathe.value = 0;
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _breathe.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _drag += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.animate || _isTestEnvironment) {
      setState(() => _drag = Offset.zero);
      return;
    }
    // A spring back to the resting spot, carrying the velocity of the throw.
    final start = _drag;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final curve = CurvedAnimation(parent: controller, curve: Curves.elasticOut);
    controller.addListener(() {
      setState(() => _drag = Offset.lerp(start, Offset.zero, curve.value)!);
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
      }
    });
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: Listenable.merge([_morph, _breathe]),
          builder: (context, _) {
            final breath = 1 +
                0.045 * Curves.easeInOut.transform(_breathe.value);
            return Transform.translate(
              offset: _drag,
              child: Transform.scale(
                scale: breath,
                child: SizedBox(
                  width: widget.diameter,
                  height: widget.diameter,
                  child: CustomPaint(
                    painter: _BlobPainter(phase: _morph.value),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.phase});

  final double phase;

  static const _core = Color(0xFFFFB534);
  static const _light = Color(0xFFFFE0AE);
  static const _deep = Color(0xFFFF8B3D);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final body = _blobPath(size);
    final t = phase * 2 * math.pi;

    // 1. A radiant halo, so the shape sits in the page rather than on it.
    canvas.drawPath(
      _blobPath(size, radiusScale: 1.22),
      Paint()
        ..color = _core.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );

    // 2. A cast shadow as a blurred copy of the shape. Not canvas.drawShadow:
    //    that renders a rectangular occluder behind a non-rectangular path,
    //    which showed up as a grey box.
    canvas.drawPath(
      _blobPath(size, radiusScale: 0.95).shift(const Offset(0, 9)),
      Paint()
        ..color = const Color(0x45C07818)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );

    // 3. The body, with its light source orbiting rather than fixed, which is
    //    what makes it read as liquid instead of a painted circle.
    final orbit = Offset(math.cos(t) * 0.22, math.sin(t) * 0.22);
    canvas.drawPath(
      body,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(orbit.dx - 0.18, orbit.dy - 0.26),
          radius: 1.05,
          colors: [
            _light.withValues(alpha: 0.98),
            _core.withValues(alpha: 0.94),
            _deep.withValues(alpha: 0.88),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Offset.zero & size),
    );

    // 4. An inner counter-swirl turning the other way: two fluids inside one
    //    skin rather than one flat fill.
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(-t * 0.7);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.drawPath(
      _blobPath(size, radiusScale: 0.60).shift(Offset(size.width * 0.05, 0)),
      Paint()..color = _light.withValues(alpha: 0.24),
    );
    canvas.restore();

    // 5. Effervescence: small bubbles drifting up inside the body.
    for (var i = 0; i < 4; i++) {
      final drift = (phase * 1.6 + i * 0.25) % 1.0;
      final x = centre.dx + math.sin(t * 0.9 + i * 1.9) * size.width * 0.22;
      final y = centre.dy + size.height * (0.30 - drift * 0.62);
      final r = size.width * (0.028 + i * 0.006);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.40),
      );
    }

    // 6. A specular sheen where the light would catch glass.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          centre.dx - size.width * 0.16,
          centre.dy - size.height * 0.20,
        ),
        width: size.width * 0.30,
        height: size.height * 0.17,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(centre.dx + size.width * 0.20, centre.dy + size.height * 0.14),
      size.width * 0.035,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    // 7. Surface tension: a shimmering rim, so the skin has an edge against a
    //    pale page. Measured about 1.2 to 1 without it.
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const Color(0x66FFFFFF),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0x3AB46B0A),
    );
  }

  /// An organic closed curve: a circle perturbed by two slow harmonics, so it
  /// never reads as a circle and never repeats visibly.
  Path _blobPath(Size size, {double radiusScale = 1.0}) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.40 * radiusScale;
    final t = phase * 2 * math.pi;

    const points = 72;
    final path = Path();
    for (var i = 0; i < points; i++) {
      final theta = (i / points) * 2 * math.pi;
      final wobble =
          0.055 * math.sin(3 * theta + t) + 0.032 * math.sin(5 * theta - t * 1.3);
      final r = radius * (1 + wobble);
      final point = Offset(
        centre.dx + r * math.cos(theta),
        centre.dy + r * math.sin(theta),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}
