import '../../core/constants/moods.dart';
import '../../core/day_key.dart';
import '../../core/models/session_record.dart';

/// One mood score per day, oldest first, for the last [days] days up to and
/// including today. A day is the median of the mood words chosen that day, and
/// a day with no mood word is left out rather than filled in.
///
/// Feeds the short trend in the capacity estimate. The scores are an ordering
/// of the five mood words, so only the direction over a few days is meaningful.
List<double> dailyMoodScores({
  required List<SessionRecord> sessions,
  required DateTime now,
  int days = 5,
}) {
  final scoresByDay = <String, List<double>>{};
  for (final session in sessions) {
    final score = Moods.score(session.mood);
    if (score == null) continue;
    scoresByDay.putIfAbsent(dayKey(session.createdAt), () => []).add(score);
  }

  final today = dateOnly(now);
  final result = <double>[];
  for (var back = days - 1; back >= 0; back--) {
    final day = DateTime(today.year, today.month, today.day - back);
    final scores = scoresByDay[dayKey(day)];
    if (scores == null) continue;
    final sorted = [...scores]..sort();
    final middle = sorted.length ~/ 2;
    result.add(
      sorted.length.isOdd
          ? sorted[middle]
          : (sorted[middle - 1] + sorted[middle]) / 2,
    );
  }
  return result;
}
