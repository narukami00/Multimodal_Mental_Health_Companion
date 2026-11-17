import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/forest_garden.dart';
import 'package:solace_mobile/domain/forest/forest_river.dart';
import 'package:solace_mobile/domain/forest/forest_sky.dart';
import 'package:solace_mobile/features/forest/forest_world.dart';

List<FinishedTree> trees(int count) => List.generate(count, (i) => FinishedTree(
  index: i, species: i % 7, finishedAt: DateTime(2026, 1, 1), waters: const [],
));

void main() {
  test('regions expand at the tree extent plus 80% viewport threshold', () {
    expect(riverRegions(0, 0), [0]);
    expect(riverRegions(0, riverRegionWidth - riverRevealMargin - 1), [0]);
    expect(riverRegions(0, riverRegionWidth - riverRevealMargin), [0, 1]);
    expect(riverRegions(-riverRegionWidth + riverRevealMargin, 0), [-1, 0]);
  });

  test('old river shapes and tree locations hold as the forest expands', () {
    final small = ForestWorld()..setFinished(trees(3));
    final large = ForestWorld()..setFinished(trees(90));
    addTearDown(small.dispose);
    addTearDown(large.dispose);
    expect(large.rivers.length, greaterThan(small.rivers.length));
    for (var i = 0; i < 3; i++) {
      expect(large.slotOf(i).x, small.slotOf(i).x);
      expect(large.slotOf(i).z, small.slotOf(i).z);
    }
    final original = small.rivers.single;
    final expanded = large.rivers.firstWhere((r) => r.region == original.region);
    for (var y = 358.0; y < 1300; y += 4) {
      expect(original.centerAt(y), expanded.centerAt(y));
    }
    expect(large.rivers.where((r) => r.region != 0).first.phase, isNot(original.phase));
  });

  test('channel and bank exclusions keep reserved tree roots on dry ground', () {
    final world = ForestWorld()..setFinished(trees(140));
    addTearDown(world.dispose);
    for (final river in world.rivers) {
      for (final root in river.roots) {
        expect(river.excludes(root.dx, root.dy), isFalse,
            reason: 'region ${river.region}, root $root');
      }
      for (var y = 360.0; y < 1600; y += 7) {
        expect(river.excludes(river.centerAt(y), y), isTrue);
        expect(river.centerAt(y).isFinite, isTrue);
        expect(river.halfWidthAt(y), greaterThan(0));
        expect((river.centerAt(y + 1) - river.centerAt(y)).abs(), lessThan(0.8),
            reason: 'river curves must remain smooth around reserved roots');
      }
    }
  });

  testWidgets('meadow and river stay anchored after panning away and returning', (tester) async {
    await tester.runAsync(() async {
      final world = ForestWorld(reducedMotion: true)..setFinished(trees(3));
      Future<List<int>> render() async {
        final recorder = ui.PictureRecorder();
        world.paint(ui.Canvas(recorder), const ui.Size(360, 900));
        final picture = recorder.endRecording();
        final image = await picture.toImage(360, 900);
        final bytes = await image.toByteData();
        final pixels = List<int>.of(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        return pixels;
      }
      try {
        final original = await render();
        world.camX = 1120;
        await render();
        world.camX = 0;
        expect(await render(), orderedEquals(original));
      } finally {
        world.dispose();
      }
    });
  });

  testWidgets('river renders across weather, light, camera and screen shapes', (tester) async {
    await tester.runAsync(() async {
      final world = ForestWorld()..setFinished(trees(5));
      try {
        for (final weather in ForestWeather.values) {
          for (final hour in [6.5, 12.0, 18.0, 22.0]) {
            world.weather = weather;
            world.hour = hour;
            world.update(0.05);
            for (final size in [const ui.Size(380, 680), const ui.Size(360, 900)]) {
              final recorder = ui.PictureRecorder();
              world.paint(ui.Canvas(recorder), size);
              final picture = recorder.endRecording();
              final image = await picture.toImage(size.width.toInt(), size.height.toInt());
              expect(image.width, size.width.toInt());
              image.dispose();
              picture.dispose();
            }
          }
        }
        world
          ..beginGesture()
          ..camX = world.rivers.last.anchor
          ..zoom = 2.5
          ..lift = -40;
        final recorder = ui.PictureRecorder();
        world.paint(ui.Canvas(recorder), const ui.Size(380, 680));
        recorder.endRecording().dispose();
      } finally {
        world.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });
}
