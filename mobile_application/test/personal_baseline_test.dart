import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/domain/footprint/pattern_features.dart';
import 'package:solace_mobile/domain/footprint/personal_baseline.dart';

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// A usage row for [day] with the given screen minutes and anything else.
DailyFeatures _row(
  DateTime day,
  double screen, {
  Map<String, int>? categories,
  int? sleepStart,
  double? mood,
}) => DailyFeatures(
  dayKey: _key(day),
  sources: const {'usage'},
  screenOnMinutes: screen.round(),
  categoryMinutes: categories,
  estimatedSleepStartMinute: sleepStart,
  selfMoodMedian: mood,
);

/// [count] consecutive days ending the day before [end], oldest first, with
/// screen time from [screen].
List<DailyFeatures> _days(
  DateTime end,
  int count,
  double Function(DateTime day) screen,
) => [
  for (var back = count; back >= 1; back--)
    _row(
      DateTime(end.year, end.month, end.day - back),
      screen(DateTime(end.year, end.month, end.day - back)),
    ),
];

void main() {
  // Thursday 15 October 2026. Friday and Saturday are the weekend.
  final end = DateTime(2026, 10, 15);

  test('the fixture dates fall on the weekdays the cases assume', () {
    expect(end.weekday, DateTime.thursday);
  });

  group('robust statistics', () {
    test('median handles odd, even, and empty', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(median(const []), isNull);
    });

    test('MAD ignores one wild value', () {
      expect(medianAbsoluteDeviation([10, 11, 9, 10, 12, 8, 500]), 1);
    });
  });

  group('learning', () {
    test('says nothing before there are enough days', () {
      final baseline = PersonalBaseline.build(
        _days(end, 13, (_) => 200),
        referenceEnd: end,
      );

      expect(baseline.isReady, isFalse);
      expect(baseline.of(PatternFeature.screenOnMinutes, end), isNull);
    });

    test('has a baseline at exactly the minimum', () {
      final baseline = PersonalBaseline.build(
        _days(end, 14, (_) => 200),
        referenceEnd: end,
      );

      expect(baseline.isReady, isTrue);
      expect(baseline.of(PatternFeature.screenOnMinutes, end)!.median, 200);
    });

    test('a feature that was not collected has no baseline', () {
      final baseline = PersonalBaseline.build(
        _days(end, 20, (_) => 200),
        referenceEnd: end,
      );

      expect(baseline.of(PatternFeature.sleepMinutes, end), isNull);
      expect(baseline.features, contains(PatternFeature.screenOnMinutes));
      expect(baseline.features, isNot(contains(PatternFeature.sleepMinutes)));
    });
  });

  group('the reference window', () {
    test('never includes the reference end or anything after it', () {
      final rows = [
        ..._days(end, 20, (_) => 200),
        _row(end, 900),
        _row(DateTime(2026, 10, 16), 900),
      ];

      final baseline = PersonalBaseline.build(rows, referenceEnd: end);

      expect(baseline.of(PatternFeature.screenOnMinutes, end)!.median, 200);
    });

    test('only reaches back the window', () {
      final rows = [
        ..._days(end, 28, (_) => 200),
        // Older than 28 days before the end: ignored.
        for (var day = 1; day <= 12; day++) _row(DateTime(2026, 9, day), 900),
      ];

      final baseline = PersonalBaseline.build(rows, referenceEnd: end);

      // A Thursday gets the weekday baseline, and 28 days hold 20 weekdays.
      final feature = baseline.of(PatternFeature.screenOnMinutes, end)!;
      expect(feature.median, 200);
      expect(feature.samples, 20);
    });
  });

  group('what counts as usual', () {
    test('one very unusual day barely moves it', () {
      final rows = _days(
        end,
        21,
        (day) => day.day == 8 ? 900 : 200 + (day.day % 3) * 5,
      );

      final feature = PersonalBaseline.build(
        rows,
        referenceEnd: end,
      ).of(PatternFeature.screenOnMinutes, end)!;

      expect(feature.median, closeTo(205, 5));
      expect(feature.sigma, lessThan(60));
    });

    test('a perfectly regular person still has a floor on their spread', () {
      final feature = PersonalBaseline.build(
        _days(end, 20, (_) => 200),
        referenceEnd: end,
      ).of(PatternFeature.screenOnMinutes, end)!;

      // 15% of 200, not zero.
      expect(feature.sigma, closeTo(30, 1e-9));
    });

    test('a very small usual value falls back on the feature\'s own floor', () {
      final feature = PersonalBaseline.build(
        _days(end, 20, (_) => 2),
        referenceEnd: end,
      ).of(PatternFeature.screenOnMinutes, end)!;

      expect(feature.sigma, PatternFeature.screenOnMinutes.minScale);
    });

    test('z scores are signed and measured in their own spreads', () {
      final baseline = PersonalBaseline.build(
        _days(end, 20, (_) => 200),
        referenceEnd: end,
      );
      final high = _row(end, 260);
      final low = _row(end, 140);

      expect(baseline.zScore(PatternFeature.screenOnMinutes, high), closeTo(2, 1e-9));
      expect(baseline.zScore(PatternFeature.screenOnMinutes, low), closeTo(-2, 1e-9));
      expect(
        baseline.zScore(PatternFeature.screenOnMinutes, _row(end, 200)),
        closeTo(0, 1e-9),
      );
    });

    test('no z score when the row did not collect the feature', () {
      final baseline = PersonalBaseline.build(
        _days(end, 20, (_) => 200),
        referenceEnd: end,
      );

      expect(
        baseline.zScore(
          PatternFeature.screenOnMinutes,
          DailyFeatures(dayKey: _key(end), sources: const {'usage'}),
        ),
        isNull,
      );
    });
  });

  group('weekdays and weekends', () {
    // Weekends (Fri, Sat) are much heavier.
    double shaped(DateTime day) =>
        {DateTime.friday, DateTime.saturday}.contains(day.weekday) ? 400 : 150;

    test('are kept apart when there are enough of each', () {
      final baseline = PersonalBaseline.build(
        _days(end, 28, shaped),
        referenceEnd: end,
      );

      final weekday = baseline.of(PatternFeature.screenOnMinutes, DateTime(2026, 10, 15))!;
      final weekend = baseline.of(PatternFeature.screenOnMinutes, DateTime(2026, 10, 16))!;

      expect(weekday.median, 150);
      expect(weekday.daytypeSpecific, isTrue);
      expect(weekend.median, 400);
      expect(weekend.daytypeSpecific, isTrue);
    });

    test('a heavy weekend day is ordinary, not a departure', () {
      final baseline = PersonalBaseline.build(
        _days(end, 28, shaped),
        referenceEnd: end,
      );
      final saturday = _row(DateTime(2026, 10, 17), 400);

      expect(
        baseline.zScore(PatternFeature.screenOnMinutes, saturday)!.abs(),
        lessThan(0.5),
      );
    });

    test('too few weekend days fall back to all days', () {
      // Sixteen days with only two weekend days among them.
      final baseline = PersonalBaseline.build(
        _days(end, 16, shaped),
        referenceEnd: end,
      );

      final weekend = baseline.of(PatternFeature.screenOnMinutes, DateTime(2026, 10, 16))!;
      expect(weekend.daytypeSpecific, isFalse);
      expect(weekend.samples, 16);
    });

    test('which days are the weekend is a parameter', () {
      final baseline = PersonalBaseline.build(
        _days(end, 28, shaped),
        referenceEnd: end,
        weekendDays: const {DateTime.saturday, DateTime.sunday},
      );

      // Saturday pools with Sunday now, and Sundays are light, so the weekend
      // baseline sits between the two instead of at Saturday's 400.
      final saturday = baseline.of(
        PatternFeature.screenOnMinutes,
        DateTime(2026, 10, 17),
      )!;
      expect(saturday.median, isNot(400));
      expect(saturday.median, inInclusiveRange(150, 400));
    });
  });

  group('features', () {
    test('categories read as a real zero when the row has totals', () {
      const withTotals = DailyFeatures(
        dayKey: '2026-10-01',
        categoryMinutes: {'social': 40},
      );
      const withoutTotals = DailyFeatures(dayKey: '2026-10-01');

      expect(PatternFeature.socialMinutes.valueOf(withTotals), 40);
      expect(PatternFeature.videoMinutes.valueOf(withTotals), 0);
      expect(PatternFeature.socialMinutes.valueOf(withoutTotals), isNull);
    });

    test('phone-down time is continuous across midnight', () {
      DailyFeatures at(int minute) => DailyFeatures(
        dayKey: '2026-10-01',
        estimatedSleepStartMinute: minute,
      );

      final late = PatternFeature.sleepOnset.valueOf(at(23 * 60 + 30))!;
      final later = PatternFeature.sleepOnset.valueOf(at(30))!;

      expect(later - late, 60);
    });

    test('app engagement is not a pattern feature', () {
      final names = PatternFeature.values.map((f) => f.name).toSet();

      for (final engagement in ['checkInCount', 'chatMinutes', 'journalWordCount']) {
        expect(names, isNot(contains(engagement)));
      }
    });

    test('every feature belongs to a family and has a plain label', () {
      for (final feature in PatternFeature.values) {
        expect(feature.label, isNotEmpty);
        expect(feature.minScale, greaterThan(0));
      }
    });

    test('mood comes from the day\'s mood median', () {
      final baseline = PersonalBaseline.build(
        [
          for (var back = 20; back >= 1; back--)
            _row(DateTime(2026, 10, 15 - back), 200, mood: 0.25),
        ],
        referenceEnd: end,
      );

      expect(baseline.of(PatternFeature.moodScore, end)!.median, 0.25);
      expect(PatternFeature.moodScore.family, PatternFamily.mood);
    });
  });
}
