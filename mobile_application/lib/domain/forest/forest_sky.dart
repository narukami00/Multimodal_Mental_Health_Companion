import 'dart:math' as math;

import 'tree_geometry.dart';

/// The sky and light of the forest as a function of the hour and the weather: a straight port of the approved prototype's
/// `skyState`. Pure: colours are plain [r, g, b] lists, so it can be tested without a screen.

typedef Rgb = List<double>;

Rgb rgbFromHex(String h) {
  final n = int.parse(h.substring(1), radix: 16);
  return [((n >> 16) & 255).toDouble(), ((n >> 8) & 255).toDouble(), (n & 255).toDouble()];
}

Rgb mixRgb(Rgb a, Rgb b, double t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
Rgb shadeRgb(Rgb c, double k) => k >= 0 ? mixRgb(c, [255, 255, 255], k) : mixRgb(c, [0, 0, 0], -k);
Rgb greyRgb(Rgb c) {
  final l = c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11;
  return [l, l, l];
}

double _easeInOut(double t) => 0.5 - 0.5 * math.cos(math.pi * clamp01(t));

/// How the weather changes the light and what falls from the sky.
class WeatherLook {
  const WeatherLook({
    required this.label,
    this.cover = 0,
    this.grey = 0,
    this.dim = 0,
    this.rain = 0,
    this.snow = 0,
    this.fog = 0,
    this.wind = 0,
    this.flash = 0,
    this.pale = false,
  });
  final String label;
  final double cover, grey, dim, fog, wind;
  final int rain, snow;
  final bool pale;
  final double flash;
}

enum ForestWeather { clear, partly, overcast, rain, storm, fog, snow, wind }

const weatherLooks = <ForestWeather, WeatherLook>{
  ForestWeather.clear: WeatherLook(label: 'Clear', cover: 0.12, wind: 0.2),
  ForestWeather.partly: WeatherLook(label: 'Partly cloudy', cover: 0.45, grey: 0.08, dim: 0.02, wind: 0.3),
  ForestWeather.overcast: WeatherLook(label: 'Overcast', cover: 1.0, grey: 0.55, dim: 0.12, fog: 0.1, wind: 0.3),
  ForestWeather.rain: WeatherLook(label: 'Light rain', cover: 0.95, grey: 0.6, dim: 0.18, rain: 70, fog: 0.12, wind: 0.4),
  ForestWeather.storm: WeatherLook(label: 'Storm', cover: 1.0, grey: 0.75, dim: 0.32, rain: 170, fog: 0.15, wind: 0.85, flash: 1),
  ForestWeather.fog: WeatherLook(label: 'Fog', cover: 0.65, grey: 0.5, dim: 0.06, fog: 0.85, wind: 0.1, pale: true),
  ForestWeather.snow: WeatherLook(label: 'Snow', cover: 0.9, grey: 0.5, dim: 0.04, snow: 120, fog: 0.15, wind: 0.25, pale: true),
  ForestWeather.wind: WeatherLook(label: 'Windy', cover: 0.4, grey: 0.1, dim: 0.03, wind: 1.0),
};

// hour, sky top/mid/bottom, hills far/mid/near, ground top/bottom, tint colour, tint alpha, stars, shadow length
const _keys = <List<Object>>[
  [0.0, '#0a1230', '#16214a', '#273663', '#273a55', '#1f3446', '#1a3040', '#1e3a2b', '#142a1d', '#08102e', 0.46, 1.0, 0.0],
  [4.8, '#111a42', '#2a2f62', '#5a4d7a', '#33415e', '#2a3e4c', '#23384a', '#233f2e', '#183020', '#141a40', 0.36, 0.7, 0.0],
  [6.2, '#6a7fbd', '#d7a2a6', '#ffcf9e', '#9aa2b6', '#7c9584', '#6a8c5b', '#89ad62', '#6b934b', '#ff9466', 0.10, 0.06, 1.6],
  [8.3, '#78b9e6', '#b9dcf1', '#f2efd8', '#b2c8d4', '#93b788', '#7dac5e', '#a2cc71', '#80b158', '#ffffff', 0.0, 0.0, 0.9],
  [12.5, '#5aaae8', '#a3d3f3', '#e3f2f6', '#a8c4d6', '#8dba82', '#75ad58', '#9ccb68', '#79ad53', '#ffffff', 0.0, 0.0, 0.35],
  [15.8, '#66a9de', '#afd2e8', '#f4e9cf', '#b3c3cc', '#95b47e', '#7ca655', '#a3c766', '#7fa84f', '#ffd9a0', 0.04, 0.0, 0.8],
  [18.0, '#7898c8', '#efbf90', '#ffc871', '#c3a28e', '#97955f', '#7c8e45', '#a4ac55', '#7c873f', '#ff9a3c', 0.13, 0.0, 2.2],
  [19.4, '#3a4784', '#a86f98', '#ef9671', '#5f5a74', '#4d5a5c', '#3f5246', '#4e6338', '#3a4c2a', '#5a3a7a', 0.26, 0.25, 1.4],
  [20.8, '#0e1636', '#1b2550', '#2e3966', '#2a3c57', '#213548', '#1b3141', '#1f3b2c', '#152b1e', '#08102e', 0.44, 0.95, 0.0],
  [24.0, '#0a1230', '#16214a', '#273663', '#273a55', '#1f3446', '#1a3040', '#1e3a2b', '#142a1d', '#08102e', 0.46, 1.0, 0.0],
];

String phaseName(double h) {
  if (h < 5) return 'Night';
  if (h < 7) return 'Dawn';
  if (h < 11) return 'Morning';
  if (h < 14) return 'Midday';
  if (h < 17.2) return 'Afternoon';
  if (h < 18.9) return 'Golden hour';
  if (h < 20.3) return 'Dusk';
  return 'Night';
}

class SkyBody {
  const SkyBody(this.x, this.y, this.a, this.warm);
  final double x, y, a, warm;
}

/// Everything the drawing layer needs to know about the light, as plain numbers and colours.
class SkyState {
  const SkyState({
    required this.hour,
    required this.phase,
    required this.weather,
    required this.skyTop,
    required this.skyMid,
    required this.skyBot,
    required this.hillFar,
    required this.hillMid,
    required this.hillNear,
    required this.groundTop,
    required this.groundBot,
    required this.tint,
    required this.tintA,
    required this.stars,
    required this.shadow,
    required this.sun,
    required this.moon,
    required this.night,
    required this.treeLight,
    required this.cloudCol,
  });

  final double hour;
  final String phase;
  final WeatherLook weather;
  final Rgb skyTop, skyMid, skyBot, hillFar, hillMid, hillNear, groundTop, groundBot, tint, treeLight, cloudCol;
  final double tintA, stars, shadow, night;
  final SkyBody sun, moon;

  double get day => 1 - night;
  double get cover => weather.cover;
  double get wind => weather.wind;
  double get fog => weather.fog;
}

SkyState skyState(double hour, ForestWeather weatherKey) {
  final h = ((hour % 24) + 24) % 24;
  final w = weatherLooks[weatherKey]!;
  var i = 0;
  while (h > (_keys[i + 1][0] as double)) {
    i++;
  }
  final a = _keys[i], b = _keys[i + 1];
  final t = _easeInOut((h - (a[0] as double)) / ((b[0] as double) - (a[0] as double)));
  Rgb col(int k) => mixRgb(rgbFromHex(a[k] as String), rgbFromHex(b[k] as String), t);
  double num2(int k) => lerp(a[k] as double, b[k] as double, t);

  const paleTarget = <double>[214, 220, 224];
  Rgb wx(Rgb c) {
    var o = mixRgb(c, mixRgb(greyRgb(c), [150, 158, 168], 0.25), w.grey);
    if (w.pale) o = mixRgb(o, mixRgb(paleTarget, o, 0.55), w.fog * 0.7 + (weatherKey == ForestWeather.snow ? 0.4 : 0));
    return shadeRgb(o, -w.dim * 0.9);
  }

  Rgb wxSoft(Rgb c) => mixRgb(c, greyRgb(c), w.grey * 0.45);

  final sunT = (h - 5.9) / (19.6 - 5.9);
  final moonH = h < 12 ? h + 24 : h;
  final moonT = (moonH - 19.4) / (30.1 - 19.4);
  SkyBody arc(double u, double alpha, double warm) =>
      SkyBody(lerp(18, 362, u), 345 - math.sin(math.pi * clamp01(u)) * 275, alpha, warm);
  final night = num2(11);
  final tintA = num2(10);
  return SkyState(
    hour: h,
    phase: phaseName(h),
    weather: w,
    skyTop: wx(col(1)),
    skyMid: wx(col(2)),
    skyBot: wx(col(3)),
    hillFar: wx(col(4)),
    hillMid: wxSoft(col(5)),
    hillNear: wxSoft(col(6)),
    groundTop: wxSoft(col(7)),
    groundBot: wxSoft(col(8)),
    tint: col(9),
    tintA: clamp01(tintA + w.dim),
    stars: night * (1 - w.cover * 0.9),
    shadow: num2(12) * (1 - w.cover * 0.85),
    sun: arc(sunT, (sunT > -0.02 && sunT < 1.02 ? 1 : 0) * (1 - w.cover * 0.85), 1 - math.sin(math.pi * clamp01(sunT))),
    moon: arc(
      moonT,
      (moonT > 0 && moonT < 1 ? smooth(0, 0.06, moonT) * smooth(1, 0.94, moonT) : 0) * (1 - w.cover * 0.8),
      0,
    ),
    night: night,
    treeLight: mixRgb([255, 255, 255], col(9), clamp01((tintA + w.dim) * 1.25)),
    cloudCol: mixRgb(mixRgb(col(3), [255, 255, 255], 0.55 * (1 - night)), [120, 128, 140], w.grey * 0.6),
  );
}
