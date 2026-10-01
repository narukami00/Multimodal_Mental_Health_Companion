/// When, if at all, to push "you have an idea" over the next few days.
///
/// Pure, like `SuggestionSchedule`: it is given the facts and returns times, so
/// every rule can be checked without a device. Push is local, so it can only
/// say an idea is waiting, never which one.
///
/// Budget: one idea push a day beside the one check-in reminder is exactly the
/// two-a-day ceiling, so the ceiling holds by construction. A future crisis
/// tier would be the only thing allowed past it.
abstract final class SuggestionPushPlan {
  /// Days ahead that get a push. Doubles as the lapse rule: once someone has
  /// been away three days the plan runs dry on its own, so a person who stops
  /// opening the app stops being nudged without anything needing to run.
  static const horizonDays = 3;

  /// Where the day's push is first tried: mid-morning, a clear gap from the
  /// usual evening check-in reminder.
  static const baseMinutes = 10 * 60;

  /// A push that collides with the reminder, or lands in the sleep window,
  /// defers by this much, at most [maxDeferrals] times, then is dropped for the
  /// day. It never carries over, so nothing piles up.
  static const deferStep = 90;
  static const maxDeferrals = 2;

  /// Keeps an idea push this far from the check-in reminder. The reminder was
  /// asked for by the user, so it wins.
  static const reminderClearance = 60;

  /// Whether [minute] (past midnight) falls inside a sleep window. The window
  /// may cross midnight, which is the usual case: 22:00 to 07:00.
  static bool inQuietHours(int minute, int start, int end) {
    if (start == end) return false;
    return start < end
        ? minute >= start && minute < end
        : minute >= start || minute < end;
  }

  static List<DateTime> plan({
    required DateTime now,
    required bool enabled,
    required int? daysSinceLastCheckIn,
    required bool ideaOfferedToday,
    required bool reminderEnabled,
    required int reminderMinutes,
    required bool quietEnabled,
    required int quietStart,
    required int quietEnd,
  }) {
    if (!enabled) return const [];
    final away = daysSinceLastCheckIn ?? 0;
    final times = <DateTime>[];

    for (var day = 0; day < horizonDays; day++) {
      if (away + day >= horizonDays) break;
      if (day == 0 && ideaOfferedToday) continue;
      final midnight = DateTime(now.year, now.month, now.day + day);
      // Deferral is for collisions. If the usual time has simply passed, today
      // is over for pushes rather than slid later into the afternoon.
      if (!midnight.add(const Duration(minutes: baseMinutes)).isAfter(now)) {
        continue;
      }

      for (var attempt = 0; attempt <= maxDeferrals; attempt++) {
        final minute = baseMinutes + attempt * deferStep;
        final at = midnight.add(Duration(minutes: minute));
        if (quietEnabled && inQuietHours(minute, quietStart, quietEnd)) {
          continue;
        }
        if (reminderEnabled &&
            (minute - reminderMinutes).abs() < reminderClearance) {
          continue;
        }
        times.add(at);
        break;
      }
    }
    return times;
  }
}
