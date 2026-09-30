import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../suggestions/suggestion_card_surface.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// The gentle idea, sitting on Home below whichever card is on top.
///
/// One sentence and two answers. Declining is instant and warm, and the space
/// it occupied closes up behind it.
class HomeSuggestionCard extends StatefulWidget {
  const HomeSuggestionCard({
    required this.choice,
    required this.onAccept,
    this.onDecline,
    this.onVanished,
    super.key,
  });

  /// What was peeked, or null when nothing is due.
  final SuggestionCardChoice? choice;

  /// Called when the user says they did it, with the suggestion they saw.
  final void Function(SuggestionCardChoice choice) onAccept;
  final VoidCallback? onDecline;

  /// Called once the card has closed, so the next one can be brought in.
  final VoidCallback? onVanished;

  @override
  State<HomeSuggestionCard> createState() => _HomeSuggestionCardState();
}

class _HomeSuggestionCardState extends State<HomeSuggestionCard> {
  SuggestionCardChoice? _choice;
  bool _sayingGoodbye = false;

  @override
  void initState() {
    super.initState();
    _choice = widget.choice;
  }

  @override
  void didUpdateWidget(HomeSuggestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once a suggestion is on screen it stays put. Home rebuilds often, and a
    // card that swapped its activity mid-reach would be worse than one that
    // lags a moment behind.
    if (_choice == null && !_sayingGoodbye) _choice = widget.choice;
  }

  void _decline() {
    setState(() => _sayingGoodbye = true);
    widget.onDecline?.call();
    // Long enough to read the goodbye, short enough not to feel like a delay.
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() {
        _choice = null;
        _sayingGoodbye = false;
      });
      widget.onVanished?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    if (choice == null) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _sayingGoodbye ? 0.0 : 1.0,
          child: _CardShell(
            activity: choice.activity,
            sayingGoodbye: _sayingGoodbye,
            onAccept: _sayingGoodbye ? null : () => widget.onAccept(choice),
            onDecline: _sayingGoodbye ? null : _decline,
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.activity,
    required this.sayingGoodbye,
    required this.onAccept,
    required this.onDecline,
  });

  final Activity activity;
  final bool sayingGoodbye;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientFor(activity.type),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A5A4030),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(26)),
              child: _CardBackdrop(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
            child: Row(
              children: [
                ActivityTypeGlyph(type: activity.type, size: 58),
                const SizedBox(width: 16),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    child: Text(
                      sayingGoodbye
                          ? 'Okay, have a nice day.'
                          : activity.title,
                      key: ValueKey(sayingGoodbye),
                      style: const TextStyle(
                        color: Color(0xFF4A3728),
                        fontSize: 17,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _AnswerButton(
                  key: const ValueKey('suggestion-accept'),
                  icon: Icons.check_rounded,
                  tooltip: 'I did it',
                  onPressed: onAccept,
                ),
                const SizedBox(width: 6),
                _AnswerButton(
                  key: const ValueKey('suggestion-decline'),
                  icon: Icons.close_rounded,
                  tooltip: 'Not today',
                  onPressed: onDecline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _gradientFor(ActivityType type) {
    return switch (type) {
      ActivityType.movement => const [Color(0xFFFFF3DC), Color(0xFFFFE3B8)],
      ActivityType.social => const [Color(0xFFFFE9E2), Color(0xFFFFD6C6)],
      ActivityType.creative => const [Color(0xFFF6E9FF), Color(0xFFE8D4FA)],
      ActivityType.nature => const [Color(0xFFE6F4E4), Color(0xFFCFE9CC)],
      ActivityType.mindfulness => const [Color(0xFFE4F1F6), Color(0xFFCCE3EE)],
      ActivityType.learning => const [Color(0xFFFFF1D9), Color(0xFFF6DFAE)],
      ActivityType.productivity => const [Color(0xFFEDEBF7), Color(0xFFD9D5EE)],
    };
  }
}

/// Two answers, and nothing else. Each is a plain circle, so neither reads as
/// the "right" one.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.72),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: const Color(0xFF4A3728)),
          ),
        ),
      ),
    );
  }
}

/// A very quiet backdrop, so the card reads as considered rather than plain.
class _CardBackdrop extends StatelessWidget {
  const _CardBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackdropPainter());
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x14FFFFFF);
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.1),
      size.height * 0.9,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.06, size.height * 0.95),
      size.height * 0.5,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

/// A vector glyph per activity type.
///
/// Drawn rather than shipped as image assets: the app has no SVG dependency,
/// and a painter scales cleanly and can be animated without adding one.
class ActivityTypeGlyph extends StatefulWidget {
  const ActivityTypeGlyph({required this.type, this.size = 52, super.key});

  final ActivityType type;
  final double size;

  @override
  State<ActivityTypeGlyph> createState() => _ActivityTypeGlyphState();
}

class _ActivityTypeGlyphState extends State<ActivityTypeGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void initState() {
    super.initState();
    // Never left running under test: an endless animation hangs pumpAndSettle.
    if (!_isTestEnvironment) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _GlyphPainter(
            type: widget.type,
            progress: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.type, required this.progress});

  final ActivityType type;
  final double progress;

  /// A slow drift and sway, so the glyph feels alive without demanding
  /// attention. Deliberately more movement than a static icon would need: a
  /// still glyph at this size reads as decoration, and the point is that it is
  /// a living card.
  double get _scale => 1 + math.sin(progress * 2 * math.pi) * 0.09;

  double get _tilt => math.sin(progress * 2 * math.pi) * 0.07;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // A filled disc, so the glyph reads as an icon rather than a stray line.
    canvas.drawCircle(
      Offset.zero,
      size.width * 0.46,
      Paint()..color = const Color(0x33FFFFFF),
    );

    canvas.scale(_scale);
    canvas.rotate(_tilt);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF6B4A2C);

    switch (type) {
      case ActivityType.movement:
        _footsteps(canvas, size, stroke);
      case ActivityType.social:
        _twoCircles(canvas, size, stroke);
      case ActivityType.creative:
        _brush(canvas, size, stroke);
      case ActivityType.nature:
        _leaf(canvas, size, stroke);
      case ActivityType.mindfulness:
        _ripples(canvas, size, stroke);
      case ActivityType.learning:
        _book(canvas, size, stroke);
      case ActivityType.productivity:
        _check(canvas, size, stroke);
    }
    canvas.restore();
  }

  void _footsteps(Canvas canvas, Size size, Paint stroke) {
    final r = size.width;
    canvas.drawCircle(Offset(-r * 0.10, -r * 0.14), r * 0.10, stroke);
    canvas.drawCircle(Offset(r * 0.06, r * 0.06), r * 0.10, stroke);
    canvas.drawLine(
      Offset(-r * 0.10, -r * 0.02),
      Offset(-r * 0.10, -r * 0.04),
      stroke,
    );
  }

  void _twoCircles(Canvas canvas, Size size, Paint stroke) {
    final r = size.width;
    canvas.drawCircle(Offset(-r * 0.13, -r * 0.05), r * 0.11, stroke);
    canvas.drawCircle(Offset(r * 0.14, -r * 0.02), r * 0.09, stroke);
  }

  void _brush(Canvas canvas, Size size, Paint stroke) {
    final r = size.width;
    canvas.drawLine(
      Offset(-r * 0.18, r * 0.18),
      Offset(r * 0.18, -r * 0.18),
      stroke,
    );
    canvas.drawCircle(Offset(-r * 0.18, r * 0.18), r * 0.07, stroke);
  }

  void _leaf(Canvas canvas, Size size, Paint stroke) {
    final r = size.width;
    final path = Path()
      ..moveTo(0, -r * 0.22)
      ..quadraticBezierTo(r * 0.24, -r * 0.02, 0, r * 0.22)
      ..quadraticBezierTo(-r * 0.24, -r * 0.02, 0, -r * 0.22);
    canvas.drawPath(path, stroke);
    canvas.drawLine(Offset(0, -r * 0.18), Offset(0, r * 0.18), stroke);
  }

  void _ripples(Canvas canvas, Size size, Paint stroke) {
    final r = size.width;
    for (final scale in [0.10, 0.19, 0.28]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * scale),
        math.pi * 0.15,
        math.pi * 0.7,
        false,
        stroke,
      );
    }
  }

  void _book(Canvas canvas, Size size, Paint stroke) {
    final r = size.width;
    canvas.drawLine(Offset(0, -r * 0.16), Offset(0, r * 0.16), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 0.16)
        ..quadraticBezierTo(-r * 0.14, -r * 0.22, -r * 0.22, -r * 0.16)
        ..lineTo(-r * 0.22, r * 0.14)
        ..quadraticBezierTo(-r * 0.14, r * 0.10, 0, r * 0.16),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, -r * 0.16)
        ..quadraticBezierTo(r * 0.14, -r * 0.22, r * 0.22, -r * 0.16)
        ..lineTo(r * 0.22, r * 0.14)
        ..quadraticBezierTo(r * 0.14, r * 0.10, 0, r * 0.16),
      stroke,
    );
  }

  void _check(Canvas canvas, Size size, Paint stroke) {
    final r = size.width;
    canvas.drawPath(
      Path()
        ..moveTo(-r * 0.19, 0)
        ..lineTo(-r * 0.05, r * 0.15)
        ..lineTo(r * 0.20, -r * 0.16),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.type != type;
  }
}
