import 'dart:math' as math;

import 'forest_sky.dart' show ForestWeather;
import 'forest_weather.dart' show weatherSpellHours;
import 'tree_geometry.dart';

enum ForestPropKind { log, stone }

const _dayMs = Duration.millisecondsPerDay;
const habitatAreaWidth = 380.0;

/// A saved landmark. Its position and growth rate never change after arrival.
class ForestProp {
  ForestProp({required this.id, required this.kind, required this.x, required this.z,
    required this.born, required this.rate, required this.returnDays, this.returnAt});

  final int id;
  final ForestPropKind kind;
  final double x, z, rate, returnDays;
  final DateTime born;
  DateTime? returnAt;

  double ageAt(DateTime now) => math.max(0, now.difference(born).inMilliseconds / _dayMs) * rate;
  double get matureAge => kind == ForestPropKind.log ? 18 : 26;
  bool canReturn(DateTime now) => returnAt == null &&
      now.difference(born).inMilliseconds / _dayMs >= matureAge / rate + 3;
  double returnFraction(DateTime now) => returnAt == null ? 0 :
      math.max(0, now.difference(returnAt!).inMilliseconds / (_dayMs * returnDays));
  double returnProgress(DateTime now) => clamp01(returnFraction(now));
  bool occupies(DateTime now) => returnFraction(now) < 1;
  bool expired(DateTime now) => returnFraction(now) >= 1.5;

  Map<String, Object?> toMap() => {'id': id, 'kind': kind.name, 'x': x, 'z': z,
    'born': born.toIso8601String(), 'rate': rate, 'returnDays': returnDays,
    'returnAt': returnAt?.toIso8601String()};

  static ForestProp? fromMap(Object? raw) {
    if (raw is! Map || raw['id'] is! int || (raw['id'] as int) < 0) return null;
    final kind = ForestPropKind.values.where((k) => k.name == raw['kind']).firstOrNull;
    final born = DateTime.tryParse('${raw['born']}');
    final x = raw['x'], z = raw['z'], rate = raw['rate'], days = raw['returnDays'];
    if (kind == null || born == null || x is! num || z is! num || rate is! num || days is! num ||
        !x.isFinite || !z.isFinite || !rate.isFinite || !days.isFinite ||
        x.abs() > 1e7 || z < -0.7 || z > 0.85 || rate < 0.65 || rate > 1.4 || days < 6 || days > 9) {
      return null;
    }
    final returnAt = DateTime.tryParse('${raw['returnAt']}');
    if (returnAt != null && returnAt.isBefore(born)) return null;
    return ForestProp(id: raw['id'] as int, kind: kind, x: x.toDouble(), z: z.toDouble(),
      born: born, rate: rate.toDouble(), returnDays: days.toDouble(), returnAt: returnAt);
  }
}

/// Weather events are processed once, independent of frames, camera movement or
/// route visits. Retired records are discarded after their plant patch fades.
class ForestHabitat {
  ForestHabitat({int? seed}) : seed = seed ?? math.Random().nextInt(0x7fffffff);

  final int seed;
  final props = <ForestProp>[];
  int serial = 0;
  int? lastSpell;
  ForestWeather? lastWeather;
  DateTime? lastArrival, lastObserved;

  DateTime timeAt(DateTime now) => lastObserved != null && now.isBefore(lastObserved!) ? lastObserved! : now;

  bool capacityAt(double x, DateTime now) {
    var area = 0, clearing = 0;
    for (final p in props) {
      if (!p.occupies(now)) continue;
      if ((p.x / habitatAreaWidth).floor() == (x / habitatAreaWidth).floor()) area++;
      if ((p.x / (habitatAreaWidth / 2)).floor() == (x / (habitatAreaWidth / 2)).floor()) clearing++;
    }
    return area < 4 && clearing < 2;
  }

  /// Only the current spell is considered on return after time away. Consecutive
  /// spells of the same weather form one episode, rather than repeated rolls.
  bool advance({required DateTime now, required ForestWeather weather,
    required double centerX,
    required bool Function(double x, double z, ForestPropKind kind) canPlace}) {
    final spell = DateTime(now.year, now.month, now.day,
        now.hour ~/ weatherSpellHours * weatherSpellHours).millisecondsSinceEpoch;
    if (lastSpell != null && spell <= lastSpell!) return false;
    final at = timeAt(now);
    final newEpisode = weather != lastWeather || lastSpell == null ||
        spell - lastSpell! > const Duration(hours: weatherSpellHours).inMilliseconds;
    lastSpell = spell;
    lastWeather = weather;
    lastObserved = at;
    props.removeWhere((p) => p.expired(at));
    if (!newEpisode || !const [ForestWeather.rain, ForestWeather.storm,
        ForestWeather.wind, ForestWeather.snow].contains(weather)) {
      return true;
    }

    final random = mulberry32(seed ^ (spell ~/ 1000));
    final roll = random();
    final arrivals = roll < 0.60 ? 0 : roll < 0.92 ? 1 : 2;
    // At most one mature landmark begins returning in any weather episode.
    for (final p in props) {
      if (p.canReturn(at) && random() < 0.25) {
        p.returnAt = at;
        break;
      }
    }
    if (lastArrival != null && at.difference(lastArrival!) < const Duration(days: 1)) return true;
    for (var i = 0; i < arrivals; i++) {
      final kind = random() < (weather == ForestWeather.wind ? 0.8 : 0.5)
          ? ForestPropKind.log : ForestPropKind.stone;
      for (var attempt = 0; attempt < 100; attempt++) {
        final x = centerX + (random() - 0.5) * 300;
        final z = 0.78 - random() * 1.4;
        if (!capacityAt(x, at) || !canPlace(x, z, kind)) continue;
        if (props.any((p) => p.occupies(at) &&
            math.pow((x - p.x) / 67, 2) + math.pow((z - p.z) * 162 / 20, 2) < 1)) {
          continue;
        }
        props.add(ForestProp(id: serial++, kind: kind, x: x, z: z, born: at,
          rate: 0.65 + random() * 0.75, returnDays: 6 + random() * 3));
        lastArrival = at;
        break;
      }
    }
    return true;
  }

  Map<String, Object?> toMap() => {'seed': seed, 'serial': serial, 'lastSpell': lastSpell,
    'lastWeather': lastWeather?.name, 'lastArrival': lastArrival?.toIso8601String(),
    'lastObserved': lastObserved?.toIso8601String(), 'props': [for (final p in props) p.toMap()]};

  static ForestHabitat fromMap(Object? raw) {
    if (raw is! Map) return ForestHabitat();
    final habitat = ForestHabitat(seed: raw['seed'] is int ? raw['seed'] as int : null);
    final ids = <int>{};
    for (final item in raw['props'] is List ? raw['props'] as List : const []) {
      final prop = ForestProp.fromMap(item);
      if (prop != null && ids.add(prop.id)) habitat.props.add(prop);
    }
    habitat.serial = math.max(raw['serial'] is int ? raw['serial'] as int : 0,
        ids.fold(0, (a, b) => math.max(a, b + 1)));
    habitat.lastSpell = raw['lastSpell'] is int ? raw['lastSpell'] as int : null;
    habitat.lastWeather = ForestWeather.values.where((w) => w.name == raw['lastWeather']).firstOrNull;
    habitat.lastArrival = DateTime.tryParse('${raw['lastArrival']}');
    habitat.lastObserved = DateTime.tryParse('${raw['lastObserved']}');
    return habitat;
  }
}
