import '../../core/day_key.dart';
import '../../core/models/session_record.dart';
import '../../core/models/suggestion_record.dart';

/// A single day in the rhythm ribbon.
class RhythmDay {
  const RhythmDay({
    required this.date,
    required this.hasCheckIn,
    required this.isRestDay,
    required this.hasSuggestionOutcome,
    required this.isToday,
  });

  final DateTime date;
  final bool hasCheckIn;
  final bool isRestDay;

  /// Whether the user answered a suggestion that day. A skipped suggestion
  /// with a reason still counts: declining is a decision.
  final bool hasSuggestionOutcome;

  final bool isToday;

  /// A day counts as attended if the user made any deliberate decision about
  /// their own wellbeing — a check-in, a declared rest, or an answered
  /// suggestion.
  bool get attended => hasCheckIn || isRestDay || hasSuggestionOutcome;
}

/// The user's own typical week, shown only once there is enough history.
class RhythmUsual {
  const RhythmUsual({required this.daysPerWeek, required this.sampleWeeks});

  final int daysPerWeek;
  final int sampleWeeks;
}

/// Derived, read-only view of the last four weeks.
class RhythmSummary {
  const RhythmSummary({
    required this.days,
    required this.checkInCount,
    required this.restCount,
    this.usual,
  });

  /// Twenty-eight days, oldest first.
  final List<RhythmDay> days;
  final int checkInCount;
  final int restCount;

  /// Null when there is not enough history to say anything honest.
  final RhythmUsual? usual;

  bool get isEmpty => checkInCount == 0 && restCount == 0;

  /// The most recent seven days, for the compact home widget.
  List<RhythmDay> get recentWeek => days.length <= 7
      ? days
      : days.sublist(days.length - 7);
}

/// Aggregates check-ins, declared rest days and answered suggestions into the
/// rhythm view. Pure, so the rules can be verified directly.
///
/// Nothing here counts consecutive days, compares the user to other people, or
/// treats a gap as a debt.
RhythmSummary summariseRhythm({
  required List<SessionRecord> sessions,
  required Set<String> restDays,
  required List<SuggestionRecord> suggestions,
  DateTime? now,
  int windowDays = 28,
  int usualWeeks = 8,
  int minimumActiveWeeks = 3,
}) {
  final today = dateOnly(now ?? DateTime.now());

  final checkInDays = <String>{};
  for (final session in sessions) {
    checkInDays.add(dayKey(session.createdAt));
  }

  // Only answered suggestions count: a suggestion that was merely shown, and
  // then abandoned, is not a decision the user made.
  final suggestionDays = <String>{};
  for (final record in suggestions) {
    if (record.status == SuggestionStatus.shown) continue;
    suggestionDays.add(dayKey(record.shownAt));
  }

  final attendedDays = <String>{
    ...checkInDays,
    ...restDays,
    ...suggestionDays,
  };

  final days = <RhythmDay>[
    for (var offset = windowDays - 1; offset >= 0; offset--)
      _dayAt(
        today.subtract(Duration(days: offset)),
        checkInDays,
        restDays,
        suggestionDays,
        today,
      ),
  ];

  return RhythmSummary(
    days: days,
    checkInCount: days.where((day) => day.hasCheckIn).length,
    restCount: days.where((day) => day.isRestDay).length,
    usual: _usual(
      attendedDays: attendedDays,
      today: today,
      weeks: usualWeeks,
      minimumActiveWeeks: minimumActiveWeeks,
    ),
  );
}

RhythmDay _dayAt(
  DateTime date,
  Set<String> checkInDays,
  Set<String> restDays,
  Set<String> suggestionDays,
  DateTime today,
) {
  final key = dayKey(date);
  return RhythmDay(
    date: date,
    hasCheckIn: checkInDays.contains(key),
    isRestDay: restDays.contains(key),
    hasSuggestionOutcome: suggestionDays.contains(key),
    isToday: date == today,
  );
}

/// Median attended days per week across the trailing weeks that have any data.
///
/// Returns null unless enough weeks are populated, so the app never states a
/// "usual" based on a fortnight of noise.
RhythmUsual? _usual({
  required Set<String> attendedDays,
  required DateTime today,
  required int weeks,
  required int minimumActiveWeeks,
}) {
  final weeklyCounts = <int>[];
  for (var week = 0; week < weeks; week++) {
    final end = today.subtract(Duration(days: week * 7));

    var count = 0;
    for (var offset = 0; offset < 7; offset++) {
      if (attendedDays.contains(dayKey(end.subtract(Duration(days: offset))))) {
        count++;
      }
    }
    weeklyCounts.add(count);
  }

  // Weeks with no activity are excluded rather than counted as zeros: the
  // user's "usual" is derived from the weeks they actually used the app, so a
  // long gap cannot quietly drag their own baseline down to nothing.
  final activeCounts = weeklyCounts.where((count) => count > 0).toList();
  if (activeCounts.length < minimumActiveWeeks) return null;

  activeCounts.sort();
  final middle = activeCounts.length ~/ 2;
  final median = activeCounts.length.isOdd
      ? activeCounts[middle]
      : ((activeCounts[middle - 1] + activeCounts[middle]) / 2).round();

  return RhythmUsual(daysPerWeek: median, sampleWeeks: activeCounts.length);
}
