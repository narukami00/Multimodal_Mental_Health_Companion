import 'package:flutter/material.dart';

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

  Future<void> _declineTask() async {
    if (_taskLeaving) return;
    setState(() => _taskLeaving = true);
    // Let the task wipe away before the card closes up, so the two motions read
    // as one gesture rather than as a flicker followed by a jump.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    widget.onTaskDecline?.call();
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      color: const Color(0xFFFFF6E4),
      child: Column(
        children: [
          if (widget.eyebrow != null) ...[
            Text(
              widget.eyebrow!.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                // Darkened amber. At the old value this sat near 2.6:1, which is
                // unreadable on a low-end panel in daylight.
                color: Color(0xFF8A5600),
              ),
            ),
            const SizedBox(height: 9),
          ],
          Text(
            widget.headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              height: 1.22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Color(0xFF4A3728),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              // Was 7B6A55 at this size, which measured about 3.1:1.
              color: Color(0xFF5F4E3A),
            ),
          ),
          const SizedBox(height: 15),
          // A bright orange gradient, not the dark brown that was here before.
          // That colour was never part of the app's palette, and dark ink on
          // bright orange is both on-brand and readable, where white on the
          // previous amber measured about 2:1.
          _OrangeButton(
            label: widget.ctaLabel,
            onPressed: widget.onCta,
            height: 46,
            radius: 999,
            horizontalPadding: 26,
            prominent: true,
          ),
        ],
      ),
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
                onPressed: widget.onTaskAccept,
              ),
              const SizedBox(width: 9),
              _TaskButton(
                key: const ValueKey('task-decline'),
                label: task.declineLabel,
                filled: false,
                onPressed: _declineTask,
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

/// The app's own orange, as a button.
///
/// Dark ink on a bright orange gradient: the brown fill this replaces was never
/// in the palette, and white on amber measured around 2:1, which is unreadable
/// on a low-end panel in daylight.
class _OrangeButton extends StatelessWidget {
  const _OrangeButton({
    required this.label,
    required this.onPressed,
    required this.height,
    required this.radius,
    required this.horizontalPadding,
    required this.prominent,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double radius;
  final double horizontalPadding;
  final bool prominent;

  static const _ink = Color(0xFF3F2A0E);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: prominent
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFC24F), Color(0xFFF09A18)],
              )
            : null,
        border: prominent
            ? null
            : Border.all(color: const Color(0x2E4A3728), width: 1.4),
        boxShadow: prominent
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
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: prominent ? _ink : const Color(0xFF5F4E3A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
