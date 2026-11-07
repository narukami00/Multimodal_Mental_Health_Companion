import '../../core/constants/moods.dart';
import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../core/models/suggestion_record.dart';
import '../goals/goals.dart';

/// A one-page overview the person can choose to hand to a therapist, made only from what they have entered or allowed
/// on their phone. It describes and counts; it never diagnoses, scores or advises. What leaves the phone is up to
/// them: it is only a file they save.
///
/// The person's own words are left out unless they switch them on.
class TherapistSummary {
  const TherapistSummary({
    required this.name,
    required this.from,
    required this.to,
    required this.days,
    required this.entries,
    required this.activeDays,
    required this.voiceOrVideo,
    required this.moods,
    required this.ideasTried,
    required this.ideasLifted,
    required this.phone,
    required this.goals,
    required this.words,
  });

  final String? name;

  /// The first and last day covered (date only), and how many days that is.
  final DateTime from;
  final DateTime to;
  final int days;

  final int entries;
  final int activeDays;
  final int voiceOrVideo;

  /// How often each mood word came up, in the person's plain words (Upbeat, Calm, Even, Low, Tense), most first.
  final List<MapEntry<String, int>> moods;

  final int ideasTried;

  /// Of the ideas where they said how they felt before and after, how many they felt lighter after.
  final int ideasLifted;

  final PhoneOverview? phone;
  final List<GoalOverview> goals;

  /// Short pieces of their own entries, newest first; empty unless they chose to include them.
  final List<WordsExcerpt> words;
}

class PhoneOverview {
  const PhoneOverview({
    required this.daysRead,
    this.typicalScreenMinutes,
    this.typicalPickups,
    this.typicalLateNightMinutes,
    this.typicalFirstPickupMinute,
  });

  final int daysRead;

  /// The typical (median) day over the period.
  final int? typicalScreenMinutes;
  final int? typicalPickups;
  final int? typicalLateNightMinutes;
  final int? typicalFirstPickupMinute;
}

class GoalOverview {
  const GoalOverview({required this.title, required this.target, required this.met, required this.judged});
  final String title;

  /// "At most 3 h".
  final String target;
  final int met;
  final int judged;
}

class WordsExcerpt {
  const WordsExcerpt(this.day, this.text);
  final DateTime day;
  final String text;
}

/// How many characters of one entry are kept when words are included.
const excerptLength = 220;

/// Builds the summary for the [days] days ending on [now] (today included).
TherapistSummary buildTherapistSummary({
  required List<SessionRecord> sessions,
  required List<SuggestionRecord> ideas,
  required List<DailyFeatures> phoneRows,
  required List<Goal> goals,
  required List<GoalDay> goalDays,
  required DateTime now,
  int days = 30,
  String? name,
  bool includeWords = false,
  int maxExcerpts = 6,
}) {
  final to = dateOnly(now);
  final from = DateTime(to.year, to.month, to.day - (days - 1));
  bool inRange(DateTime at) => !dateOnly(at).isBefore(from) && !dateOnly(at).isAfter(to);

  final mine = [for (final s in sessions) if (inRange(s.createdAt)) s]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final moodCounts = <String, int>{};
  for (final s in mine) {
    final mood = s.effectiveMood;
    if (mood == null || Moods.score(mood) == null) continue;
    final word = Moods.display(mood);
    moodCounts[word] = (moodCounts[word] ?? 0) + 1;
  }
  final moods = moodCounts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });

  final tried = [for (final r in ideas) if (r.done == true && inRange(r.completedAt ?? r.acceptedAt ?? r.shownAt)) r];
  var lifted = 0;
  for (final r in tried) {
    final before = Moods.score(r.moodBefore), after = Moods.score(r.moodAfter);
    if (before != null && after != null && after > before) lifted++;
  }

  return TherapistSummary(
    name: (name?.trim().isEmpty ?? true) ? null : name!.trim(),
    from: from,
    to: to,
    days: days,
    entries: mine.length,
    activeDays: {for (final s in mine) dayKey(s.createdAt)}.length,
    voiceOrVideo: mine.where((s) => s.mode != CaptureMode.text).length,
    moods: moods,
    ideasTried: tried.length,
    ideasLifted: lifted,
    phone: _phone(phoneRows, from, to),
    goals: _goals(goals, goalDays, from, to),
    words: includeWords
        ? [
            for (final s in mine)
              if ((s.text ?? '').trim().isNotEmpty) WordsExcerpt(dateOnly(s.createdAt), _excerpt(s.text!)),
          ].take(maxExcerpts).toList()
        : const [],
  );
}

String _excerpt(String text) {
  final one = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return one.length <= excerptLength ? one : '${one.substring(0, excerptLength).trimRight()}…';
}

int? _median(Iterable<int?> values) {
  final v = [for (final x in values) ?x]..sort();
  return v.isEmpty ? null : v[v.length ~/ 2];
}

PhoneOverview? _phone(List<DailyFeatures> rows, DateTime from, DateTime to) {
  final fromKey = dayKey(from), toKey = dayKey(to);
  final read = [
    for (final r in rows)
      if (r.hasUsage && r.usageComplete && r.dayKey.compareTo(fromKey) >= 0 && r.dayKey.compareTo(toKey) <= 0) r,
  ];
  if (read.isEmpty) return null;
  return PhoneOverview(
    daysRead: read.length,
    typicalScreenMinutes: _median(read.map((r) => r.screenOnMinutes)),
    typicalPickups: _median(read.map((r) => r.unlockCount)),
    typicalLateNightMinutes: _median(read.map((r) => r.screenMinutesInSleepWindow)),
    typicalFirstPickupMinute: _median(read.map((r) => r.firstPickupMinute)),
  );
}

List<GoalOverview> _goals(List<Goal> goals, List<GoalDay> goalDays, DateTime from, DateTime to) {
  final fromKey = dayKey(from), toKey = dayKey(to);
  return [
    for (final g in goals)
      () {
        var met = 0, judged = 0;
        for (final d in goalDays) {
          if (d.day.compareTo(fromKey) < 0 || d.day.compareTo(toKey) > 0) continue;
          final outcome = d.results[g.id]?.outcome;
          if (outcome == GoalOutcome.met) {
            met++;
            judged++;
          } else if (outcome == GoalOutcome.notThisTime) {
            judged++;
          }
        }
        return GoalOverview(
          title: g.measure.title,
          target: '${g.measure.stem} ${describeGoalValue(g.measure, g.target)}${g.weekdaysOnly ? ' (weekdays)' : ''}',
          met: met,
          judged: judged,
        );
      }(),
  ];
}
