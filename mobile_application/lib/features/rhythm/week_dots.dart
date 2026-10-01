import 'package:flutter/material.dart';

/// The last seven days, as marks.
///
/// Carries no words: the shape says what happened, and the whole row is the tap
/// target through to the rhythm page where a rest day can be declared. State is
/// encoded by shape rather than by a lighter tint, because a faded dot reads as
/// missing data rather than as a day someone chose to rest.
class WeekDots extends StatelessWidget {
  const WeekDots({
    required this.checkedIn,
    required this.rested,
    this.onTap,
    super.key,
  });

  /// Seven entries, oldest first, ending with today.
  final List<bool> checkedIn;
  final List<bool> rested;

  final VoidCallback? onTap;

  static const _accent = Color(0xFF8A5600);
  static const _idle = Color(0x334A3728);

  @override
  Widget build(BuildContext context) {
    assert(checkedIn.length == 7 && rested.length == 7);
    return Semantics(
      label: 'Your last seven days',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          // A 44px tall target even though the marks are 10px: the row is the
          // control, not the dots.
          height: 44,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: _Dot(
                    isToday: i == 6,
                    isCheckedIn: checkedIn[i],
                    isRest: rested[i],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.isToday,
    required this.isCheckedIn,
    required this.isRest,
  });

  final bool isToday;
  final bool isCheckedIn;
  final bool isRest;

  @override
  Widget build(BuildContext context) {
    final filled = isCheckedIn;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? WeekDots._accent : Colors.transparent,
        border: filled
            ? null
            : Border.all(
                color: isRest
                    ? WeekDots._idle.withValues(alpha: 0.75)
                    : WeekDots._idle,
                width: 1.6,
              ),
        // Today is a ring rather than a colour, so the most alert-like hue in
        // the app is never spent on "the most recent day".
        boxShadow: isToday
            ? const [
                BoxShadow(color: WeekDots._accent, spreadRadius: 2.6),
              ]
            : null,
      ),
    );
  }
}
