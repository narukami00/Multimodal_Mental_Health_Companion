import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/forest_sky.dart';

/// Reference values come from the approved JavaScript prototype, run in Node, so the app lights the forest exactly as designed.
void main() {
  final ref = jsonDecode(File('test/fixtures/forest/sky_reference.json').readAsStringSync()) as List;

  void closeRgb(List<double> got, dynamic want, String what) {
    final w = (want as List).cast<num>();
    for (var i = 0; i < 3; i++) {
      expect(got[i], closeTo(w[i].toDouble(), 1e-6), reason: what);
    }
  }

  for (final e in ref) {
    final entry = e as Map<String, dynamic>;
    test('${entry['h']}h, ${entry['w']}', () {
      final weather = ForestWeather.values.firstWhere((x) => x.name == entry['w']);
      final s = skyState((entry['h'] as num).toDouble(), weather);
      closeRgb(s.skyTop, entry['skyTop'], 'skyTop');
      closeRgb(s.skyBot, entry['skyBot'], 'skyBot');
      closeRgb(s.hillNear, entry['hillNear'], 'hillNear');
      closeRgb(s.groundTop, entry['groundTop'], 'groundTop');
      closeRgb(s.treeLight, entry['treeLight'], 'treeLight');
      closeRgb(s.cloudCol, entry['cloudCol'], 'cloudCol');
      expect(s.tintA, closeTo((entry['tintA'] as num).toDouble(), 1e-9));
      expect(s.stars, closeTo((entry['stars'] as num).toDouble(), 1e-9));
      expect(s.shadow, closeTo((entry['shadow'] as num).toDouble(), 1e-9));
      expect(s.night, closeTo((entry['night'] as num).toDouble(), 1e-9));
      final sun = entry['sun'] as Map<String, dynamic>;
      expect(s.sun.x, closeTo((sun['x'] as num).toDouble(), 1e-6));
      expect(s.sun.y, closeTo((sun['y'] as num).toDouble(), 1e-6));
      expect(s.sun.a, closeTo((sun['a'] as num).toDouble(), 1e-9));
      final moon = entry['moon'] as Map<String, dynamic>;
      expect(s.moon.a, closeTo((moon['a'] as num).toDouble(), 1e-9));
    });
  }
}
