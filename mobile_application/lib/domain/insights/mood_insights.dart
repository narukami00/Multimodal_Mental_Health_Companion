import '../../core/constants/moods.dart';
import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../../core/models/session_record.dart';
import '../footprint/personal_baseline.dart';

/// One calendar day in the mood strip.
class MoodDay {
  const MoodDay({required this.day, this.mood, this.checkIns = 0});

  final DateTime day;

  /// The mood word chosen most often that day (the latest, on a tie). Null when
  /// no mood word was chosen: a gap is a gap, never filled in.
  final String? mood;
  final int checkIns;
}

/// The last [days] days, oldest first, ending today. Always exactly [days] long.
List<MoodDay> moodStrip(List<SessionRecord> sessions, DateTime now, {int days = 30}) {
  final byDay = <String, List<SessionRecord>>{};
  for (final session in sessions) {
    if (Moods.score(session.mood) == null) continue;
    byDay.putIfAbsent(dayKey(session.createdAt), () => []).add(session);
  }
  final today = dateOnly(now);
  return [
    for (var back = days - 1; back >= 0; back--)
      () {
        final day = DateTime(today.year, today.month, today.day - back);
        final entries = byDay[dayKey(day)];
        if (entries == null) return MoodDay(day: day);
        entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final counts = <String, int>{};
        for (final e in entries) {
          final word = Moods.values.firstWhere(
            (m) => m.toLowerCase() == e.mood!.trim().toLowerCase(),
          );
          counts[word] = (counts[word] ?? 0) + 1;
        }
        final top = counts.values.reduce((a, b) => a > b ? a : b);
        // Latest check-in among the most frequent words wins a tie.
        final word = Moods.values.firstWhere(
          (m) => counts[m] == top && m.toLowerCase() == entries.last.mood!.trim().toLowerCase(),
          orElse: () => counts.entries.firstWhere((e) => e.value == top).key,
        );
        return MoodDay(day: day, mood: word, checkIns: entries.length);
      }(),
  ];
}

/// A plain summary of a strip: how many days have a mood and which word came up
/// most. Null when there is nothing to say.
String? moodStripSummary(List<MoodDay> strip) {
  final withMood = [for (final d in strip) if (d.mood != null) d];
  if (withMood.isEmpty) return null;
  final counts = <String, int>{};
  for (final d in withMood) {
    counts[d.mood!] = (counts[d.mood!] ?? 0) + 1;
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  final top = ranked.first;
  final days = withMood.length;
  return 'You checked in on $days of the last ${strip.length} days. '
      '${top.key} came up most, on ${top.value}.';
}

/// What can honestly be said about late nights and the mood words on the days
/// after. Descriptive only: it counts, and never says one caused the other.
class NightsAndMoods {
  const NightsAndMoods({
    required this.laterNights,
    required this.laterNightsLow,
    required this.usualNights,
    required this.usualNightsLow,
  });

  /// Days after a night the phone went down well later than usual, and how many
  /// of them had a lower mood word.
  final int laterNights;
  final int laterNightsLow;
  final int usualNights;
  final int usualNightsLow;

  String get text =>
      'After $laterNights nights your phone went down later than usual, '
      '$laterNightsLow of the next days had a lower mood word. After your usual '
      'nights, $usualNightsLow of $usualNights did. These tended to coincide; '
      'it does not mean one caused the other.';
}

/// Pairs each finished night with the mood word chosen the next day.
///
/// Needs [minDays] paired days overall and [minEach] in each group, otherwise
/// null. A "later" night is one where the phone went down at least
/// [laterByMinutes] after this person's own median.
NightsAndMoods? nightsAndMoods(
  List<DailyFeatures> rows,
  List<SessionRecord> sessions, {
  int minDays = 14,
  int minEach = 4,
  int laterByMinutes = 45,
}) {
  final starts = <String, int>{};
  for (final row in rows) {
    final start = row.estimatedSleepStartMinute;
    if (row.hasUsage && row.usageComplete && start != null) {
      // Minutes after 6 PM, so a night that crosses midnight is one run of numbers.
      starts[row.dayKey] = (start - 18 * 60 + 1440) % 1440;
    }
  }
  final usual = median([for (final v in starts.values) v.toDouble()]);
  if (usual == null) return null;

  final scoresByDay = <String, List<double>>{};
  for (final s in sessions) {
    final score = Moods.score(s.mood);
    if (score != null) scoresByDay.putIfAbsent(dayKey(s.createdAt), () => []).add(score);
  }

  var later = 0, laterLow = 0, normal = 0, normalLow = 0;
  for (final entry in starts.entries) {
    final next = dayKey(
      DateTime.parse(entry.key).add(const Duration(days: 1)),
    );
    final scores = scoresByDay[next];
    if (scores == null) continue;
    final sorted = [...scores]..sort();
    final mid = sorted.length ~/ 2;
    final day = sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    final low = day < 0;
    if (entry.value - usual >= laterByMinutes) {
      later++;
      if (low) laterLow++;
    } else {
      normal++;
      if (low) normalLow++;
    }
  }
  if (later + normal < minDays || later < minEach || normal < minEach) return null;
  return NightsAndMoods(
    laterNights: later,
    laterNightsLow: laterLow,
    usualNights: normal,
    usualNightsLow: normalLow,
  );
}
