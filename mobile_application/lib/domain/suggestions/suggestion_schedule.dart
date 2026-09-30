import '../../core/models/suggestion_record.dart';

/// Decides whether a suggestion is due to be offered right now.
///
/// Pure by design: it reads history and never writes. Home asks this question on
/// every rebuild, and writing a record there would inflate the very counts the
/// confidence gate depends on.
class SuggestionSchedule {
  const SuggestionSchedule();

  /// Minimum spacing between suggestions, so two never arrive at once.
  static const minimumGap = Duration(hours: 4);

  /// One a day for the first fortnight, two a day after that.
  static const earlyDays = 14;

  bool isDue({
    required List<SuggestionRecord> history,
    required int? profileAgeDays,
    required bool checkInCompletedToday,
    required DateTime now,
  }) {
    // The first slot sits straight after the day's check-in, so an idea arrives
    // as a follow-on from reflecting rather than as a separate demand.
    if (!checkInCompletedToday) return false;

    final shownToday = history
        .where((record) => _sameDate(record.shownAt, now))
        .length;
    final cap = (profileAgeDays ?? earlyDays) < earlyDays ? 1 : 2;
    if (shownToday >= cap) return false;

    if (history.isEmpty) return true;
    final last = history.reduce(
      (a, b) => a.shownAt.isAfter(b.shownAt) ? a : b,
    );
    return now.difference(last.shownAt) >= minimumGap;
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
