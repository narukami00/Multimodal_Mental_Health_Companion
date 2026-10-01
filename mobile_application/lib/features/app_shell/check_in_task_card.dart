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

/// The day's task, as offered inside the check-in card.
class TaskOffer {
  const TaskOffer({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.acceptLabel = "I'll try it",
    this.declineLabel = 'Not now',
  });

  final String eyebrow;
  final String title;
  final String description;
  final String acceptLabel;
  final String declineLabel;
}

/// One card holding both the daily check-in and the day's task.
///
/// They belong together: the task is a follow-on from reflecting, not a separate
/// demand, and two stacked cards made it look like two things to do. When the
/// task is declined it wipes away and the card closes up to just the check-in,
/// so declining costs the user a card's worth of attention and nothing else.
class CheckInTaskCard extends StatefulWidget {
  const CheckInTaskCard({
    required this.headline,
    required this.subtitle,
    required this.ctaLabel,
    this.eyebrow,
    this.onCta,
    this.task,
    this.onTaskAccept,
    this.onTaskOpen,
    this.onTaskDecline,
    super.key,
  });

  final String? eyebrow;
  final String headline;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback? onCta;

  final TaskOffer? task;
  final VoidCallback? onTaskAccept;
  final VoidCallback? onTaskOpen;

  /// Called once the task has finished wiping away, so the parent can drop it.
  final VoidCallback? onTaskDecline;

  @override
  State<CheckInTaskCard> createState() => _CheckInTaskCardState();
}

class _CheckInTaskCardState extends State<CheckInTaskCard> {
  bool _taskLeaving = false;

  @override
  void didUpdateWidget(CheckInTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A replacement task has to arrive visible. Without this reset it inherited
    // the previous one's faded-out state, so declining left the card looking
    // blank even though a new task had already been chosen for it.
    if (widget.task?.title != oldWidget.task?.title) {
      _taskLeaving = false;
    }
  }

  Future<void> _dismissTask(VoidCallback? then) async {
    if (_taskLeaving) return;
    setState(() => _taskLeaving = true);
    // Let the task wipe away before the card closes up, so the two motions read
    // as one gesture rather than as a flicker followed by a jump.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    then?.call();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;

    return AnimatedSize(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: const Color(0xFFFFFDF8),
          border: Border.all(color: const Color(0x144A3728)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14120C04),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCheckIn(context),
              if (task != null)
                AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInCubic,
                  offset: _taskLeaving
                      ? const Offset(0, 0.10)
                      : Offset.zero,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _taskLeaving ? 0 : 1,
                    // The whole task is a tap target, not just its buttons:
                    // tapping the idea itself is the obvious thing to try, and
                    // it opens the full details.
                    child: GestureDetector(
                      onTap: widget.onTaskOpen,
                      behavior: HitTestBehavior.opaque,
                      child: _buildTask(context, task),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckIn(BuildContext context) {
    return _CheckInPanel(
      eyebrow: widget.eyebrow,
      headline: widget.headline,
      subtitle: widget.subtitle,
      ctaLabel: widget.ctaLabel,
      onCta: widget.onCta,
    );
  }

  Widget _buildTask(BuildContext context, TaskOffer task) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 15),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x144A3728))),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E4), Color(0xFFFDECCE)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.eyebrow.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: Color(0xFF8A5600),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            task.title,
            style: const TextStyle(
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: Color(0xFF4A3728),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            task.description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFF5F4E3A),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TaskButton(
                key: const ValueKey('task-accept'),
                label: task.acceptLabel,
                filled: true,
                onPressed: () => _dismissTask(widget.onTaskAccept),
              ),
              const SizedBox(width: 12),
              _TaskButton(
                key: const ValueKey('task-decline'),
                label: task.declineLabel,
                filled: false,
                onPressed: () => _dismissTask(widget.onTaskDecline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskButton extends StatelessWidget {
  const _TaskButton({
    required this.label,
    required this.filled,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _OrangeButton(
      label: label,
      onPressed: onPressed,
      height: 44,
      radius: 13,
      horizontalPadding: 20,
      prominent: filled,
    );
  }
}

/// The check-in half: a saturated orange panel with a slowly sweeping gradient
/// and a rotating sun behind the words.
///
/// This is deliberately the loudest thing on the screen. It is the one action
/// the app wants someone to take, and with everything at equal weight nobody
/// knows where to start.
class _CheckInPanel extends StatefulWidget {
  const _CheckInPanel({
    required this.headline,
    required this.subtitle,
    required this.ctaLabel,
    this.eyebrow,
    this.onCta,
  });

  final String? eyebrow;
  final String headline;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback? onCta;

  @override
  State<_CheckInPanel> createState() => _CheckInPanelState();
}

class _CheckInPanelState extends State<_CheckInPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void initState() {
    super.initState();
    if (!_isTestEnvironment) _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) {
        final t = _sweep.value;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            // The gradient rotates through a full turn, so the end of the cycle
            // is the same as the start. Sweeping the begin/end alignment instead
            // reached the end of its travel and snapped back, which read as a
            // visible pop every loop.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFFFFC85A),
                Color(0xFFF5A01C),
                Color(0xFFFFB534),
                Color(0xFFF09A18),
              ],
              stops: const [0.0, 0.35, 0.7, 1.0],
              transform: GradientRotation(t * 2 * math.pi),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -26,
                top: -32,
                child: _Sun(rotation: t * 2 * math.pi, size: 150),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Column(
                  // Left-aligned, reading left to right, rather than centred:
                  // a centred block reads as a poster, and this is a thing to do.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.eyebrow != null) ...[
                      Text(
                        widget.eyebrow!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: const Color(0xFF4A3213).withValues(
                            alpha: 0.78,
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                    Text(
                      widget.headline,
                      style: const TextStyle(
                        // Larger than it was: this question is the focal point of
                        // the page, and at 20 it sat at the same weight as
                        // everything else around it.
                        fontSize: 23,
                        height: 1.18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        color: Color(0xFF3F2A0E),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF3F2A0E).withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Inverted from the panel: a light pill on the orange,
                    // rather than an orange pill on a pale card. It reads as the
                    // one thing to press instead of blending into the page.
                    _OrangeButton(
                      label: widget.ctaLabel,
                      onPressed: widget.onCta,
                      height: 48,
                      radius: 999,
                      horizontalPadding: 30,
                      prominent: false,
                      light: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A slowly rotating sun, sitting behind the check-in copy.
class _Sun extends StatelessWidget {
  const _Sun({required this.rotation, required this.size});

  final double rotation;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SunPainter()),
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final core = size.width * 0.22;

    canvas.drawCircle(
      centre,
      core,
      Paint()..color = const Color(0xFFFFF3D6).withValues(alpha: 0.34),
    );

    final ray = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.028
      ..color = const Color(0xFFFFF3D6).withValues(alpha: 0.30);

    for (var i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi;
      final long = i.isEven;
      final from = core * (long ? 1.5 : 1.45);
      final to = core * (long ? 2.5 : 2.05);
      canvas.drawLine(
        Offset(
          centre.dx + from * math.cos(angle),
          centre.dy + from * math.sin(angle),
        ),
        Offset(
          centre.dx + to * math.cos(angle),
          centre.dy + to * math.sin(angle),
        ),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SunPainter oldDelegate) => false;
}

/// The small orange disc at the head of the check-in button, carrying a tick.
///
/// It echoes the sun already painted on the panel, which gives the button a
/// shape of its own instead of being a label in a box. The tick is drawn rather
/// than set in an icon font, because the Material icon font is not present in
/// this build and every glyph from it renders as a tofu box.
class _TickDisc extends StatelessWidget {
  const _TickDisc();

  static const _diameter = 36.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _diameter,
      height: _diameter,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFC24F), Color(0xFFEE8B0C)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x73106904),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(painter: _TickPainter()),
    );
  }
}

class _TickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.72, size.height * 0.36);

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _TickPainter oldDelegate) => false;
}

/// The app's own orange, as a button.
///
/// Dark ink on a bright orange gradient. The brown fill this replaces was never
/// in the palette, and white on amber measures around 2:1, which is unreadable
/// on a low-end panel in daylight.
class _OrangeButton extends StatelessWidget {
  const _OrangeButton({
    required this.label,
    required this.onPressed,
    required this.height,
    required this.radius,
    required this.horizontalPadding,
    required this.prominent,
    this.light = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double radius;
  final double horizontalPadding;
  final bool prominent;

  /// A pale pill for use on the orange panel, where an orange button would
  /// disappear into its own background.
  final bool light;

  static const _ink = Color(0xFF3F2A0E);

  @override
  Widget build(BuildContext context) {
    final solid = prominent || light;
    final ink = solid ? _ink : const Color(0xFF5F4E3A);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: prominent
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFC24F), Color(0xFFF09A18)],
              )
            : light
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFF4E2)],
              )
            : null,
        border: prominent
            ? null
            : light
            ? null
            : Border.all(color: const Color(0x2E4A3728), width: 1.2),
        // Two shadows on the cream pill: a tight one for contact and a wider,
        // slightly spread-negative one for lift. A single shadow reads flat.
        boxShadow: light
            ? const [
                BoxShadow(
                  color: Color(0x33704004),
                  blurRadius: 3,
                  offset: Offset(0, 2),
                ),
                BoxShadow(
                  color: Color(0x57704004),
                  blurRadius: 22,
                  spreadRadius: -4,
                  offset: Offset(0, 10),
                ),
              ]
            : prominent
            ? const [
                BoxShadow(
                  color: Color(0x33E08A10),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            height: height,
            padding: light
                ? const EdgeInsets.only(left: 7, right: 26)
                : EdgeInsets.symmetric(horizontal: horizontalPadding),
            // widthFactor 1 makes the button hug its own content. Without it a
            // Container carrying an alignment expands to whatever width its
            // parent offers, turning a capsule into a full-width bar.
            child: Center(
              widthFactor: 1,
              child: light
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _TickDisc(),
                        const SizedBox(width: 11),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: ink,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        color: ink,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
