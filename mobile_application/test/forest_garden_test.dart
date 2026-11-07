import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/forest_garden.dart';

void main() {
  const cfg = ForestConfig();
  var n = 0;
  WaterEvent ev(WaterKind kind, DateTime at) => WaterEvent(id: 'e${n++}', kind: kind, at: at);
  DateTime day(int d, [int h = 9]) => DateTime(2026, 3, d, h);

  group('what an activity is worth in a day', () {
    test('three typed check-ins count, the fourth is saved but gives no water', () {
      final g = growGarden([for (var i = 0; i < 5; i++) ev(WaterKind.text, day(2, 8 + i))], const ForestConfig(maxGrowthPerDay: 10));
      expect(g.currentProgress, 3);
      expect(g.currentWaters.map((w) => w.earned), [1, 1, 1, 0, 0]);
    });

    test('three tasks count, then no more', () {
      final g = growGarden([for (var i = 0; i < 4; i++) ev(WaterKind.task, day(2, 8 + i))], const ForestConfig(maxGrowthPerDay: 10));
      expect(g.currentProgress, 3);
    });

    test('the first voice or video journal is worth two, then one each, up to two extra', () {
      final g = growGarden([for (var i = 0; i < 5; i++) ev(WaterKind.journal, day(2, 8 + i))], const ForestConfig(maxGrowthPerDay: 10));
      expect(g.currentWaters.map((w) => w.earned), [2, 1, 1, 0, 0]);
    });

    test('the caps start fresh each day', () {
      final g = growGarden([
        for (var d = 2; d < 4; d++) for (var i = 0; i < 4; i++) ev(WaterKind.text, day(d, 8 + i)),
      ], const ForestConfig(maxGrowthPerDay: 10));
      expect(g.currentProgress, 6);
    });
  });

  group('the tree needs time', () {
    test('only three waters a day can advance it, but the rest still count as earned', () {
      final g = growGarden([
        ev(WaterKind.journal, day(2, 8)),
        ev(WaterKind.text, day(2, 9)),
        ev(WaterKind.text, day(2, 10)),
        ev(WaterKind.task, day(2, 11)),
      ], cfg);
      expect(g.currentProgress, 3);
      expect(g.currentWaters.map((w) => w.earned), [2, 1, 1, 1]);
      expect(g.currentWaters.map((w) => w.grown), [2, 1, 0, 0]);
    });

    test('a very active day cannot finish a tree on its own', () {
      final g = growGarden([
        for (var i = 0; i < 3; i++) ev(WaterKind.text, day(2, 8 + i)),
        for (var i = 0; i < 3; i++) ev(WaterKind.task, day(2, 12 + i)),
        for (var i = 0; i < 3; i++) ev(WaterKind.journal, day(2, 16 + i)),
      ], cfg);
      expect(g.finished, isEmpty);
      expect(g.currentProgress, 3);
    });
  });

  group('trees finish and new ones start', () {
    test('seven waters make a tree, the extras carry on to the next, and nothing is lost', () {
      final events = [
        for (var d = 2; d < 5; d++) for (var i = 0; i < 3; i++) ev(WaterKind.text, day(d, 8 + i)),
      ]; // 3 a day for 3 days: 9 waters
      final g = growGarden(events, cfg);
      expect(g.finished, hasLength(1));
      expect(g.finished.single.waters.fold<int>(0, (n, w) => n + w.grown), 7);
      expect(g.currentIndex, 1);
      expect(g.currentProgress, 2);
    });

    test('the first tree is an oak, and no two in a row are the same kind', () {
      expect(speciesFor(0, -1), 0);
      var prev = speciesFor(0, -1);
      for (var i = 1; i < 60; i++) {
        final s = speciesFor(i, prev);
        expect(s, isNot(prev));
        prev = s;
      }
    });

    test('the stage drawn is one per water', () {
      expect(growGarden(const [], cfg).stage, 0);
      expect(growGarden([ev(WaterKind.text, day(2))], cfg).stage, 1);
      expect(growGarden([ev(WaterKind.journal, day(2)), ev(WaterKind.text, day(2, 10))], cfg).stage, 3);
    });

    test('the same events in any order give the same garden', () {
      final a = [ev(WaterKind.text, day(2, 8)), ev(WaterKind.journal, day(2, 9)), ev(WaterKind.task, day(3, 9))];
      expect(growGarden(a.reversed.toList(), cfg).currentProgress, growGarden(a, cfg).currentProgress);
    });
  });

  group('what is poured in front of the person', () {
    final now = DateTime(2026, 3, 5, 15);
    final yesterday = ev(WaterKind.text, DateTime(2026, 3, 4, 20));
    final morning = ev(WaterKind.text, DateTime(2026, 3, 5, 8));
    final noon = ev(WaterKind.task, DateTime(2026, 3, 5, 12));

    test('earlier days are applied quietly, today\'s unwatched ones are waiting', () {
      final all = [yesterday, morning, noon];
      expect(unwatchedToday(all, null, now).map((e) => e.id), [morning.id, noon.id]);
      expect(displayedEvents(all, null, now).map((e) => e.id), [yesterday.id]);
    });

    test('once watched they are part of the picture and are not poured again', () {
      final all = [yesterday, morning, noon];
      final watched = DateTime(2026, 3, 5, 9);
      expect(unwatchedToday(all, watched, now).map((e) => e.id), [noon.id]);
      expect(displayedEvents(all, watched, now).map((e) => e.id), [yesterday.id, morning.id]);
    });

    test('someone who was away has nothing to watch, and the tree is where they left it', () {
      expect(unwatchedToday([yesterday], null, DateTime(2026, 3, 9)), isEmpty);
    });
  });

  test('an event survives being written down and read back', () {
    final e = ev(WaterKind.journal, DateTime(2026, 3, 2, 9, 30));
    final back = WaterEvent.fromMap(e.toMap())!;
    expect((back.id, back.kind, back.at), (e.id, e.kind, e.at));
    expect(WaterEvent.fromMap({'id': 'x', 'kind': 'nonsense', 'at': 'nope'}), isNull);
  });
}
