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

/// A night sky in which every moment the person chose to keep is a star, joined to its neighbours by faint lines
/// into a small constellation. With none yet it is a quiet sky that says where the first one will go. The card also
/// holds the two ways to add one: write it, or talk about it.
class MomentsSkyCard extends StatefulWidget {
  const MomentsSkyCard({required this.count, required this.onAdd, this.onTalk, super.key});

  /// How many moments are kept.
  final int count;
  final VoidCallback onAdd;

  /// Opens a chat. Hidden when null.
  final VoidCallback? onTalk;

  @override
  State<MomentsSkyCard> createState() => _MomentsSkyCardState();
}

class _MomentsSkyCardState extends State<MomentsSkyCard> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 20));
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = _isTestEnvironment || (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (!still && !_running) {
      _loop.repeat();
      _running = true;
    } else if (still && _running) {
      _loop.stop();
      _running = false;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    final title = n == 0 ? 'Your first star is waiting' : (n == 1 ? 'One moment kept' : '$n moments kept');
    final sub = n == 0 ? 'A good thing, however small, becomes a light here.' : 'Each one is a light you chose to keep.';
    return Semantics(
      container: true,
      label: '$title. $sub',
      child: ClipRRect(
        key: const ValueKey('moments-sky'),
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) => CustomPaint(painter: _SkyPainter(n, _loop.value)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MOMENTS WORTH KEEPING',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: Color(0xB3FFF1DA)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Color(0xFFFFF6E6)),
                  ),
                  const SizedBox(height: 4),
                  Text(sub, style: const TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: Color(0xCCFFF1DA))),
                  const SizedBox(height: 118),
                  Row(
                    children: [
                      Expanded(
                        child: _SkyButton(key: const ValueKey('moment-add'), label: 'Add a moment', icon: Icons.add_rounded, filled: true, onTap: widget.onAdd),
                      ),
                      if (widget.onTalk != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SkyButton(key: const ValueKey('moment-talk'), label: 'Talk about one', icon: Icons.chat_bubble_outline_rounded, filled: false, onTap: widget.onTalk!),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkyButton extends StatelessWidget {
  const _SkyButton({required this.label, required this.icon, required this.filled, required this.onTap, super.key});

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFFFFF6E6);
    return Material(
      color: filled ? const Color(0xFFFFB534) : Colors.transparent,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: fg.withValues(alpha: 0.45))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? const Color(0xFF3A2A0C) : fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: filled ? const Color(0xFF3A2A0C) : fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.count, this.t);

  final int count;
  final double t;

  static double _s(double x) => math.sin(x * 2 * math.pi);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2B2A52), Color(0xFF59477E), Color(0xFFB8708A)],
          stops: [0, 0.62, 1],
        ).createShader(rect),
    );

    // A faint background of small stars.
    final bg = math.Random(21);
    for (var i = 0; i < 36; i++) {
      final x = bg.nextDouble() * w, y = bg.nextDouble() * h * 0.7;
      final tw = 0.3 + 0.7 * (0.5 + 0.5 * _s(t * 2 + i * 0.29));
      canvas.drawCircle(Offset(x, y), 0.7 + bg.nextDouble() * 0.9, Paint()..color = Colors.white.withValues(alpha: 0.35 * tw));
    }

    // A soft glow on the horizon.
    final glowC = Offset(w * 0.5, h * 1.05);
    canvas.drawCircle(
      glowC,
      w * 0.7,
      Paint()..shader = RadialGradient(colors: [const Color(0xFFFFB27A).withValues(alpha: 0.5), const Color(0x00FFB27A)]).createShader(Rect.fromCircle(center: glowC, radius: w * 0.7)),
    );

    // The moments, as stars in the band between the words and the buttons.
    final shown = math.min(count, 28);
    final pts = <Offset>[];
    for (var i = 0; i < shown; i++) {
      final r = math.Random(i * 7919 + 13);
      pts.add(Offset(w * (0.07 + 0.86 * r.nextDouble()), h * (0.42 + 0.26 * r.nextDouble())));
    }
    final ordered = [...pts]..sort((a, b) => a.dx.compareTo(b.dx));
    for (var i = 0; i + 1 < ordered.length; i++) {
      canvas.drawLine(
        ordered[i],
        ordered[i + 1],
        Paint()
          ..color = const Color(0xFFFFE3A8).withValues(alpha: 0.22)
          ..strokeWidth = 0.9,
      );
    }
    for (var i = 0; i < pts.length; i++) {
      final pulse = 0.75 + 0.25 * _s(t * 3 + i * 0.37);
      final p = pts[i];
      canvas.drawCircle(p, 11 * pulse, Paint()..color = const Color(0xFFFFD98A).withValues(alpha: 0.22));
      canvas.drawCircle(p, 3.2, Paint()..color = const Color(0xFFFFF0C4));
      // a little four-point sparkle
      final len = 6.0 * pulse;
      final line = Paint()
        ..color = const Color(0xFFFFF0C4).withValues(alpha: 0.8)
        ..strokeWidth = 1;
      canvas.drawLine(p - Offset(len, 0), p + Offset(len, 0), line);
      canvas.drawLine(p - Offset(0, len), p + Offset(0, len), line);
    }

    // With none yet, three dim places for the first stars.
    if (count == 0) {
      final spots = [Offset(w * 0.22, h * 0.56), Offset(w * 0.5, h * 0.48), Offset(w * 0.78, h * 0.58)];
      for (var i = 0; i < spots.length; i++) {
        final a = 0.28 + 0.14 * _s(t * 2 + i * 0.3);
        canvas.drawCircle(
          spots[i],
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFFFFE3A8).withValues(alpha: a),
        );
      }
    }

    // Hills at the bottom, so the sky has somewhere to sit.
    final hill = Path()..moveTo(0, h);
    for (double x = 0; x <= w; x += 4) {
      hill.lineTo(x, h * 0.9 + 6 * _s(x / w * 1.3 + 0.2));
    }
    hill
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0xFF2A2347).withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) => old.t != t || old.count != count;
}
