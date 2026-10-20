import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../capacity/capacity_estimator.dart';
import 'pattern_features.dart';
import 'personal_baseline.dart';
import 'sleep_estimator.dart';

/// What kind of thing a noticing is about, so the page can give it an icon.
enum NoticingKind { screen, rhythm, apps }

/// One plain statement about the person's own phone use, backed by their data.
class PhoneNoticing {
  const PhoneNoticing({
    required this.kind,
    required this.meta,
    required this.text,
    this.value,
    this.caption,
    this.note,
  });

  final NoticingKind kind;

  /// A short label for the card, such as "YOUR USUAL SCREEN TIME".
  final String meta;

  /// The whole statement in a sentence (what a screen reader reads).
  final String text;

  /// The same statement as a glanceable headline, such as "9 h 20 min", with a short [caption] under it
  /// and an optional [note] for the extra detail. All three are null for a noticing without them.
  final String? value;
  final String? caption;
  final String? note;
}

/// What the Insights page can say about phone patterns right now.
class PhoneNoticings {
  const PhoneNoticings({
    required this.daysRead,
    required this.daysNeeded,
    required this.noticings,
  });

  /// Complete days of device data read so far.
  final int daysRead;

  /// How many are needed before anything is said about what is usual.
  final int daysNeeded;
  final List<PhoneNoticing> noticings;

  bool get isLearning => daysRead < daysNeeded;

  /// Nothing has been read at all.
  bool get isEmpty => daysRead == 0;
}

/// Plain statements about the person's own usual, from the weeks before [now].
///
/// Pure and descriptive: it says what the numbers are and never whether they are
/// good, enough, too much, or like anyone else's. Until there are enough days to
/// know what is usual it says only how many have been read, and makes no claim.
PhoneNoticings phoneNoticings(
  List<DailyFeatures> rows,
  DateTime now, {
  Set<int> weekendDays = defaultWeekendDays,
}) {
  final today = dateOnly(now);
  final todayKey = dayKey(today);
  final usable = [
    for (final row in rows)
      if (row.hasUsage && row.usageComplete && row.dayKey.compareTo(todayKey) < 0)
        row,
  ];
  const needed = PersonalBaseline.defaultMinDays;
  if (usable.length < needed) {
    return PhoneNoticings(
      daysRead: usable.length,
      daysNeeded: needed,
      noticings: const [],
    );
  }

  final baseline = PersonalBaseline.build(
    usable,
    referenceEnd: today,
    weekendDays: weekendDays,
  );
  final noticings = <PhoneNoticing>[];

  // Their usual screen time, split by weekday and weekend only where there were
  // enough of each to say so.
  const screen = PatternFeature.screenOnMinutes;
  // 2026-10-05 is a Monday and 2026-10-03 a Saturday: any real weekday and
  // weekend date work for asking which baseline applies.
  final weekday = baseline.of(screen, _anyDay(weekendDays, weekend: false));
  final weekend = baseline.of(screen, _anyDay(weekendDays, weekend: true));
  if (weekday != null) {
    final split = weekday.daytypeSpecific &&
        weekend != null &&
        weekend.daytypeSpecific &&
        (weekend.median - weekday.median).abs() >=
            0.2 * (weekday.median > 1 ? weekday.median : 1);
    noticings.add(
      PhoneNoticing(
        kind: NoticingKind.screen,
        meta: 'YOUR USUAL SCREEN TIME',
        text: split
            ? 'Your screen is usually on for about ${_duration(weekday.median)} '
                  'on a weekday and about ${_duration(weekend.median)} on a '
                  'weekend day.'
            : 'Your screen is usually on for about ${_duration(weekday.median)} '
                  'a day.',
        value: _duration(weekday.median),
        caption: split ? 'on a weekday' : 'on a usual day',
        note: split ? '${_duration(weekend.median)} on a weekend day' : null,
      ),
    );
  }

  // When the phone usually goes down and comes back, and how steady that is.
  final onset = baseline.of(PatternFeature.sleepOnset, _anyDay(weekendDays, weekend: false));
  final ends = [
    for (final row in usable)
      if (row.estimatedSleepEndMinute != null) row.estimatedSleepEndMinute!.toDouble(),
  ];
  final wake = median(ends);
  if (onset != null && wake != null && ends.length >= needed ~/ 2) {
    final onsetMinute = (onset.median.round() + 18 * 60) % 1440;
    final steadiness = sleepRegularityMinutes(usable);
    final base = 'Your phone usually goes down around ${_clock(onsetMinute)} and '
        'is next picked up around ${_clock(wake.round())}.';
    final steadyNote = steadiness == null
        ? null
        : steadiness < 5
        ? 'Bedtime has been very steady'
        : 'Bedtime varies by about ${_minutes(steadiness)}';
    noticings.add(
      PhoneNoticing(
        kind: NoticingKind.rhythm,
        meta: 'YOUR USUAL NIGHT',
        text: steadiness == null
            ? base
            : steadiness < 5
            ? '$base The time it goes down has been very steady.'
            : '$base The time it goes down has varied by about '
                  '${_minutes(steadiness)}.',
        value: '${_clock(onsetMinute)} to ${_clock(wake.round())}',
        caption: 'phone goes down, then picked up',
        note: steadyNote,
      ),
    );
  }

  // Where phone time has gone over the last week.
  final week = [
    for (final row in usable)
      if (row.dayKey.compareTo(
            dayKey(DateTime(today.year, today.month, today.day - 7)),
          ) >=
          0)
        row,
  ];
  final totals = <String, int>{};
  for (final row in week) {
    row.categoryMinutes?.forEach((name, minutes) {
      totals[name] = (totals[name] ?? 0) + minutes;
    });
  }
  final all = totals.values.fold<int>(0, (a, b) => a + b);
  if (week.length >= 3 && all >= 60) {
    final ranked = totals.entries.toList()
      ..sort((a, b) {
        final byTime = b.value.compareTo(a.value);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    final top = ranked.first;
    noticings.add(
      PhoneNoticing(
        kind: NoticingKind.apps,
        meta: 'WHERE TIME WENT THIS WEEK',
        text: 'Most of your phone time this week was ${top.key}, about '
            '${(top.value * 100 / all).round()}% of it.',
        value: '${top.key[0].toUpperCase()}${top.key.substring(1)} ${(top.value * 100 / all).round()}%',
        caption: "of this week's phone time",
      ),
    );
  }

  return PhoneNoticings(
    daysRead: usable.length,
    daysNeeded: needed,
    noticings: noticings,
  );
}

/// Any real date that counts as a weekday or a weekend day under [weekendDays].
DateTime _anyDay(Set<int> weekendDays, {required bool weekend}) {
  var day = DateTime(2026, 10, 5);
  for (var i = 0; i < 7; i++) {
    if (weekendDays.contains(day.weekday) == weekend) return day;
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return day;
}

String _duration(double minutes) {
  final total = minutes.round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

String _minutes(double value) => '${value.round()} min';

String _clock(int minuteOfDay) {
  final h24 = (minuteOfDay ~/ 60) % 24;
  final m = minuteOfDay % 60;
  final period = h24 >= 12 ? 'PM' : 'AM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $period';
}
