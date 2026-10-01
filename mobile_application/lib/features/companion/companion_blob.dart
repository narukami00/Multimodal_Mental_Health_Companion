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
    final path = _blobPath(size);

    // A blurred copy of the shape, offset down. Not canvas.drawShadow: that
    // renders a rectangular occluder behind a non-rectangular path, which
    // showed up as a grey box around the blob.
    canvas.drawPath(
      _blobPath(size, radiusScale: 0.94).shift(const Offset(0, 7)),
      Paint()
        ..color = const Color(0x40C07818)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    // Two offset translucent layers under the body, so it reads as liquid with
    // depth rather than as a flat disc. They are what let it sit over text
    // without hiding it.
    canvas.drawPath(
      _blobPath(size, radiusScale: 0.86),
      Paint()..color = _core.withValues(alpha: 0.30),
    );
    canvas.drawPath(
      _blobPath(size, radiusScale: 0.68),
      Paint()..color = _light.withValues(alpha: 0.26),
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.44),
          radius: 0.95,
          colors: [
            _light.withValues(alpha: 0.82),
            _core.withValues(alpha: 0.72),
            _deep.withValues(alpha: 0.62),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    // An inner rim, which is what gives the silhouette an edge against a pale
    // background. Measured about 1.2 to 1 without it.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x3AC07818),
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
