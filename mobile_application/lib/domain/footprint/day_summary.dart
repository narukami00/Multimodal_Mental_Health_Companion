import '../../core/models/daily_features.dart';

/// One day of phone patterns, reduced to what is worth saying plainly.
///
/// Pure and descriptive only: it states what the numbers are, never whether they
/// are good or bad, and never compares anyone to anyone else. Every field is
/// null when the row did not collect it, so the page can leave a line out
/// instead of showing a zero it does not know.
class DaySummary {
  const DaySummary({
    required this.dayKey,
    this.screenOn,
    this.pickups,
    this.longestStretch,
    this.busiestHour,
    this.sleepStartMinute,
    this.sleepEndMinute,
    this.sleepMinutes,
    this.topCategories = const [],
  });

  /// Builds a summary from a stored row.
  factory DaySummary.of(DailyFeatures row) {
    final screen = row.screenOnMinutes;
    final longest = row.longestSessionMinutes;
    final hours = row.hourlyActiveMinutes;

    int? busiest;
    if (hours != null) {
      var best = 0;
      for (var hour = 0; hour < hours.length; hour++) {
        // Strictly greater, so the earlier hour wins a tie and the answer is
        // reproducible.
        if (hours[hour] > best) {
          best = hours[hour];
          busiest = hour;
        }
      }
      // A busiest hour of a few minutes is not a pattern.
      if (best < _minBusiestMinutes) busiest = null;
    }

    final categories = [...?row.categoryMinutes?.entries]
      ..removeWhere((entry) => entry.value <= 0)
      ..sort((a, b) {
        final byTime = b.value.compareTo(a.value);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });

    return DaySummary(
      dayKey: row.dayKey,
      screenOn: screen == null ? null : Duration(minutes: screen),
      pickups: row.sessionCount,
      longestStretch: longest == null || longest == 0
          ? null
          : Duration(minutes: longest),
      busiestHour: busiest,
      sleepStartMinute: row.estimatedSleepStartMinute,
      sleepEndMinute: row.estimatedSleepEndMinute,
      sleepMinutes: row.estimatedSleepMinutes,
      topCategories: [
        for (final entry in categories.take(2))
          (name: entry.key, minutes: entry.value),
      ],
    );
  }

  /// The least minutes in a single hour for it to be called the busiest.
  static const _minBusiestMinutes = 10;

  final String dayKey;
  final Duration? screenOn;
  final int? pickups;
  final Duration? longestStretch;
  final int? busiestHour;

  /// A sleep estimate, as minutes of the day and a length. Phone-down to
  /// phone-pickup, so it runs a little long and is only ever an estimate.
  final int? sleepStartMinute;
  final int? sleepEndMinute;
  final int? sleepMinutes;

  /// The two categories with the most time, most first.
  final List<({String name, int minutes})> topCategories;

  bool get isEmpty =>
      screenOn == null &&
      pickups == null &&
      sleepMinutes == null &&
      topCategories.isEmpty;
}

/// The most recent day with any phone-pattern data that has finished, so a day
/// still in progress is never described as if it were complete. Null if there is
/// none.
DailyFeatures? latestFinishedDay(List<DailyFeatures> rows, DateTime now) {
  final today = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  DailyFeatures? best;
  for (final row in rows) {
    if (!row.hasUsage || row.dayKey.compareTo(today) >= 0) continue;
    if (best == null || row.dayKey.compareTo(best.dayKey) > 0) best = row;
  }
  return best;
}

/// Screen minutes for each of the last [days] days ending today, oldest first.
/// A day with no usage data is null: not zero, since nothing was observed.
List<({DateTime day, int? minutes})> recentScreenMinutes(
  List<DailyFeatures> rows,
  DateTime now, {
  int days = 7,
}) {
  final byDay = {for (final row in rows) row.dayKey: row};
  final result = <({DateTime day, int? minutes})>[];
  for (var back = days - 1; back >= 0; back--) {
    final day = DateTime(now.year, now.month, now.day - back);
    final key = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final row = byDay[key];
    result.add((
      day: day,
      minutes: row != null && row.hasUsage ? row.screenOnMinutes : null,
    ));
  }
  return result;
}
