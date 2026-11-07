import '../../core/constants/moods.dart';
import '../../core/day_key.dart';
import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../core/models/suggestion_record.dart';

/// One finished week (Monday to Sunday), described plainly from what the person did and shared.
///
/// It only ever describes: it counts, it never compares one week with another, never calls a week good or bad, and
/// never says anything was missed. A quiet week is just a quiet week.
class WeekRecap {
  const WeekRecap({
    required this.weekStart,
    required this.activeDays,
    required this.entries,
    required this.voiceOrVideo,
    required this.tasksDone,
    required this.topMood,
    required this.dayHasEntry,
    required this.dayMoods,
  });

  /// The Monday this week began (date only).
  final DateTime weekStart;

  DateTime get weekEnd => DateTime(weekStart.year, weekStart.month, weekStart.day + 6);

  /// Days of the week with at least one entry (0 to 7).
  final int activeDays;

  /// Entries made: check-ins and journals of every kind.
  final int entries;

  /// How many of them were voice or video.
  final int voiceOrVideo;

  /// Small tasks or exercises they said they did.
  final int tasksDone;

  /// The mood word that came up most (internal word, see [Moods.display]); null when no entry had one.
  final String? topMood;

  /// Seven flags, Monday first: whether that day has an entry.
  final List<bool> dayHasEntry;

  /// Seven moods, Monday first: the most frequent mood word that day, or null.
  final List<String?> dayMoods;

  /// The recap in a few plain sentences.
  List<String> get lines {
    final out = <String>[];
    out.add(activeDays == 1 ? 'You checked in on 1 day.' : 'You checked in on $activeDays of 7 days.');
    if (entries > activeDays || voiceOrVideo > 0) {
      final voice = voiceOrVideo == 0 ? '' : ' ($voiceOrVideo by voice or video)';
      out.add('You made $entries ${entries == 1 ? 'entry' : 'entries'}$voice.');
    }
    if (topMood != null) out.add('${Moods.display(topMood)} came up most.');
    if (tasksDone > 0) out.add('You tried $tasksDone small ${tasksDone == 1 ? 'thing' : 'things'}.');
    if (activeDays <= 1) out.add('A quieter week, and that is fine. One check-in is still a check-in.');
    return out;
  }
}

/// The Monday of the week containing [day] (date only).
DateTime mondayOf(DateTime day) {
  final d = dateOnly(day);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

/// Every finished week that has at least one entry, newest first. The current week is not included: a recap is for
/// a week that is over. Weeks with nothing in them are left out rather than shown as empty.
List<WeekRecap> weeklyRecaps(
  List<SessionRecord> sessions,
  List<SuggestionRecord> history,
  DateTime now,
) {
  final thisMonday = mondayOf(now);
  final byWeek = <DateTime, List<SessionRecord>>{};
  for (final s in sessions) {
    final monday = mondayOf(s.createdAt);
    if (!monday.isBefore(thisMonday)) continue;
    byWeek.putIfAbsent(monday, () => []).add(s);
  }
  final tasksByWeek = <DateTime, int>{};
  for (final r in history) {
    if (r.done != true) continue;
    final at = r.completedAt ?? r.acceptedAt ?? r.shownAt;
    final monday = mondayOf(at);
    if (!monday.isBefore(thisMonday)) continue;
    tasksByWeek[monday] = (tasksByWeek[monday] ?? 0) + 1;
  }

  final weeks = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final monday in weeks) _recap(monday, byWeek[monday]!, tasksByWeek[monday] ?? 0)];
}

WeekRecap _recap(DateTime monday, List<SessionRecord> entries, int tasks) {
  final perDay = List.generate(7, (_) => <SessionRecord>[]);
  for (final e in entries) {
    final index = dateOnly(e.createdAt).difference(monday).inDays;
    if (index >= 0 && index < 7) perDay[index].add(e);
  }
  final moodCounts = <String, int>{};
  final dayMoods = <String?>[];
  for (final day in perDay) {
    final counts = <String, int>{};
    for (final e in day) {
      final mood = e.effectiveMood;
      if (mood == null || Moods.score(mood) == null) continue;
      counts[mood] = (counts[mood] ?? 0) + 1;
      moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
    }
    dayMoods.add(_top(counts));
  }
  return WeekRecap(
    weekStart: monday,
    activeDays: perDay.where((d) => d.isNotEmpty).length,
    entries: entries.length,
    voiceOrVideo: entries.where((e) => e.mode != CaptureMode.text).length,
    tasksDone: tasks,
    topMood: _top(moodCounts),
    dayHasEntry: [for (final d in perDay) d.isNotEmpty],
    dayMoods: dayMoods,
  );
}

/// The most frequent key; the one that sorts first on a tie, so it is always the same.
String? _top(Map<String, int> counts) {
  if (counts.isEmpty) return null;
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return ranked.first.key;
}

/// A few sentences over every recap: the overall picture. Null when there is nothing to say yet.
List<String>? overallSummary(List<WeekRecap> recaps) {
  if (recaps.isEmpty) return null;
  final weeks = recaps.length;
  final days = recaps.fold<int>(0, (n, r) => n + r.activeDays);
  final tasks = recaps.fold<int>(0, (n, r) => n + r.tasksDone);
  final moodCounts = <String, int>{};
  final weekdayCounts = List.filled(7, 0);
  for (final r in recaps) {
    if (r.topMood != null) moodCounts[r.topMood!] = (moodCounts[r.topMood!] ?? 0) + 1;
    for (var i = 0; i < 7; i++) {
      if (r.dayHasEntry[i]) weekdayCounts[i]++;
    }
  }
  final out = <String>[
    weeks == 1 ? 'Over 1 week, you showed up on $days ${days == 1 ? 'day' : 'days'}.' : 'Over $weeks weeks, you showed up on $days days.',
  ];
  final topMood = _top(moodCounts);
  if (topMood != null) out.add('${Moods.display(topMood)} was the word that came up most.');
  if (tasks > 0) out.add('You tried $tasks small ${tasks == 1 ? 'thing' : 'things'} along the way.');
  final best = weekdayCounts.reduce((a, b) => a > b ? a : b);
  if (best >= 2 && weeks >= 3) {
    const names = ['Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays', 'Sundays'];
    out.add('${names[weekdayCounts.indexOf(best)]} are when you most often check in.');
  }
  return out;
}
