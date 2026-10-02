import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import 'personal_baseline.dart';

/// One finished day laid out as a 24-hour ring: how much the screen was on in
/// each hour, when the phone went down overnight, and what an ordinary hour has
/// looked like for this person lately.
class DayRhythm {
  const DayRhythm({
    required this.dayKey,
    required this.hours,
    required this.totalMinutes,
    required this.peakHour,
    this.usualHours,
    this.sleepStartMinute,
    this.sleepEndMinute,
  });

  final String dayKey;

  /// Screen-on share of each hour, 0 to 1, index 0 = midnight to 1 AM.
  final List<double> hours;
  final int totalMinutes;

  /// The busiest hour, or null if the screen was barely on.
  final int? peakHour;

  /// The usual share for each hour over the days before, when there are enough.
  final List<double>? usualHours;

  /// When the phone went down for the night and came back, minute of day.
  final int? sleepStartMinute;
  final int? sleepEndMinute;

  bool get hasNight => sleepStartMinute != null && sleepEndMinute != null;

  /// One plain sentence about the day. Descriptive, never an assessment.
  String get caption {
    final parts = <String>[];
    if (peakHour != null) {
      parts.add('Busiest around ${hourLabel(peakHour!)}');
    }
    if (hasNight) {
      parts.add(
        'phone down ${clockLabel(sleepStartMinute!)}, up ${clockLabel(sleepEndMinute!)}',
      );
    }
    if (parts.isEmpty) return 'Your screen was on for about ${durationLabel(totalMinutes)}.';
    final text = parts.join(', ');
    return '${text[0].toUpperCase()}${text.substring(1)}.';
  }
}

/// The most recent finished day that has an hourly picture, as a [DayRhythm].
///
/// Pure. Needs at least [minUsualDays] earlier days to draw a "usual" ghost, and
/// otherwise draws none. Returns null when there is no finished day to show.
DayRhythm? dayRhythm(
  List<DailyFeatures> rows,
  DateTime now, {
  int usualWindow = 14,
  int minUsualDays = 7,
}) {
  final todayKey = dayKey(dateOnly(now));
  final usable = [
    for (final row in rows)
      if (row.hasUsage &&
          row.usageComplete &&
          row.dayKey.compareTo(todayKey) < 0 &&
          row.hourlyActiveMinutes != null &&
          row.hourlyActiveMinutes!.length == 24)
        row,
  ]..sort((a, b) => a.dayKey.compareTo(b.dayKey));
  if (usable.isEmpty) return null;

  final latest = usable.last;
  final minutes = latest.hourlyActiveMinutes!;
  final total = latest.screenOnMinutes ?? minutes.fold<int>(0, (a, b) => a + b);
  var peak = 0;
  for (var h = 1; h < 24; h++) {
    if (minutes[h] > minutes[peak]) peak = h;
  }

  final before = usable.sublist(0, usable.length - 1);
  final recent = before.length > usualWindow
      ? before.sublist(before.length - usualWindow)
      : before;
  List<double>? usual;
  if (recent.length >= minUsualDays) {
    usual = [
      for (var h = 0; h < 24; h++)
        (median([for (final r in recent) r.hourlyActiveMinutes![h].toDouble()]) ?? 0) / 60,
    ];
  }

  return DayRhythm(
    dayKey: latest.dayKey,
    hours: [for (final m in minutes) (m / 60).clamp(0.0, 1.0)],
    totalMinutes: total,
    peakHour: minutes[peak] >= 5 ? peak : null,
    usualHours: usual,
    sleepStartMinute: latest.estimatedSleepStartMinute,
    sleepEndMinute: latest.estimatedSleepEndMinute,
  );
}

String hourLabel(int hour) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12 ${hour >= 12 ? 'PM' : 'AM'}';
}

String clockLabel(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60) % 24;
  final m = minuteOfDay % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
}

String durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}
