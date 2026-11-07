import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/app_shell/check_in_task_card.dart';
import 'package:solace_mobile/features/forest/forest_card_scene.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, {ForestCardData? forest, VoidCallback? onCta}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const SizedBox()); // a clean slate, so the previous card is fully taken down first
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: CheckInTaskCard(
            eyebrow: 'Daily check-in',
            headline: 'How does your mind\nfeel right now?',
            subtitle: 'A calm 2-minute space to notice where you are.',
            ctaLabel: 'Check in now',
            onCta: onCta,
            forest: forest,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  ForestCardData data(ForestPalette p, {int species = 0, double stage = 4, bool water = false, VoidCallback? onOpen}) =>
      ForestCardData(palette: p, species: species, stage: stage, waterWaiting: water, onOpen: onOpen ?? () {});

  testWidgets('without the forest the card is the original one, subtitle and all', (tester) async {
    await pumpCard(tester);
    expect(find.text('A calm 2-minute space to notice where you are.'), findsOneWidget);
    expect(find.byKey(const ValueKey('forest-open')), findsNothing);
  });

  testWidgets('with the forest the subtitle goes, the question stays, and the button still checks in', (tester) async {
    var checkIns = 0;
    await pumpCard(tester, forest: data(ForestPalette.day), onCta: () => checkIns++);
    expect(find.text('A calm 2-minute space to notice where you are.'), findsNothing);
    expect(find.text('How does your mind feel right now?'), findsOneWidget);
    await tester.tap(find.text('Check in now'));
    expect(checkIns, 1);
  });

  testWidgets('tapping the tree side opens the forest and does not start a check-in', (tester) async {
    var opened = 0, checkIns = 0;
    await pumpCard(tester, forest: data(ForestPalette.day, onOpen: () => opened++), onCta: () => checkIns++);
    await tester.tap(find.byKey(const ValueKey('forest-open')));
    expect(opened, 1);
    expect(checkIns, 0);
  });

  testWidgets('every hour, every species and every stage lay out without trouble', (tester) async {
    for (final p in [ForestPalette.day, ForestPalette.golden, ForestPalette.dusk, ForestPalette.night]) {
      for (final species in [0, 2, 3, 4]) {
        await pumpCard(tester, forest: data(p, species: species, stage: 6.5, water: true));
        expect(tester.takeException(), isNull);
      }
    }
    for (final stage in [0.0, 1.5, 3.0, 5.0, 7.0]) {
      await pumpCard(tester, forest: data(ForestPalette.night, stage: stage));
      expect(tester.takeException(), isNull);
    }
  });

  test('the palette follows the hour', () {
    expect(ForestPalette.forHour(2).name, 'night');
    expect(ForestPalette.forHour(6).name, 'golden');
    expect(ForestPalette.forHour(12).name, 'day');
    expect(ForestPalette.forHour(18).name, 'golden');
    expect(ForestPalette.forHour(20).name, 'dusk');
    expect(ForestPalette.forHour(22).name, 'night');
  });
}
