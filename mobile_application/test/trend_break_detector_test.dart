import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/domain/footprint/pattern_features.dart';
import 'package:solace_mobile/domain/footprint/trend_break_detector.dart';

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Changes to apply to a synthetic day, in the feature's own unit.
class _Shift {
  const _Shift({
    this.screen = 0,
    this.sessions = 0,
    this.onsetMinutes = 0,
    this.mood = 0,
  });

  final double screen;
  final double sessions;
  final double onsetMinutes;
  final double mood;
}

/// A person with a steady rhythm and ordinary day-to-day noise, from [start] for
/// [days] days, with [shift] applied on the days it returns one for.
///
/// Spreads after the detector's floors: screen 30 minutes, pickups 9, phone-down
/// time about 50 minutes, mood 0.25.
List<DailyFeatures> _person({
  required DateTime start,
  required int days,
  _Shift Function(int index, DateTime day)? shift,
  int seed = 7,
  bool heavyWeekends = false,
  bool finalised = true,
}) {
  final random = math.Random(seed);
  double gauss() {
    final u1 = 1 - random.nextDouble();
    final u2 = random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  final rows = <DailyFeatures>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime(start.year, start.month, start.day + i);
    final change = shift?.call(i, day) ?? const _Shift();
    final weekend = {DateTime.friday, DateTime.saturday}.contains(day.weekday);
    final base = heavyWeekends && weekend ? 400.0 : 200.0;
    final onset = 23 * 60 + 30 + 18 * gauss() + change.onsetMinutes;
    rows.add(
      DailyFeatures(
        dayKey: _key(day),
        sources: {'usage', if (finalised) 'usageFinal', 'inApp'},
        screenOnMinutes: (base + 18 * gauss() + change.screen).round(),
        sessionCount: (60 + 5 * gauss() + change.sessions).round(),
        estimatedSleepStartMinute: onset.round() % 1440,
        estimatedSleepMinutes: (450 + 20 * gauss()).round(),
        selfMoodMedian: 0.25 + 0.05 * gauss() + change.mood,
      ),
    );
  }
  return rows;
}

final _start = DateTime(2026, 9, 1);

/// The day each synthetic series is judged on: 31 October.
final _asOf = DateTime(2026, 10, 31, 9);

void main() {
  test('the fixture dates assume a Saturday asOf', () {
    expect(_asOf.weekday, DateTime.saturday);
  });

  group('learning', () {
    test('says nothing and says so while there is too little history', () {
      final report = detectTrendBreaks(
        rows: _person(start: DateTime(2026, 10, 18), days: 13),
        asOf: _asOf,
      );

      expect(report.learning, isTrue);
      expect(report.surfaced, isNull);
      expect(report.silent, isEmpty);
    });

    test('never fires on a break inside the learning period', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: DateTime(2026, 10, 16),
          days: 15,
          shift: (_, day) =>
              day.day >= 28 ? const _Shift(screen: 200, onsetMinutes: 240) : const _Shift(),
        ),
        asOf: _asOf,
      );

      expect(report.surfaced, isNull);
    });
  });

  group('a steady person', () {
    test('has nothing to report', () {
      final report = detectTrendBreaks(
        rows: _person(start: _start, days: 60),
        asOf: _asOf,
      );

      expect(report.learning, isFalse);
      expect(report.surfaced, isNull);
    });

    test('is almost never told something shifted over a hundred days', () {
      final rows = _person(start: _start, days: 140, seed: 11);
      var surfaced = 0;
      var judged = 0;
      for (var offset = 40; offset <= 139; offset++) {
        final asOf = DateTime(_start.year, _start.month, _start.day + offset, 9);
        final report = detectTrendBreaks(rows: rows, asOf: asOf);
        judged++;
        if (report.surfaced != null) surfaced++;
      }

      expect(judged, 100);
      expect(surfaced, lessThanOrEqualTo(3));
    });

    test('a heavier weekend is their normal, not a departure', () {
      final rows = _person(start: _start, days: 60, heavyWeekends: true);

      final report = detectTrendBreaks(rows: rows, asOf: _asOf);

      expect(report.surfaced, isNull);
    });
  });

  group('a shift', () {
    // Judged on the 31st, so the latest day is the 30th.
    _Shift Function(int, DateTime) lastDays(int from, _Shift change) =>
        (_, day) => day.month == 10 && day.day >= from ? change : const _Shift();

    test('in two families at once is surfaced', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: lastDays(28, const _Shift(screen: 120, onsetMinutes: 180)),
        ),
        asOf: _asOf,
      );

      final shift = report.surfaced!;
      expect(shift.families, containsAll([PatternFamily.screen, PatternFamily.rhythm]));
      expect(shift.startDay, DateTime(2026, 10, 28));
      expect(shift.latestDay, DateTime(2026, 10, 30));
      expect(shift.strength, greaterThan(2));
      expect(shift.key, startsWith('2026-10-28:'));
    });

    test('in one family alone is recorded but never surfaced', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: lastDays(28, const _Shift(screen: 120, sessions: 30)),
        ),
        asOf: _asOf,
      );

      expect(report.surfaced, isNull);
      expect(
        report.silent.map((b) => b.feature),
        containsAll([PatternFeature.screenOnMinutes, PatternFeature.sessionCount]),
      );
    });

    test('screen time and pickups together are one family, not two', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: lastDays(28, const _Shift(screen: 150, sessions: 40)),
        ),
        asOf: _asOf,
      );

      expect(report.surfaced, isNull);
    });

    test('one feature plus a change of mood is surfaced', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: lastDays(28, const _Shift(screen: 120, mood: -1)),
        ),
        asOf: _asOf,
      );

      expect(
        report.surfaced!.families,
        containsAll([PatternFamily.screen, PatternFamily.mood]),
      );
    });

    test('knows which way it went', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: lastDays(28, const _Shift(screen: -110, onsetMinutes: -150)),
        ),
        asOf: _asOf,
      );

      final directions = {
        for (final f in report.surfaced!.features) f.feature: f.direction,
      };
      expect(directions[PatternFeature.screenOnMinutes], BreakDirection.down);
      expect(directions[PatternFeature.sleepOnset], BreakDirection.down);
    });

    test('a single odd day is not a break', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: (_, day) => day.month == 10 && day.day == 30
              ? const _Shift(screen: 200, onsetMinutes: 300)
              : const _Shift(),
        ),
        asOf: _asOf,
      );

      expect(report.surfaced, isNull);
      expect(report.silent, isEmpty);
    });

    test('that is over is not reported as going on', () {
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: (_, day) => day.month == 10 && day.day >= 22 && day.day <= 24
              ? const _Shift(screen: 150, onsetMinutes: 240)
              : const _Shift(),
        ),
        asOf: _asOf,
      );

      expect(report.surfaced, isNull);
    });

    test('still counts if the latest day is the day before yesterday', () {
      // The 30th is ordinary; the shift ran the 28th and 29th.
      final report = detectTrendBreaks(
        rows: _person(
          start: _start,
          days: 60,
          shift: (_, day) => day.month == 10 && day.day >= 28 && day.day <= 29
              ? const _Shift(screen: 130, onsetMinutes: 200)
              : const _Shift(),
        ),
        asOf: _asOf,
      );

      expect(report.surfaced, isNotNull);
      expect(report.surfaced!.startDay, DateTime(2026, 10, 28));
      // The fast rule saw it end on the 29th.
      final fast = report.surfaced!.features.where((f) => f.kind == BreakKind.fast);
      expect(fast, isNotEmpty);
      expect(fast.every((f) => f.latestDay == DateTime(2026, 10, 29)), isTrue);
    });
  });

  group('only complete days count', () {
    test('today is left out however unusual it looks', () {
      final rows = _person(start: _start, days: 60);
      final withToday = [
        ...rows,
        DailyFeatures(
          dayKey: _key(DateTime(2026, 10, 31)),
          sources: const {'usage', 'usageFinal'},
          screenOnMinutes: 900,
          estimatedSleepStartMinute: 4 * 60,
        ),
      ];

      expect(detectTrendBreaks(rows: withToday, asOf: _asOf).surfaced, isNull);
    });

    test('a day read before it ended is left out, not compared', () {
      final base = _person(start: _start, days: 60);
      // The last three days are wildly off but were read partway through.
      final partial = [
        ...base.take(57),
        for (final row in base.skip(57))
          DailyFeatures(
            dayKey: row.dayKey,
            sources: const {'usage'},
            screenOnMinutes: 900,
            estimatedSleepStartMinute: 4 * 60,
          ),
      ];

      expect(detectTrendBreaks(rows: partial, asOf: _asOf).surfaced, isNull);
    });

    test('a gap in the data ends a fast run instead of bridging it', () {
      final rows = _person(
        start: _start,
        days: 60,
        shift: (_, day) => day.month == 10 && day.day >= 27
            ? const _Shift(screen: 130, onsetMinutes: 200)
            : const _Shift(),
      )..removeWhere((row) => row.dayKey == '2026-10-29');

      final report = detectTrendBreaks(rows: rows, asOf: _asOf);

      // Only the 30th follows the gap, and one day is not a fast run. (The
      // slow rule may still notice three big days out of four, which is fair.)
      final fast =
          report.surfaced?.features.where((f) => f.kind == BreakKind.fast) ?? [];
      expect(fast, isEmpty);
    });
  });

  group('a slow drift', () {
    test('too small for the fast rule is still noticed once it has held', () {
      final rows = _person(
        start: _start,
        days: 60,
        shift: (_, day) => day.month == 10 && day.day >= 17
            ? const _Shift(screen: 42, onsetMinutes: 60)
            : const _Shift(),
      );

      final report = detectTrendBreaks(rows: rows, asOf: _asOf);

      final shift = report.surfaced!;
      expect(
        shift.features.every((f) => f.kind == BreakKind.slow),
        isTrue,
        reason: 'about 1.4 spreads a day never clears the fast threshold',
      );
      expect(shift.families.length, greaterThanOrEqualTo(2));
    });

    test('one wild day cannot build one', () {
      final rows = _person(
        start: _start,
        days: 60,
        shift: (_, day) => day.month == 10 && day.day == 20
            ? const _Shift(screen: 900, onsetMinutes: 600)
            : const _Shift(),
      );

      expect(detectTrendBreaks(rows: rows, asOf: _asOf).surfaced, isNull);
    });
  });
}
