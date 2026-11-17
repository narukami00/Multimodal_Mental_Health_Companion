import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/forest_garden.dart';
import 'package:solace_mobile/domain/forest/forest_habitat.dart';
import 'package:solace_mobile/domain/forest/forest_sky.dart';
import 'package:solace_mobile/features/forest/forest_controller.dart';
import 'package:solace_mobile/features/forest/forest_world.dart';
import 'package:solace_mobile/features/forest/forest_prop_painter.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

final start = DateTime(2026, 11, 1, 12);
bool openGround(double x, double z, ForestPropKind kind) => true;
void spell(ForestHabitat habitat, DateTime now, {double center = 0,
    ForestWeather weather = ForestWeather.storm}) {
  habitat.advance(now: now, weather: weather, centerX: center, canPlace: openGround);
}
ForestHabitat withArrival() {
  for (var seed = 0; seed < 200; seed++) {
    final habitat = ForestHabitat(seed: seed);
    spell(habitat, start);
    if (habitat.props.isNotEmpty) return habitat;
  }
  throw StateError('No seed produced an arrival');
}

void main() {
  test('weather has zero, one or two arrivals; ordinary skies never spawn', () {
    final counts = <int>{};
    for (var seed = 0; seed < 200; seed++) {
      final habitat = ForestHabitat(seed: seed);
      spell(habitat, start);
      counts.add(habitat.props.length);
      for (final p in habitat.props) {
        expect(p.rate, inInclusiveRange(0.65, 1.4));
        expect(p.returnDays, inInclusiveRange(6, 9));
      }
      for (final weather in [ForestWeather.clear, ForestWeather.partly, ForestWeather.fog, ForestWeather.overcast]) {
        final quiet = ForestHabitat(seed: seed);
        spell(quiet, start, weather: weather);
        expect(quiet.props, isEmpty);
      }
    }
    expect(counts, {0, 1, 2});
  });

  test('saved spells never reroll on reopening, panning or changing weather in the same slot', () {
    final habitat = withArrival();
    final encoded = jsonEncode(habitat.toMap());
    final restored = ForestHabitat.fromMap(jsonDecode(encoded));
    spell(restored, start.add(const Duration(minutes: 30)), center: 2000, weather: ForestWeather.wind);
    expect(jsonEncode(restored.toMap()), encoded);
    spell(restored, start.add(const Duration(hours: 4)));
    expect(restored.props.length, habitat.props.length); // same continuous storm
    spell(restored, start.subtract(const Duration(days: 1)));
    expect(restored.props.length, habitat.props.length);
    expect(restored.timeAt(start), start.add(const Duration(hours: 4)));
  });

  test('daily arrival cooldown and long absence avoid bursts', () {
    final habitat = withArrival();
    final count = habitat.props.length;
    spell(habitat, start.add(const Duration(hours: 4)), weather: ForestWeather.wind);
    expect(habitat.props.length, count);
    spell(habitat, start.add(const Duration(days: 90)), center: 1200);
    expect(habitat.props.where((p) => p.born.isAfter(start)).length, lessThanOrEqualTo(2));
    expect(habitat.props.length, lessThanOrEqualTo(count + 2));
  });

  test('land density stays bounded across many spells and neighboring areas', () {
    final habitat = ForestHabitat(seed: 48);
    final locations = <int, (double, double)>{};
    for (var i = 0; i < 600; i++) {
      final now = start.add(Duration(hours: i * 4));
      spell(habitat, now, center: [-370.0, -185.0, 0.0, 185.0, 370.0][i % 5],
        weather: i.isEven ? ForestWeather.wind : ForestWeather.storm);
      for (final p in habitat.props) {
        expect(locations.putIfAbsent(p.id, () => (p.x, p.z)), (p.x, p.z));
        final active = habitat.props.where((q) => q.occupies(now));
        expect(active.where((q) => (q.x / 380).floor() == (p.x / 380).floor()).length, lessThanOrEqualTo(4));
        expect(active.where((q) => (q.x / 190).floor() == (p.x / 190).floor()).length, lessThanOrEqualTo(2));
        expect(p.expired(now), isFalse);
      }
      expect(habitat.props.map((p) => p.id).toSet().length, habitat.props.length);
    }
    expect(locations.length, greaterThan(5));
    expect(habitat.props.length, lessThan(35)); // active landmarks plus fading plant patches
  });

  test('only mature props return, at most one per event, then release their space', () {
    final habitat = withArrival();
    final p = habitat.props.first;
    for (var i = 1; i < 12; i++) {
      spell(habitat, start.add(Duration(hours: i * 4)),
        weather: i.isEven ? ForestWeather.wind : ForestWeather.storm);
      expect(p.returnAt, isNull);
    }
    for (var i = 0; i < 100 && p.returnAt == null; i++) {
      final now = start.add(Duration(days: 80, hours: i * 4));
      spell(habitat, now, weather: i.isEven ? ForestWeather.wind : ForestWeather.storm);
      expect(habitat.props.where((q) => q.returnAt == now).length, lessThanOrEqualTo(1));
    }
    expect(p.returnAt, isNotNull);
    for (final k in [0.0, 0.2, 0.52, 0.85, 1.0, 1.5]) {
      final now = p.returnAt!.add(Duration(milliseconds: (p.returnDays * Duration.millisecondsPerDay * k).round()));
      expect(p.returnFraction(now), closeTo(k, 0.00001));
      if (k > 1.00001) expect(p.occupies(now), isFalse);
    }
    spell(habitat, p.returnAt!.add(const Duration(days: 30)), weather: ForestWeather.clear);
    expect(habitat.props.any((q) => q.id == p.id), isFalse);
  });

  test('terrain excludes existing and future roots and channels without shifting props', () {
    final world = ForestWorld();
    addTearDown(world.dispose);
    final placed = <ForestProp>[];
    for (var seed = 0; seed < 80; seed++) {
      final habitat = ForestHabitat(seed: seed);
      habitat.advance(now: start, weather: ForestWeather.storm,
        centerX: [-1800.0, -950.0, 0.0, 950.0, 1800.0][seed % 5], canPlace: world.canPlaceProp);
      placed.addAll(habitat.props);
    }
    expect(placed.length, greaterThan(20));
    world.setFinished(List.generate(140, (i) => FinishedTree(index: i, species: i % 7,
      finishedAt: start, waters: const [])));
    for (final p in placed) {
      expect(world.canPlaceProp(p.x, p.z, p.kind), isTrue);
      for (final river in world.rivers) {
        expect(river.excludes(p.x, depthY(p.z), margin: 30), isFalse);
      }
    }
  });

  test('legacy garden data and watering survive habitat persistence and reopening', () async {
    final store = InMemoryForestStore();
    final legacy = ForestData.fromMap({'initialised': true, 'seen': ['old'], 'events': [
      WaterEvent(id: 'old', kind: WaterKind.text, at: start.subtract(const Duration(days: 1))).toMap()
    ], 'watchedThrough': start.toIso8601String()});
    expect(legacy.habitat.props, isEmpty);
    final data = ForestData.fromMap({...legacy.toMap(),
      'habitat': ForestHabitat(seed: withArrival().seed).toMap()});
    await store.save(data);
    final sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
    var controller = ForestController(store: store, sessions: sessions, clock: () => start)
      ..weatherPicker = (_) => ForestWeather.storm;
    await controller.load();
    await controller.tendHabitat(centerX: 0, canPlace: openGround);
    expect(controller.habitat.props, isNotEmpty);
    expect((await store.load()).habitat.props.length, controller.habitat.props.length);
    final props = jsonEncode(controller.habitat.toMap());
    controller.dispose();
    controller = ForestController(store: store, sessions: sessions, clock: () => start)
      ..weatherPicker = (_) => ForestWeather.storm;
    await controller.load();
    await controller.tendHabitat(centerX: 2000, canPlace: openGround);
    expect(jsonEncode(controller.habitat.toMap()), props);
    expect(controller.events.single.id, 'old');
    expect(controller.garden.currentProgress, 1);
    expect((await store.load()).watchedThrough, start);
    controller.dispose();sessions.dispose();
  });

  testWidgets('both assets render all life chapters in day, rain, night and snow', (tester) async {
    await tester.runAsync(() async {
      for (final kind in ForestPropKind.values) {
        final p = ForestProp(id: 2, kind: kind, x: -100, z: -0.1, born: start,
          rate: 1, returnDays: 7, returnAt: start.add(const Duration(days: 40)));
        for (final day in [0.0, 5.0, 12.0, 30.0, 41.12, 43.64, 45.95, 48.75]) {
          final now = start.add(Duration(milliseconds: (day * Duration.millisecondsPerDay).round()));
          for (final light in [const [255.0, 255.0, 255.0], const [90.0, 112.0, 133.0]]) {
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder)..translate(80, 65);
            paintForestProp(canvas, p, now, light: light, wet: true, snow: 0.5);
            final picture = recorder.endRecording();
            final image = await picture.toImage(160, 100);
            image.dispose();picture.dispose();
          }
        }
      }
      final world = ForestWorld(reducedMotion: true)
        ..props = [ForestProp(id: 2, kind: ForestPropKind.log, x: -100, z: -0.1,
          born: start, rate: 1, returnDays: 7)]
        ..habitatNow = start.add(const Duration(days: 25));
      for (final weather in ForestWeather.values) {
        world.weather = weather;world.update(.05);
        for (final zoom in [0.8, 1.0, 3.0]) {
          world.zoom = zoom;
          final recorder = ui.PictureRecorder();
          world.paint(ui.Canvas(recorder), const ui.Size(360, 900));
          recorder.endRecording().dispose();
        }
      }
      world.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
