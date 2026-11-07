import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';

/// Gentle phone-use goals, judged the morning after, from the numbers Solace already keeps.
///
/// Nothing here blocks or punishes: a day is "met", "not this time", or not judged at all (no data, a rest day, a
/// weekday-only goal on a weekend). A goal that is hard is offered an easier number, never a lecture.
enum GoalMeasure { screenTime, pickups, longestStretch, lateNight, firstPickup }

/// What the person sees: name, how the target reads, and the unit.
extension GoalMeasureText on GoalMeasure {
  String get title => switch (this) {
    GoalMeasure.screenTime => 'Screen time',
    GoalMeasure.pickups => 'Pickups',
    GoalMeasure.longestStretch => 'Longest stretch',
    GoalMeasure.lateNight => 'Late-night screen',
    GoalMeasure.firstPickup => 'First pickup',
  };

  /// "At most 3 h" / "Not before 8:00 am" style stem.
  String get stem => switch (this) {
    GoalMeasure.firstPickup => 'Not before',
    _ => 'At most',
  };

  String get explanation => switch (this) {
    GoalMeasure.screenTime => 'Total time the screen is on in a day.',
    GoalMeasure.pickups => 'How many times you unlock your phone.',
    GoalMeasure.longestStretch => 'The longest time you stay on the phone in one go.',
    GoalMeasure.lateNight => 'Screen time during your sleep hours.',
    GoalMeasure.firstPickup => 'Leave the phone alone a little longer in the morning.',
  };

  /// A sensible number to start from when there is not enough history to read the person's usual.
  int get defaultTarget => switch (this) {
    GoalMeasure.screenTime => 180,
    GoalMeasure.pickups => 60,
    GoalMeasure.longestStretch => 45,
    GoalMeasure.lateNight => 20,
    GoalMeasure.firstPickup => 480,
  };

  /// How far one tap on the stepper moves the number.
  int get step => switch (this) {
    GoalMeasure.screenTime => 10,
    GoalMeasure.pickups => 5,
    GoalMeasure.longestStretch => 5,
    GoalMeasure.lateNight => 5,
    GoalMeasure.firstPickup => 15,
  };

  int get minTarget => switch (this) {
    GoalMeasure.screenTime => 30,
    GoalMeasure.pickups => 10,
    GoalMeasure.longestStretch => 10,
    GoalMeasure.lateNight => 0,
    GoalMeasure.firstPickup => 300,
  };

  int get maxTarget => switch (this) {
    GoalMeasure.screenTime => 720,
    GoalMeasure.pickups => 300,
    GoalMeasure.longestStretch => 240,
    GoalMeasure.lateNight => 240,
    GoalMeasure.firstPickup => 720,
  };

  bool get targetIsClockTime => this == GoalMeasure.firstPickup;
}

/// A target the person set.
class Goal {
  const Goal({
    required this.id,
    required this.measure,
    required this.target,
    required this.createdDay,
    this.weekdaysOnly = false,
  });

  final String id;
  final GoalMeasure measure;

  /// Minutes, a count, or (for the first pickup) the minute of the day.
  final int target;

  /// Judged only Monday to Friday.
  final bool weekdaysOnly;

  /// The day it was set (`yyyy-MM-dd`). Days before it are never judged, so a new goal cannot rewrite the past.
  final String createdDay;

  Goal copyWith({int? target, bool? weekdaysOnly}) => Goal(
    id: id,
    measure: measure,
    target: target ?? this.target,
    createdDay: createdDay,
    weekdaysOnly: weekdaysOnly ?? this.weekdaysOnly,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'measure': measure.name,
    'target': target,
    'weekdaysOnly': weekdaysOnly,
    'createdDay': createdDay,
  };

  static Goal? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final measure = GoalMeasure.values.where((m) => m.name == raw['measure']).firstOrNull;
    final id = raw['id'];
    final target = raw['target'];
    final created = raw['createdDay'];
    if (measure == null || id is! String || target is! int || created is! String) return null;
    return Goal(id: id, measure: measure, target: target, createdDay: created, weekdaysOnly: raw['weekdaysOnly'] == true);
  }
}

enum GoalOutcome {
  met,
  notThisTime,

  /// No usable phone data for that day. Never counted either way.
  noData,

  /// A rest day, a weekend for a weekday goal, or a day before the goal existed.
  skipped,
}

/// How one goal went on one day. [value] is what was measured, when there was something to measure.
class GoalResult {
  const GoalResult(this.outcome, [this.value]);
  final GoalOutcome outcome;
  final int? value;
}

int? _valueFor(GoalMeasure measure, DailyFeatures row) => switch (measure) {
  GoalMeasure.screenTime => row.screenOnMinutes,
  GoalMeasure.pickups => row.unlockCount,
  GoalMeasure.longestStretch => row.longestSessionMinutes,
  GoalMeasure.lateNight => row.screenMinutesInSleepWindow,
  GoalMeasure.firstPickup => row.firstPickupMinute,
};

/// Judges one goal on one day. [row] is that day's stored row, or null when there is none.
GoalResult judgeGoal(Goal goal, String day, DailyFeatures? row, {bool resting = false}) {
  if (day.compareTo(goal.createdDay) < 0 || resting) return const GoalResult(GoalOutcome.skipped);
  if (goal.weekdaysOnly) {
    final parsed = DateTime.tryParse(day);
    if (parsed != null && parsed.weekday > DateTime.friday) return const GoalResult(GoalOutcome.skipped);
  }
  // Only a day that was read to its end is judged; a half-read day would flatter or unfairly fail.
  if (row == null || !row.hasUsage || !row.usageComplete) return const GoalResult(GoalOutcome.noData);
  final value = _valueFor(goal.measure, row);
  if (value == null) return const GoalResult(GoalOutcome.noData);
  final met = goal.measure == GoalMeasure.firstPickup ? value >= goal.target : value <= goal.target;
  return GoalResult(met ? GoalOutcome.met : GoalOutcome.notThisTime, value);
}

/// All the goals on one day.
class GoalDay {
  const GoalDay(this.day, this.results);
  final String day;
  final Map<String, GoalResult> results;

  /// At least one goal was met: this is what waters the tree, once, however many were met.
  bool get anyMet => results.values.any((r) => r.outcome == GoalOutcome.met);

  /// Whether any goal was actually judged (met or not this time).
  bool get judged => results.values.any((r) => r.outcome == GoalOutcome.met || r.outcome == GoalOutcome.notThisTime);
}

/// Judges every full day from the first goal up to [lastDay] (normally yesterday).
List<GoalDay> judgeGoals({
  required List<Goal> goals,
  required Map<String, DailyFeatures> rowsByDay,
  required Set<String> restDays,
  required String lastDay,
}) {
  if (goals.isEmpty) return const [];
  final first = goals.map((g) => g.createdDay).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  final start = DateTime.tryParse(first);
  final end = DateTime.tryParse(lastDay);
  if (start == null || end == null) return const [];
  final days = <GoalDay>[];
  for (var d = dateOnly(start); !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    final key = dayKey(d);
    days.add(
      GoalDay(key, {
        for (final g in goals) g.id: judgeGoal(g, key, rowsByDay[key], resting: restDays.contains(key)),
      }),
    );
  }
  return days;
}

/// A number to start a goal from: a little below the person's own usual, so the first goal is reachable.
/// Null until there are [minDays] full days to read a usual from.
int? suggestedTarget(GoalMeasure measure, Iterable<DailyFeatures> rows, {int minDays = 5}) {
  final values = <int>[
    for (final r in rows)
      if (r.hasUsage && r.usageComplete) ?_valueFor(measure, r),
  ];
  if (values.length < minDays) return null;
  values.sort();
  final median = values[values.length ~/ 2];
  final raw = measure == GoalMeasure.firstPickup ? median + 15 : (median * 0.9).round();
  final step = measure.step;
  final rounded = (raw / step).round() * step;
  return rounded.clamp(measure.minTarget, measure.maxTarget);
}

enum GoalAdjustmentKind { ease, tighten }

class GoalAdjustment {
  const GoalAdjustment(this.kind, this.newTarget);
  final GoalAdjustmentKind kind;
  final int newTarget;
}

/// A quiet offer to change a goal, from its last judged days (oldest first). Needs [window] judged days.
/// Mostly missed: offer an easier number. Always met: offer a slightly firmer one. Otherwise nothing.
GoalAdjustment? adjustmentFor(Goal goal, List<GoalOutcome> recentJudged, {int window = 5}) {
  final judged = recentJudged.where((o) => o == GoalOutcome.met || o == GoalOutcome.notThisTime).toList();
  if (judged.length < window) return null;
  final last = judged.sublist(judged.length - window);
  final missed = last.where((o) => o == GoalOutcome.notThisTime).length;
  int shift(double factor) {
    final raw = (goal.target * factor / goal.measure.step).round() * goal.measure.step;
    return raw.clamp(goal.measure.minTarget, goal.measure.maxTarget);
  }

  final isEarliest = goal.measure == GoalMeasure.firstPickup;
  if (missed >= window - 1) {
    final easier = isEarliest ? goal.target - goal.measure.step : shift(1.15);
    if (easier != goal.target) return GoalAdjustment(GoalAdjustmentKind.ease, easier);
  }
  if (missed == 0) {
    final firmer = isEarliest ? goal.target + goal.measure.step : shift(0.9);
    if (firmer != goal.target) return GoalAdjustment(GoalAdjustmentKind.tighten, firmer);
  }
  return null;
}

/// "3 h 10 min", "45 min", "60 pickups"; first pickup as a clock time.
String describeGoalValue(GoalMeasure measure, int value) {
  switch (measure) {
    case GoalMeasure.pickups:
      return '$value ${value == 1 ? 'pickup' : 'pickups'}';
    case GoalMeasure.firstPickup:
      final h = value ~/ 60;
      final m = value % 60;
      final suffix = h >= 12 ? 'pm' : 'am';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:${m.toString().padLeft(2, '0')} $suffix';
    default:
      if (value < 60) return '$value min';
      final h = value ~/ 60;
      final m = value % 60;
      return m == 0 ? '$h h' : '$h h $m min';
  }
}
