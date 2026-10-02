import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/features/insights/phone_tab.dart';

DailyFeatures _day(int back, int minutes, {bool final_ = true}) {
  final d = DateTime(2026, 10, 31 - back);
  return DailyFeatures(
    dayKey:
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    sources: {'usage', if (final_) 'usageFinal'},
    screenOnMinutes: minutes,
  );
}

void main() {
  final now = DateTime(2026, 10, 31, 9);

  test('the week is the seven days before today, oldest first', () {
    final week = weekOfScreenTime([for (var b = 1; b <= 7; b++) _day(b, 100 + b)], now)!;

    expect(week.length, 7);
    expect(week.first.day, DateTime(2026, 10, 24));
    expect(week.last.day, DateTime(2026, 10, 30));
    expect(week.last.minutes, 101);
  });

  test('too few days draws no wave, and unfinished days are not used', () {
    expect(weekOfScreenTime([_day(1, 100), _day(2, 100)], now), isNull);
    expect(
      weekOfScreenTime([_day(1, 100), _day(2, 100), _day(3, 100, final_: false)], now),
      isNull,
    );
  });

  test('a missing day is a gap, not zero', () {
    final week = weekOfScreenTime([_day(1, 100), _day(2, 100), _day(4, 100)], now)!;
    expect(week.where((d) => d.minutes == null).length, 4);
  });
}
