/// Pure scheduling maths for the daily reminder.
///
/// Kept free of Flutter and plugins so the "next reminder" label can be
/// computed and verified without a platform.
abstract final class ReminderSchedule {
  /// The next time the reminder will fire at [minutesPastMidnight].
  ///
  /// Today when that time is still ahead, otherwise tomorrow.
  static DateTime nextOccurrence(int minutesPastMidnight, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final today = DateTime(
      current.year,
      current.month,
      current.day,
      (minutesPastMidnight ~/ 60) % 24,
      minutesPastMidnight % 60,
    );
    if (today.isAfter(current)) return today;
    return today.add(const Duration(days: 1));
  }

  /// Whether the reminder fires later today rather than tomorrow.
  static bool isToday(int minutesPastMidnight, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final next = nextOccurrence(minutesPastMidnight, now: current);
    return next.day == current.day && next.month == current.month;
  }
}
