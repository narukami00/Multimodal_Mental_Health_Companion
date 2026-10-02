import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/domain/footprint/day_rhythm.dart';

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

final _now = DateTime(2026, 10, 31, 9);

DailyFeatures _day(int back, {List<int>? hourly, bool final_ = true, bool sleep = true}) {
  final day = DateTime(2026, 10, 31 - back);
  return DailyFeatures(
    dayKey: _key(day),
    sources: {'usage', if (final_) 'usageFinal'},
    screenOnMinutes: 200,
    hourlyActiveMinutes:
        hourly ?? [for (var h = 0; h < 24; h++) h == 21 ? 40 : (h >= 8 && h < 20 ? 10 : 0)],
    estimatedSleepStartMinute: sleep ? 23 * 60 + 30 : null,
    estimatedSleepEndMinute: sleep ? 7 * 60 : null,
  );
}

void main() {
  test('nothing finished means nothing to draw', () {
    expect(dayRhythm(const [], _now), isNull);
    expect(dayRhythm([_day(1, final_: false)], _now), isNull);
  });

  test('draws the latest finished day, never today', () {
    final today = DailyFeatures(
      dayKey: _key(_now),
      sources: const {'usage', 'usageFinal'},
      hourlyActiveMinutes: List.filled(24, 30),
    );
    final result = dayRhythm([_day(3), _day(1), today], _now)!;

    expect(result.dayKey, '2026-10-30');
  });

  test('hours are shares of an hour and the busiest is found', () {
    final result = dayRhythm([_day(1)], _now)!;

    expect(result.hours[21], closeTo(40 / 60, 1e-9));
    expect(result.hours.every((h) => h >= 0 && h <= 1), isTrue);
    expect(result.peakHour, 21);
    expect(result.usualHours, isNull);
  });

  test('a usual ghost appears only with enough earlier days', () {
    expect(dayRhythm([for (var b = 1; b <= 7; b++) _day(b)], _now)!.usualHours, isNull);
    final result = dayRhythm([for (var b = 1; b <= 9; b++) _day(b)], _now)!;
    expect(result.usualHours, isNotNull);
    expect(result.usualHours![21], closeTo(40 / 60, 1e-9));
  });

  test('caption describes, with the night when there is one', () {
    final result = dayRhythm([_day(1)], _now)!;
    expect(result.caption, 'Busiest around 9 PM, phone down 11:30 PM, up 7:00 AM.');
    expect(dayRhythm([_day(1, sleep: false)], _now)!.caption, 'Busiest around 9 PM.');
  });

  test('a barely-used day has no busiest hour', () {
    final result = dayRhythm(
      [_day(1, hourly: List.filled(24, 1), sleep: false)],
      _now,
    )!;
    expect(result.peakHour, isNull);
    expect(result.caption, startsWith('Your screen was on'));
  });

  test('rows without a 24-hour picture are skipped', () {
    final bad = _day(1, hourly: [1, 2, 3]);
    expect(dayRhythm([bad], _now), isNull);
  });
}
