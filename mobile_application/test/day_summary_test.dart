import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/domain/footprint/day_summary.dart';

DailyFeatures _row(
  String key, {
  int? screen = 200,
  Map<String, int>? categories,
  List<int>? hours,
}) => DailyFeatures(
  dayKey: key,
  sources: const {'usage'},
  screenOnMinutes: screen,
  sessionCount: 60,
  longestSessionMinutes: 38,
  hourlyActiveMinutes: hours,
  estimatedSleepStartMinute: 23 * 60 + 30,
  estimatedSleepEndMinute: 7 * 60,
  estimatedSleepMinutes: 450,
  categoryMinutes: categories,
);

void main() {
  group('DaySummary.of', () {
    test('states what the row says', () {
      final summary = DaySummary.of(
        _row('2026-10-01', categories: {'social': 70, 'other': 30, 'video': 20}),
      );

      expect(summary.screenOn, const Duration(minutes: 200));
      expect(summary.pickups, 60);
      expect(summary.longestStretch, const Duration(minutes: 38));
      expect(summary.sleepMinutes, 450);
      expect(summary.sleepStartMinute, 23 * 60 + 30);
      expect(summary.topCategories, [
        (name: 'social', minutes: 70),
        (name: 'other', minutes: 30),
      ]);
    });

    test('only the two biggest categories, ties by name', () {
      final summary = DaySummary.of(
        _row('2026-10-01', categories: {'video': 40, 'games': 40, 'social': 40}),
      );

      expect(summary.topCategories.map((c) => c.name), ['games', 'social']);
    });

    test('zero-minute categories are not mentioned', () {
      final summary = DaySummary.of(
        _row('2026-10-01', categories: {'social': 0, 'other': 5}),
      );

      expect(summary.topCategories, [(name: 'other', minutes: 5)]);
    });

    test('finds the busiest hour, earliest on a tie', () {
      final hours = List<int>.filled(24, 0);
      hours[9] = 30;
      hours[21] = 30;
      hours[15] = 12;

      expect(DaySummary.of(_row('2026-10-01', hours: hours)).busiestHour, 9);
    });

    test('a busiest hour of a few minutes is not a pattern', () {
      final hours = List<int>.filled(24, 0);
      hours[9] = 6;

      expect(DaySummary.of(_row('2026-10-01', hours: hours)).busiestHour, isNull);
    });

    test('fields the row did not collect stay unknown, not zero', () {
      final summary = DaySummary.of(
        const DailyFeatures(dayKey: '2026-10-01', sources: {'usage'}),
      );

      expect(summary.screenOn, isNull);
      expect(summary.pickups, isNull);
      expect(summary.busiestHour, isNull);
      expect(summary.sleepMinutes, isNull);
      expect(summary.topCategories, isEmpty);
      expect(summary.isEmpty, isTrue);
    });

    test('a zero-length longest stretch is left out', () {
      final summary = DaySummary.of(
        const DailyFeatures(
          dayKey: '2026-10-01',
          sources: {'usage'},
          screenOnMinutes: 0,
          longestSessionMinutes: 0,
        ),
      );

      expect(summary.screenOn, Duration.zero);
      expect(summary.longestStretch, isNull);
    });
  });

  group('latestFinishedDay', () {
    final now = DateTime(2026, 10, 3, 12);

    test('is the most recent day before today with usage data', () {
      final row = latestFinishedDay([
        _row('2026-10-01'),
        _row('2026-10-02'),
        _row('2026-10-03'),
      ], now);

      expect(row?.dayKey, '2026-10-02');
    });

    test('never describes a day still in progress', () {
      expect(latestFinishedDay([_row('2026-10-03')], now), isNull);
    });

    test('skips days with no usage data', () {
      final row = latestFinishedDay([
        _row('2026-10-01'),
        const DailyFeatures(dayKey: '2026-10-02', sources: {'inApp'}),
      ], now);

      expect(row?.dayKey, '2026-10-01');
    });

    test('is null with nothing stored', () {
      expect(latestFinishedDay(const [], now), isNull);
    });
  });

  group('recentScreenMinutes', () {
    test('one entry per day, oldest first, with gaps left unknown', () {
      final result = recentScreenMinutes(
        [
          _row('2026-10-01', screen: 120),
          _row('2026-10-03', screen: 90),
          const DailyFeatures(
            dayKey: '2026-10-02',
            sources: {'inApp'},
            checkInCount: 1,
          ),
        ],
        DateTime(2026, 10, 3, 12),
        days: 4,
      );

      expect(result.map((e) => e.day.day), [30, 1, 2, 3]);
      expect(result.map((e) => e.minutes), [null, 120, null, 90]);
    });
  });
}
