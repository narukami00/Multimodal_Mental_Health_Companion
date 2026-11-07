import 'forest_sky.dart';
import 'tree_geometry.dart';

/// Which weather the forest has, with no location and no network.
///
/// The weather is made up, but not at random from one moment to the next:
/// - It follows the season (from the date) and the climate of the person's country, so a monsoon country gets rain in
///   the monsoon and never snow.
/// - It is the same all day for a given day and changes in four-hour spells, drifting rather than jumping.
/// - It leans a little, never decisively, with how the last days have felt: heavier days are a touch greyer and softer,
///   brighter days a touch clearer. No storm is ever made heavier by a low mood, and nothing in the app says why.
/// - Dawn is more often misty.
///
/// Pure: the same inputs always give the same weather.

/// Countries whose year is warm, with a wet season in mid-year; they never get snow in the forest.
const _tropical = {
  'BD', 'IN', 'LK', 'NP', 'PK', 'MM', 'TH', 'VN', 'KH', 'LA', 'MY', 'SG', 'ID', 'PH', 'BN', 'TL', 'MV',
  'NG', 'GH', 'KE', 'TZ', 'UG', 'ET', 'CM', 'CI', 'SN', 'BR', 'CO', 'VE', 'PE', 'EC', 'CR', 'PA', 'JM', 'DO',
};

Map<ForestWeather, double> _seasonWeights(int month, bool tropical) {
  if (tropical) {
    final monsoon = month >= 6 && month <= 9;
    final preMonsoon = month >= 3 && month <= 5;
    final cool = month == 12 || month <= 2;
    return {
      ForestWeather.clear: monsoon ? 2 : 5,
      ForestWeather.partly: monsoon ? 3 : 4,
      ForestWeather.overcast: monsoon ? 3 : 1.5,
      ForestWeather.rain: monsoon ? 5 : 0.8,
      ForestWeather.storm: monsoon ? 2 : (preMonsoon ? 1.2 : 0.3),
      ForestWeather.fog: cool ? 2 : 0.3,
      ForestWeather.wind: preMonsoon ? 1.6 : 1,
      ForestWeather.snow: 0,
    };
  }
  switch (month) {
    case 12:
    case 1:
    case 2:
      return {
        ForestWeather.clear: 3, ForestWeather.partly: 3, ForestWeather.overcast: 4, ForestWeather.rain: 2,
        ForestWeather.storm: 0.3, ForestWeather.fog: 2, ForestWeather.wind: 1, ForestWeather.snow: 3,
      };
    case 3:
    case 4:
    case 5:
      return {
        ForestWeather.clear: 4, ForestWeather.partly: 4, ForestWeather.overcast: 2, ForestWeather.rain: 3,
        ForestWeather.storm: 0.5, ForestWeather.fog: 1, ForestWeather.wind: 2, ForestWeather.snow: 0,
      };
    case 6:
    case 7:
    case 8:
      return {
        ForestWeather.clear: 6, ForestWeather.partly: 4, ForestWeather.overcast: 1.5, ForestWeather.rain: 1.5,
        ForestWeather.storm: 1, ForestWeather.fog: 0.3, ForestWeather.wind: 1, ForestWeather.snow: 0,
      };
    default:
      return {
        ForestWeather.clear: 3, ForestWeather.partly: 3, ForestWeather.overcast: 3, ForestWeather.rain: 3,
        ForestWeather.storm: 0.5, ForestWeather.fog: 2, ForestWeather.wind: 2, ForestWeather.snow: 0,
      };
  }
}

/// How the last days have felt, from -1 (heavy) to 1 (bright), or null with nothing to go on.
double? moodLean(List<double> recentScores) {
  if (recentScores.length < 2) return null;
  return recentScores.reduce((a, b) => a + b) / recentScores.length;
}

Map<ForestWeather, double> _nudge(Map<ForestWeather, double> w, double? lean) {
  if (lean == null) return w;
  final out = Map.of(w);
  if (lean <= -0.25) {
    // A heavier stretch: a little greyer and softer. Nothing harsher.
    out[ForestWeather.overcast] = out[ForestWeather.overcast]! * 1.5;
    out[ForestWeather.rain] = out[ForestWeather.rain]! * 1.25;
    out[ForestWeather.fog] = out[ForestWeather.fog]! * 1.3;
    out[ForestWeather.clear] = out[ForestWeather.clear]! * 0.75;
    out[ForestWeather.storm] = out[ForestWeather.storm]! * 0.5;
  } else if (lean >= 0.25) {
    out[ForestWeather.clear] = out[ForestWeather.clear]! * 1.4;
    out[ForestWeather.partly] = out[ForestWeather.partly]! * 1.2;
    out[ForestWeather.overcast] = out[ForestWeather.overcast]! * 0.7;
  }
  return out;
}

ForestWeather _pick(Map<ForestWeather, double> weights, double roll) {
  final total = weights.values.fold<double>(0, (a, b) => a + b);
  var at = roll * total;
  for (final e in weights.entries) {
    at -= e.value;
    if (at < 0) return e.key;
  }
  return ForestWeather.clear;
}

/// Hours per spell of weather.
const weatherSpellHours = 4;

/// The weather at [now]. [countryCode] is the two-letter code from the profile (not a location);
/// [recentMoodScores] are the mood scores of the last few days' entries.
ForestWeather pickWeather({
  required DateTime now,
  required String countryCode,
  List<double> recentMoodScores = const [],
}) {
  final tropical = _tropical.contains(countryCode.toUpperCase());
  final weights = _nudge(_seasonWeights(now.month, tropical), moodLean(recentMoodScores));
  final daySeed = now.year * 10000 + now.month * 100 + now.day;
  final spell = now.hour ~/ weatherSpellHours;

  // Spell by spell through the day: each keeps the one before more often than not, so the sky drifts.
  var weather = _pick(weights, mulberry32(daySeed * 31 + 7)());
  for (var s = 1; s <= spell; s++) {
    final r = mulberry32(daySeed * 31 + s * 7919);
    final keep = r() < 0.55;
    final next = _pick(weights, r());
    if (!keep) weather = next;
  }

  // Early morning is more often misty, in the cooler half of the year most of all.
  final h = now.hour + now.minute / 60;
  if (h >= 5 && h < 8.5 && (weather == ForestWeather.clear || weather == ForestWeather.partly || weather == ForestWeather.overcast)) {
    final cool = now.month == 12 || now.month <= 2 || now.month >= 10;
    if (mulberry32(daySeed * 17 + 3)() < (cool ? 0.4 : 0.18)) weather = ForestWeather.fog;
  }
  return weather;
}
