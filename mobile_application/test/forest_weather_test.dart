import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/forest_sky.dart';
import 'package:solace_mobile/domain/forest/forest_weather.dart';

Map<ForestWeather, int> _tally(String country, int month, {List<double> mood = const [], int hour = 14}) {
  final out = <ForestWeather, int>{};
  for (var year = 2024; year <= 2027; year++) {
    for (var day = 1; day <= 28; day++) {
      final w = pickWeather(now: DateTime(year, month, day, hour), countryCode: country, recentMoodScores: mood);
      out[w] = (out[w] ?? 0) + 1;
    }
  }
  return out;
}

void main() {
  test('the same moment always has the same weather, and it holds steady within a spell', () {
    final a = pickWeather(now: DateTime(2026, 7, 14, 9, 5), countryCode: 'BD');
    final b = pickWeather(now: DateTime(2026, 7, 14, 9, 5), countryCode: 'BD');
    expect(a, b);
    // 8:00 to 11:59 is one spell of weather.
    final spell = {for (final h in [8, 9, 10, 11]) pickWeather(now: DateTime(2026, 7, 14, h, 30), countryCode: 'BD')};
    expect(spell, hasLength(1));
  });

  test('it drifts over a day instead of staying the same, and differs from day to day', () {
    final daily = {for (var d = 1; d <= 28; d++) pickWeather(now: DateTime(2026, 6, d, 13), countryCode: 'BD')};
    expect(daily.length, greaterThan(2), reason: 'a month of days is not all one kind of weather');
    final across = <ForestWeather>{};
    for (var d = 1; d <= 28; d++) {
      for (final h in [1, 5, 9, 13, 17, 21]) {
        across.add(pickWeather(now: DateTime(2026, 6, d, h), countryCode: 'BD'));
      }
    }
    expect(across.length, greaterThan(3));
  });

  test('a monsoon country is wet in the monsoon and never has snow', () {
    final monsoon = _tally('BD', 7);
    final dry = _tally('BD', 1);
    final wet = (monsoon[ForestWeather.rain] ?? 0) + (monsoon[ForestWeather.storm] ?? 0);
    final wetDry = (dry[ForestWeather.rain] ?? 0) + (dry[ForestWeather.storm] ?? 0);
    expect(wet, greaterThan(wetDry * 2));
    for (var m = 1; m <= 12; m++) {
      expect(_tally('BD', m)[ForestWeather.snow] ?? 0, 0, reason: 'month $m');
    }
  });

  test('a cold-winter country gets snow in winter and not in summer', () {
    expect(_tally('GB', 1)[ForestWeather.snow] ?? 0, greaterThan(0));
    expect(_tally('GB', 7)[ForestWeather.snow] ?? 0, 0);
  });

  test('heavier days lean a little greyer, brighter days a little clearer, and a low mood never makes a storm likelier', () {
    final plain = _tally('GB', 10);
    final heavy = _tally('GB', 10, mood: const [-0.5, -1.0, -0.25]);
    final bright = _tally('GB', 10, mood: const [1.0, 0.25, 1.0]);
    int grey(Map<ForestWeather, int> t) => (t[ForestWeather.overcast] ?? 0) + (t[ForestWeather.fog] ?? 0) + (t[ForestWeather.rain] ?? 0);
    expect(grey(heavy), greaterThan(grey(plain)));
    expect(bright[ForestWeather.clear] ?? 0, greaterThan(plain[ForestWeather.clear] ?? 0));
    expect(heavy[ForestWeather.storm] ?? 0, lessThanOrEqualTo(plain[ForestWeather.storm] ?? 0));
  });

  test('dawn is mistier than the afternoon', () {
    final dawn = _tally('GB', 11, hour: 6);
    final afternoon = _tally('GB', 11, hour: 15);
    expect(dawn[ForestWeather.fog] ?? 0, greaterThan(afternoon[ForestWeather.fog] ?? 0));
  });

  test('no mood to go on leans nowhere', () {
    expect(moodLean(const []), isNull);
    expect(moodLean(const [0.5]), isNull);
    expect(moodLean(const [1.0, 0.0]), 0.5);
  });
}
