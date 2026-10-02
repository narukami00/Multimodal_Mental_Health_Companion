import 'dart:math' as math;

import '../../core/models/daily_features.dart';
import '../../core/models/sleep_window.dart';
import '../../core/models/usage_event.dart';

/// A night's sleep as read from when the phone was not in use.
///
/// An estimate with known biases, not a measurement: people put the phone down
/// before they fall asleep and wake before they pick it up, so [minutes] runs
/// long, and someone who sleeps with the phone in hand or leaves it off reads
/// as having no night at all. It is only ever compared with the person's own
/// usual.
class SleepEstimate {
  const SleepEstimate({
    required this.start,
    required this.end,
    required this.confidence,
  });

  /// When the phone was put down, and when it was next picked up.
  final DateTime start;
  final DateTime end;

  /// 0 to 1: how far this reading can be trusted, from how well it fits their
  /// stated hours, how plausible its length is, and how much data backed it.
  final double confidence;

  int get minutes => end.difference(start).inMinutes;

  /// The estimate as the sleep fields of a daily row, to be merged into it.
  /// The row is the one for the morning the night ended on.
  DailyFeatures toFeatures(String dayKey) => DailyFeatures(
    dayKey: dayKey,
    sources: const {'usage'},
    estimatedSleepStartMinute: start.hour * 60 + start.minute,
    estimatedSleepEndMinute: end.hour * 60 + end.minute,
    estimatedSleepMinutes: minutes,
  );
}

/// A glance at the phone shorter than this does not end a night's sleep.
const sleepGlance = Duration(minutes: 2);

/// The shortest stretch that can be called a night.
const minSleep = Duration(hours: 3);

/// A gap longer than this is more likely a phone left off than a night's sleep.
const maxSleep = Duration(hours: 14);

/// Estimates the night that ended on the morning of [morning] (a calendar date).
///
/// Looks from 18:00 the evening before to 14:00 that day for the longest gap
/// between uses of the phone that spans the middle of the person's night: the
/// midpoint of their stated [sleepWindow], or 03:00 without one. Gaps that miss
/// that point (an afternoon without the phone) are not nights.
///
/// Pure. [events] should reach back before the evening so a session running at
/// 18:00 is seen. [dataStart] is the earliest time the data can be trusted from
/// (for instance when usage access was granted): a gap that would begin before
/// it is cut there and trusted less. Returns null when the data does not reach
/// the late morning, when no gap is long enough, or when the longest is too long
/// to be sleep.
SleepEstimate? estimateSleep({
  required DateTime morning,
  required List<UsageEvent> events,
  required DateTime dataEnd,
  DateTime? dataStart,
  SleepWindow? sleepWindow,
}) {
  final day = DateTime(morning.year, morning.month, morning.day);
  final searchStart = DateTime(day.year, day.month, day.day - 1, 18);
  final searchEnd = DateTime(day.year, day.month, day.day, 14);

  // A night is only readable once the morning has had time to show a pickup.
  if (dataEnd.isBefore(DateTime(day.year, day.month, day.day, 10))) return null;
  final horizon = dataEnd.isBefore(searchEnd) ? dataEnd : searchEnd;

  final anchor = _anchor(day, sleepWindow);
  final spans = _meaningfulSpans(events, horizon);

  // The gaps between uses, bounded by the search window. The gap after the last
  // use runs to the end of the data and has no pickup to close it, so it is not
  // a finished night and is left out.
  final gaps = <_Gap>[];
  var cursor = searchStart;
  for (final span in spans) {
    if (!span.end.isAfter(searchStart)) continue;
    if (span.start.isAfter(cursor)) {
      gaps.add(_Gap(cursor, span.start, openStart: cursor == searchStart));
    }
    if (span.end.isAfter(cursor)) cursor = span.end;
  }

  // The longest gap that reaches into the middle of the night. A glance or a
  // short wake splits a night, so the longest piece is taken rather than the one
  // exactly on the anchor.
  final nightFrom = anchor.subtract(const Duration(hours: 3));
  final nightTo = anchor.add(const Duration(hours: 3));
  _Gap? best;
  for (final gap in gaps) {
    if (!gap.start.isBefore(nightTo) || !gap.end.isAfter(nightFrom)) continue;
    if (best == null || gap.length > best.length) best = gap;
  }
  if (best == null) return null;

  var start = best.start;
  var cut = best.openStart;
  if (dataStart != null && dataStart.isAfter(start)) {
    start = dataStart;
    cut = true;
    if (!best.end.isAfter(start)) return null;
  }
  final length = best.end.difference(start);
  if (length < minSleep || length > maxSleep) return null;

  var confidence = 0.4;
  if (length >= const Duration(hours: 4) && length <= const Duration(hours: 11)) {
    confidence += 0.2;
  }
  if (sleepWindow != null && !sleepWindow.isEmpty) {
    confidence += 0.3 * _overlapShare(start, best.end, day, sleepWindow);
  } else {
    confidence += 0.1;
  }
  if (cut) confidence -= 0.25;

  return SleepEstimate(
    start: start,
    end: best.end,
    confidence: confidence.clamp(0.0, 1.0),
  );
}

/// How regular sleep has been: the spread, in minutes, of the midpoint of the
/// estimated nights. Lower is steadier. Null with fewer than five nights, since
/// a spread over fewer says nothing.
///
/// Midpoints are on a clock, so they are averaged as angles: 23:50 and 00:10 are
/// twenty minutes apart, not a day.
double? sleepRegularityMinutes(List<DailyFeatures> rows, {int nights = 14}) {
  final recent = rows
      .where(
        (row) =>
            row.estimatedSleepStartMinute != null &&
            row.estimatedSleepMinutes != null,
      )
      .toList()
    ..sort((a, b) => a.dayKey.compareTo(b.dayKey));
  final used = recent.length > nights
      ? recent.sublist(recent.length - nights)
      : recent;
  if (used.length < 5) return null;

  const day = SleepWindow.minutesPerDay;
  var sumSin = 0.0;
  var sumCos = 0.0;
  for (final row in used) {
    final midpoint =
        (row.estimatedSleepStartMinute! + row.estimatedSleepMinutes! / 2) % day;
    final angle = midpoint / day * 2 * math.pi;
    sumSin += math.sin(angle);
    sumCos += math.cos(angle);
  }
  final r = math.sqrt(sumSin * sumSin + sumCos * sumCos) / used.length;
  if (r >= 1) return 0;
  return math.sqrt(-2 * math.log(r)) * day / (2 * math.pi);
}

/// The time a night must contain: the middle of the stated hours, or 03:00.
DateTime _anchor(DateTime day, SleepWindow? window) {
  if (window == null || window.isEmpty) {
    return DateTime(day.year, day.month, day.day, 3);
  }
  final middle = (window.startMinutes + window.durationMinutes ~/ 2) %
      SleepWindow.minutesPerDay;
  // The night ends on [day], so a middle after noon belongs to the evening
  // before.
  final onDay = DateTime(day.year, day.month, day.day, 0, middle);
  return middle >= 12 * 60
      ? DateTime(day.year, day.month, day.day - 1, 0, middle)
      : onDay;
}

/// Screen-on spans long enough to count as use, so a glance at a notification at
/// 3am does not cut a night in two.
List<_Span> _meaningfulSpans(List<UsageEvent> events, DateTime horizon) {
  final sorted = events
      .where(
        (e) =>
            e.type == UsageEventType.screenOn ||
            e.type == UsageEventType.screenOff,
      )
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));

  final spans = <_Span>[];
  DateTime? since;
  for (final event in sorted) {
    if (!event.time.isBefore(horizon)) break;
    if (event.type == UsageEventType.screenOn) {
      since ??= event.time;
    } else if (since != null) {
      if (event.time.difference(since) >= sleepGlance) {
        spans.add(_Span(since, event.time));
      }
      since = null;
    }
  }
  if (since != null && horizon.difference(since) >= sleepGlance) {
    spans.add(_Span(since, horizon));
  }
  return spans;
}

/// The share of the stated window (0 to 1) that the estimated night covers.
///
/// A window that crosses midnight began the evening before [day]; one that
/// starts after midnight sits on [day] itself.
double _overlapShare(
  DateTime start,
  DateTime end,
  DateTime day,
  SleepWindow window,
) {
  final crossesMidnight = window.startMinutes > window.endMinutes;
  final windowStart = DateTime(
    day.year,
    day.month,
    crossesMidnight ? day.day - 1 : day.day,
    0,
    window.startMinutes,
  );
  final windowEnd = windowStart.add(Duration(minutes: window.durationMinutes));
  return _share(start, end, windowStart, windowEnd, window.durationMinutes);
}

double _share(
  DateTime a,
  DateTime b,
  DateTime windowStart,
  DateTime windowEnd,
  int windowMinutes,
) {
  final from = a.isAfter(windowStart) ? a : windowStart;
  final to = b.isBefore(windowEnd) ? b : windowEnd;
  if (!to.isAfter(from) || windowMinutes <= 0) return 0;
  return (to.difference(from).inMinutes / windowMinutes).clamp(0.0, 1.0);
}

class _Span {
  const _Span(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

class _Gap {
  const _Gap(this.start, this.end, {this.openStart = false});

  final DateTime start;
  final DateTime end;

  /// The gap begins at the edge of what was searched, so its true start is
  /// unknown.
  final bool openStart;

  Duration get length => end.difference(start);
}
