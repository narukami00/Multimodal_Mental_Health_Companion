import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../suggestions/suggestion_card_surface.dart';
import 'activity_scene.dart';

/// The gentle idea, sitting on Home below whichever card is on top.
///
/// One sentence, what it means, and two answers. The background carries a drawn
/// scene for the kind of activity, so the card shows its subject rather than
/// naming it beside a symbol.
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
          child: ActivitySuggestionCard(
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

/// The card face, split out so it can be rendered and reviewed on its own.
class ActivitySuggestionCard extends StatelessWidget {
  const ActivitySuggestionCard({
    required this.activity,
    required this.onAccept,
    this.onDecline,
    this.sayingGoodbye = false,
    super.key,
  });

  final Activity activity;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final bool sayingGoodbye;

  /// The palette each kind of activity is painted in.
  ///
  /// Two stops: a pale wash that the text sits on, and a deeper ink for the
  /// scene and the accents.
  static ({Color wash, Color ink}) paletteFor(ActivityType type) {
    return switch (type) {
      ActivityType.movement => (
        wash: const Color(0xFFFFF4E0),
        ink: const Color(0xFFB4793A),
      ),
      ActivityType.social => (
        wash: const Color(0xFFFFEDE6),
        ink: const Color(0xFFC2694A),
      ),
      ActivityType.creative => (
        wash: const Color(0xFFF6ECFF),
        ink: const Color(0xFF8A5FBF),
      ),
      ActivityType.nature => (
        wash: const Color(0xFFE9F5E6),
        ink: const Color(0xFF4F8A52),
      ),
      ActivityType.mindfulness => (
        wash: const Color(0xFFE7F2F7),
        ink: const Color(0xFF3F7C93),
      ),
      ActivityType.learning => (
        wash: const Color(0xFFFFF2DC),
        ink: const Color(0xFFA97B2E),
      ),
      ActivityType.productivity => (
        wash: const Color(0xFFEDEBF8),
        ink: const Color(0xFF6A63A8),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(activity.type);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.wash,
            Color.lerp(palette.wash, palette.ink, 0.14)!,
          ],
        ),
        border: Border.all(color: palette.ink.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // The scene is the background, not a badge beside the words. It gets
            // its own column on the right so the figure stands whole, and stops
            // short of the bottom so it never sits under the buttons.
            Positioned(
              right: 6,
              top: 8,
              bottom: 54,
              width: 132,
              child: ActivityScene(type: activity.type, color: palette.ink),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    // Keeps the words in their own column, clear of the art.
                    constraints: const BoxConstraints(maxWidth: 196),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      child: sayingGoodbye
                          ? Text(
                              'Okay, have a nice day.',
                              key: const ValueKey('goodbye'),
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 21,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            )
                          : Column(
                              key: const ValueKey('suggestion'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activity.title,
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontSize: 20,
                                    height: 1.22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  activity.description,
                                  style: TextStyle(
                                    color: palette.ink.withValues(alpha: 0.68),
                                    fontSize: 12.5,
                                    height: 1.42,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _AnswerButton(
                        key: const ValueKey('suggestion-decline'),
                        kind: _AnswerKind.no,
                        ink: palette.ink,
                        tooltip: 'Not today',
                        onPressed: onDecline,
                      ),
                      const SizedBox(width: 12),
                      _AnswerButton(
                        key: const ValueKey('suggestion-accept'),
                        kind: _AnswerKind.yes,
                        ink: palette.ink,
                        tooltip: 'I did it',
                        onPressed: onAccept,
                      ),
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

enum _AnswerKind { yes, no }

/// The two answers, drawn rather than using icon glyphs so their weight matches
/// the card and they never depend on a font being present.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.kind,
    required this.ink,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final _AnswerKind kind;
  final Color ink;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isYes = kind == _AnswerKind.yes;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isYes ? ink : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isYes
                  ? null
                  : Border.all(color: ink.withValues(alpha: 0.35), width: 1.5),
            ),
            child: CustomPaint(
              painter: _AnswerPainter(
                kind: kind,
                color: isYes ? const Color(0xFFFFFDF8) : ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerPainter extends CustomPainter {
  _AnswerPainter({required this.kind, required this.color});

  final _AnswerKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final centre = Offset(size.width / 2, size.height / 2);
    final unit = size.width;

    if (kind == _AnswerKind.yes) {
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - unit * 0.16, centre.dy + unit * 0.01)
          ..lineTo(centre.dx - unit * 0.05, centre.dy + unit * 0.12)
          ..lineTo(centre.dx + unit * 0.17, centre.dy - unit * 0.13),
        stroke,
      );
      return;
    }

    canvas.drawLine(
      Offset(centre.dx - unit * 0.11, centre.dy - unit * 0.11),
      Offset(centre.dx + unit * 0.11, centre.dy + unit * 0.11),
      stroke,
    );
    canvas.drawLine(
      Offset(centre.dx + unit * 0.11, centre.dy - unit * 0.11),
      Offset(centre.dx - unit * 0.11, centre.dy + unit * 0.11),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _AnswerPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
