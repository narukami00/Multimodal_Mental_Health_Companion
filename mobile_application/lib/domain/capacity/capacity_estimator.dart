import '../../core/constants/moods.dart';
import '../../core/models/sleep_window.dart';
import '../../core/models/user_profile.dart';

/// How much a person probably has to give right now.
enum CapacityLevel { low, medium, high }

/// Why the estimate is what it is. Internal: these explain the number to a
/// reader of the code or the behavioral page, and are never phrased as a claim
/// about the person ("you slept badly") in anything the user reads.
enum CapacityReason {
  /// Awake inside their own usual sleep hours.
  inSleepWindow,

  /// Within the first hour after their usual wake time.
  justWoke,

  /// In the last hour and a half before their usual bedtime.
  windingDown,

  /// Well into the waking day, away from both ends of it.
  daytime,

  /// With no sleep hours given, the small hours of the clock.
  lateNight,
  earlyMorning,
  lateEvening,

  /// Sensed sleep ran well short of their usual.
  shortSleep,
  lowMood,
  brightMood,
  decliningMood,
  recentTooHard,
}

/// A rough, explainable reading of capacity, not a measurement.
class Capacity {
  const Capacity({
    required this.level,
    required this.confidence,
    required this.reasons,
    required this.score,
  });

  final CapacityLevel level;

  /// How much of what could inform this was actually known, 0 to 1. With only
  /// the clock to go on it is low, and anything that treats [level] as firmer
  /// than that is overreading it.
  final double confidence;
  final List<CapacityReason> reasons;

  /// The sum behind [level], kept so tests and the behavioral page can see how
  /// close to a boundary a reading was.
  final double score;

  bool get isLow => level == CapacityLevel.low;
}

/// The nights at the edge of a week that count as "weekend" for sleep hours.
///
/// A night counts when the *next* day is one of these days off. Friday and
/// Saturday here, as in Bangladesh; this is a single constant so it can become
/// a setting without touching the estimator.
const defaultWeekendDays = {DateTime.friday, DateTime.saturday};

/// The sleep window that applies at [now]: the usual hours, or the weekend ones
/// when the night in question leads into a day off.
///
/// Before midday the relevant night is the one that began yesterday evening.
/// Null when the user gave no sleep hours.
SleepWindow? resolveSleepWindow({
  required UserProfile profile,
  required DateTime now,
  Set<int> weekendDays = defaultWeekendDays,
}) {
  final nightStart = now.hour < 12
      ? DateTime(now.year, now.month, now.day - 1)
      : DateTime(now.year, now.month, now.day);
  final nextDay = DateTime(nightStart.year, nightStart.month, nightStart.day + 1);
  return profile.sleepWindowFor(weekend: weekendDays.contains(nextDay.weekday));
}

/// Estimates capacity from where [now] sits in the person's day, how they said
/// they felt, and whether they recently found things too much.
///
/// Deterministic and pure. Every input is optional and an absent one simply
/// contributes nothing and lowers [Capacity.confidence]. The result shapes how
/// much effort an idea asks for; it is never shown as a score and never
/// compared between people.
///
/// - [sleepWindow]: their usual sleep hours for tonight's or last night's
///   sleep, from [resolveSleepWindow]. Without it the clock alone is used.
/// - [sleptMinutes]: sensed sleep for the last night, when available.
/// - [latestMood]: a recent check-in mood word, already limited to a recent
///   check-in by the caller.
/// - [recentMoodScores]: daily mood scores, oldest first, for a short trend.
Capacity estimateCapacity({
  required DateTime now,
  SleepWindow? sleepWindow,
  int? sleptMinutes,
  String? latestMood,
  List<double> recentMoodScores = const [],
  bool tooHardRecently = false,
}) {
  final reasons = <CapacityReason>[];
  var score = 0.0;
  var confidence = 0.0;

  // Where they are in their own day.
  final minute = now.hour * 60 + now.minute;
  if (sleepWindow != null && !sleepWindow.isEmpty) {
    confidence += 0.4;
    final position = _positionInDay(minute, sleepWindow);
    score += position.points;
    if (position.reason != null) reasons.add(position.reason!);
  } else {
    confidence += 0.2;
    final bucket = _clockBucket(now.hour);
    score += bucket.points;
    if (bucket.reason != null) reasons.add(bucket.reason!);
  }

  // Sensed sleep against their usual, when both exist.
  if (sleepWindow != null && !sleepWindow.isEmpty && sleptMinutes != null) {
    confidence += 0.2;
    final shortBy = sleepWindow.durationMinutes - sleptMinutes;
    if (shortBy >= 120) {
      score -= 2;
      reasons.add(CapacityReason.shortSleep);
    } else if (shortBy >= 60) {
      score -= 1;
      reasons.add(CapacityReason.shortSleep);
    }
  }

  // How they said they felt.
  final mood = Moods.score(latestMood);
  if (mood != null) {
    confidence += 0.3;
    if (mood <= -0.9) {
      // Strong enough to outweigh a good time of day on its own.
      score -= 3;
      reasons.add(CapacityReason.lowMood);
    } else if (mood <= -0.2) {
      score -= 1;
      reasons.add(CapacityReason.lowMood);
    } else if (mood >= 0.9) {
      score += 1;
      reasons.add(CapacityReason.brightMood);
    }
  }

  // A short trend, only with enough days to be one.
  if (recentMoodScores.length >= 3) {
    confidence += 0.1;
    final drift = recentMoodScores.last - recentMoodScores.first;
    if (drift <= -0.5) {
      score -= 1;
      reasons.add(CapacityReason.decliningMood);
    }
  }

  if (tooHardRecently) {
    score -= 1;
    reasons.add(CapacityReason.recentTooHard);
  }

  final level = score <= -2
      ? CapacityLevel.low
      : score >= 1
      ? CapacityLevel.high
      : CapacityLevel.medium;

  return Capacity(
    level: level,
    confidence: confidence.clamp(0.0, 1.0),
    reasons: List.unmodifiable(reasons),
    score: score,
  );
}

typedef _Reading = ({double points, CapacityReason? reason});

/// Where [minute] falls relative to the sleep window.
_Reading _positionInDay(int minute, SleepWindow window) {
  if (window.contains(minute)) {
    return (points: -3, reason: CapacityReason.inSleepWindow);
  }
  final sinceWake = _forward(window.endMinutes, minute);
  final untilBed = _forward(minute, window.startMinutes);

  if (sinceWake < 60) {
    return (points: -1, reason: CapacityReason.justWoke);
  }
  if (untilBed <= 90) {
    return (points: -1, reason: CapacityReason.windingDown);
  }
  if (sinceWake >= 120 && untilBed >= 240) {
    return (points: 1, reason: CapacityReason.daytime);
  }
  return (points: 0, reason: null);
}

/// Minutes from [from] forward to [to], wrapping past midnight.
int _forward(int from, int to) {
  final span = to - from;
  return span >= 0 ? span : span + SleepWindow.minutesPerDay;
}

/// With no sleep hours given, the clock is a weak stand-in. It only marks the
/// small hours and the edges of the day, and calls the rest neutral rather than
/// guessing at an energetic afternoon.
_Reading _clockBucket(int hour) {
  if (hour < 5) return (points: -3, reason: CapacityReason.lateNight);
  if (hour < 8) return (points: -1, reason: CapacityReason.earlyMorning);
  if (hour >= 22) return (points: -2, reason: CapacityReason.lateEvening);
  if (hour >= 21) return (points: -1, reason: CapacityReason.lateEvening);
  return (points: 0, reason: null);
}
