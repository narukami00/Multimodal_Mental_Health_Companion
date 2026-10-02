import 'dart:math' as math;

import '../../core/models/daily_features.dart';
import '../../core/models/sleep_window.dart';
import '../../core/models/usage_event.dart';

/// Names the category an app belongs to, or null to leave it out of the totals
/// (the launcher, system UI, and the like).
typedef CategoryResolver = String? Function(String package);

/// Reduces a day of device events to one [DailyFeatures] row, and nothing else
/// survives: the events themselves are not kept.
///
/// Pure. Times are read as wall-clock minutes and elapsed durations, so a 23- or
/// 25-hour day (daylight saving) is handled by construction, though the test
/// suite runs in a single zone and so does not exercise one.
///
/// [events] may be in any order and may reach before and after the day. Supply
/// at least several hours **before** the day starts: the screen is assumed off
/// before the first event, so a session already running at midnight is only
/// seen if its start is included. Events at or after [dataEnd] are ignored, so a
/// day still in progress reduces only what has happened.
///
/// Returns null when [dataEnd] is not after the day's start, because nothing
/// could have been observed. A day with data but no screen use is a real row of
/// zeros.
///
/// [categoryOf] decides which foreground time counts towards which category.
/// Without it no category totals are produced at all rather than a single
/// "other" bucket posing as an answer. App names ([topApps]) are produced only
/// when [includeTopApps] is true, which the caller sets from a separate consent.
DailyFeatures? reduceUsageDay({
  required DateTime day,
  required List<UsageEvent> events,
  required DateTime dataEnd,
  SleepWindow? sleepWindow,
  CategoryResolver? categoryOf,
  bool includeTopApps = false,
  String Function(String package)? labelOf,
  int topAppCount = 5,
}) {
  final dayStart = _startOfDay(day);
  final dayEnd = _nextDay(dayStart);
  final limit = dataEnd.isBefore(dayEnd) ? dataEnd : dayEnd;
  if (!limit.isAfter(dayStart)) return null;

  final sorted = [...events]..sort((a, b) => a.time.compareTo(b.time));

  // Screen use and foreground segments are built over all events, so state
  // carried in from before the day is correct, then clipped to the day.
  final screen = <_Span>[];
  final foreground = <_Segment>[];
  var screenSince = null as DateTime?;
  var currentPackage = null as String?;
  var packageSince = null as DateTime?;
  var unlocks = 0;
  var sawKeyguard = false;
  var switches = 0;

  void closePackage(DateTime at) {
    final pkg = currentPackage;
    final since = packageSince;
    if (pkg != null && since != null && at.isAfter(since)) {
      foreground.add(_Segment(pkg, since, at));
    }
    currentPackage = null;
    packageSince = null;
  }

  for (final event in sorted) {
    if (!event.time.isBefore(limit)) break;
    final inDay = !event.time.isBefore(dayStart);

    switch (event.type) {
      case UsageEventType.screenOn:
        screenSince ??= event.time;
      case UsageEventType.screenOff:
        final since = screenSince;
        if (since != null && event.time.isAfter(since)) {
          screen.add(_Span(since, event.time));
        }
        screenSince = null;
      case UsageEventType.keyguardShown:
        if (inDay) sawKeyguard = true;
      case UsageEventType.keyguardHidden:
        if (inDay) {
          sawKeyguard = true;
          unlocks++;
        }
      case UsageEventType.appForeground:
        final pkg = event.package;
        if (pkg == null || pkg.isEmpty) break;
        if (currentPackage != null &&
            currentPackage != pkg &&
            inDay &&
            screenSince != null) {
          switches++;
        }
        closePackage(event.time);
        currentPackage = pkg;
        packageSince = event.time;
      case UsageEventType.appBackground:
        if (event.package != null && event.package == currentPackage) {
          closePackage(event.time);
        }
    }
  }
  // Whatever is still open runs to the end of the data.
  final openScreen = screenSince;
  if (openScreen != null && limit.isAfter(openScreen)) {
    screen.add(_Span(openScreen, limit));
  }
  closePackage(limit);

  // Clip screen use to the day.
  final clipped = <_Span>[];
  for (final span in screen) {
    final start = span.start.isBefore(dayStart) ? dayStart : span.start;
    final end = span.end.isAfter(limit) ? limit : span.end;
    if (end.isAfter(start)) clipped.add(_Span(start, end));
  }

  final screenSeconds = clipped.fold<int>(0, (sum, s) => sum + s.seconds);
  final longest = clipped.fold<int>(0, (best, s) => math.max(best, s.seconds));

  // Time in each local hour. Each hour is capped at 60 minutes, which only
  // matters for the repeated hour when clocks go back.
  final hourly = List<double>.filled(24, 0);
  for (final span in clipped) {
    var cursor = span.start;
    while (cursor.isBefore(span.end)) {
      final nextHour = _nextHour(cursor);
      final end = nextHour.isBefore(span.end) ? nextHour : span.end;
      hourly[cursor.hour] += end.difference(cursor).inMilliseconds / 60000;
      cursor = end;
    }
  }

  // Pickups: screen-on spans that begin within the day (a span carried in from
  // before midnight is not a new pickup).
  final pickups = [
    for (final span in screen)
      if (!span.start.isBefore(dayStart) && span.start.isBefore(limit)) span,
  ];

  final firstPickup = pickups.isEmpty ? null : pickups.first.start;
  final lastUse = clipped.isEmpty ? null : clipped.last.end;

  // Foreground time while the screen was on, by category and by app.
  final categoryMinutes = <String, double>{};
  final appMinutes = <String, double>{};
  for (final segment in foreground) {
    for (final span in clipped) {
      final start = _later(segment.start, span.start);
      final end = _earlier(segment.end, span.end);
      if (!end.isAfter(start)) continue;
      final minutes = end.difference(start).inMilliseconds / 60000;
      if (categoryOf != null) {
        final category = categoryOf(segment.package);
        if (category != null) {
          categoryMinutes[category] = (categoryMinutes[category] ?? 0) + minutes;
        }
      }
      appMinutes[segment.package] =
          (appMinutes[segment.package] ?? 0) + minutes;
    }
  }

  final screenMinutes = screenSeconds / 60;

  // Screen use inside the stated sleep hours, and how far past bedtime the last
  // use of the day ran.
  int? inSleepWindow;
  int? pastBedtime;
  if (sleepWindow != null && !sleepWindow.isEmpty) {
    var seconds = 0;
    for (final span in clipped) {
      seconds += _secondsInWindow(span, dayStart, sleepWindow);
    }
    inSleepWindow = (seconds / 60).round();

    // Only meaningful for a window that crosses midnight, where "bedtime" is the
    // evening edge. A last use that carries on to midnight is read as the end of
    // the day.
    if (sleepWindow.startMinutes > sleepWindow.endMinutes && lastUse != null) {
      final lastMinute = _minuteOfDay(lastUse, limit, dayEnd);
      final delta = lastMinute - sleepWindow.startMinutes;
      // A last use more than six hours before bedtime says nothing about
      // bedtime: it is usually a day with no evening use at all.
      pastBedtime = delta >= -360 ? delta : null;
    }
  }

  return DailyFeatures(
    dayKey: _key(dayStart),
    sources: const {'usage'},
    screenOnMinutes: screenMinutes.round(),
    // Without any keyguard events the device may have no lock screen, and a
    // count of zero would be a claim about unlocks that cannot be made.
    unlockCount: sawKeyguard ? unlocks : null,
    sessionCount: pickups.length,
    longestSessionMinutes: (longest / 60).round(),
    appSwitchRate: screenMinutes >= 5 ? switches / (screenMinutes / 60) : null,
    hourlyActiveMinutes: [
      for (final minutes in hourly) minutes.round().clamp(0, 60),
    ],
    firstPickupMinute: firstPickup == null
        ? null
        : firstPickup.hour * 60 + firstPickup.minute,
    lastUseMinute: lastUse == null ? null : _minuteOfDay(lastUse, limit, dayEnd),
    screenMinutesInSleepWindow: inSleepWindow,
    lastUseDelayVsStatedBedtimeMinutes: pastBedtime,
    categoryMinutes: categoryOf == null
        ? null
        : {
            for (final entry in categoryMinutes.entries)
              entry.key: entry.value.round(),
          },
    topApps: includeTopApps ? _topApps(appMinutes, labelOf, topAppCount) : null,
  );
}

List<AppUsage> _topApps(
  Map<String, double> minutes,
  String Function(String package)? labelOf,
  int count,
) {
  final ranked = minutes.entries.toList()
    ..sort((a, b) {
      final byTime = b.value.compareTo(a.value);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
  return [
    for (final entry in ranked.take(count))
      if (entry.value.round() > 0)
        AppUsage(
          name: labelOf?.call(entry.key) ?? entry.key,
          minutes: entry.value.round(),
        ),
  ];
}

/// Seconds of [span] that fall inside [window] on the day starting [dayStart].
/// The window is applied as wall-clock minutes of the day, so it needs two
/// pieces when it crosses midnight.
int _secondsInWindow(_Span span, DateTime dayStart, SleepWindow window) {
  final pieces = window.startMinutes < window.endMinutes
      ? [(window.startMinutes, window.endMinutes)]
      : [
          (0, window.endMinutes),
          (window.startMinutes, SleepWindow.minutesPerDay),
        ];
  var seconds = 0;
  for (final (from, to) in pieces) {
    final start = _atMinute(dayStart, from);
    final end = to >= SleepWindow.minutesPerDay
        ? _nextDay(dayStart)
        : _atMinute(dayStart, to);
    final overlapStart = _later(span.start, start);
    final overlapEnd = _earlier(span.end, end);
    if (overlapEnd.isAfter(overlapStart)) {
      seconds += overlapEnd.difference(overlapStart).inSeconds;
    }
  }
  return seconds;
}

/// The minute of the day for [time], read as the end of the day (23:59) when the
/// time sits at the very end of the day's window.
int _minuteOfDay(DateTime time, DateTime limit, DateTime dayEnd) {
  if (!time.isBefore(dayEnd)) return SleepWindow.minutesPerDay - 1;
  return time.hour * 60 + time.minute;
}

DateTime _startOfDay(DateTime value) => value.isUtc
    ? DateTime.utc(value.year, value.month, value.day)
    : DateTime(value.year, value.month, value.day);

DateTime _nextDay(DateTime dayStart) => dayStart.isUtc
    ? DateTime.utc(dayStart.year, dayStart.month, dayStart.day + 1)
    : DateTime(dayStart.year, dayStart.month, dayStart.day + 1);

DateTime _atMinute(DateTime dayStart, int minute) => dayStart.isUtc
    ? DateTime.utc(dayStart.year, dayStart.month, dayStart.day, 0, minute)
    : DateTime(dayStart.year, dayStart.month, dayStart.day, 0, minute);

DateTime _nextHour(DateTime value) => value.isUtc
    ? DateTime.utc(value.year, value.month, value.day, value.hour + 1)
    : DateTime(value.year, value.month, value.day, value.hour + 1);

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

String _key(DateTime dayStart) {
  final y = dayStart.year.toString().padLeft(4, '0');
  final m = dayStart.month.toString().padLeft(2, '0');
  final d = dayStart.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class _Span {
  const _Span(this.start, this.end);

  final DateTime start;
  final DateTime end;

  int get seconds => end.difference(start).inSeconds;
}

class _Segment {
  const _Segment(this.package, this.start, this.end);

  final String package;
  final DateTime start;
  final DateTime end;
}
