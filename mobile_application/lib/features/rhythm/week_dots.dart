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

  static const _accent = Color(0xFFC87F10);
  static const _rest = Color(0xFFE8604C);
  static const _idle = Color(0x2E4A3728);
  /// Today is a very pale orange rather than a ring or a bright fill: the
  /// position already says which day it is, so the mark only needs to warm it.
  static const _today = Color(0xFFFFDCB0);

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
          // A 44px tall target even though the marks are small: the row is the
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
    // A check-in is the accent orange, filled. A rest day is a red wash rather
    // than a solid fill, so it reads as something the user chose rather than as
    // an alarm. Neither uses the dark brown that was there before.
    final Color fill;
    if (isCheckedIn) {
      fill = WeekDots._accent;
    } else if (isRest) {
      fill = WeekDots._rest.withValues(alpha: 0.28);
    } else {
      fill = WeekDots._idle;
    }

    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isToday ? WeekDots._today : fill,
        border: isRest && !isCheckedIn
            ? Border.all(
                color: WeekDots._rest.withValues(alpha: 0.75),
                width: 1.2,
              )
            : null,
      ),
    );
  }
}
