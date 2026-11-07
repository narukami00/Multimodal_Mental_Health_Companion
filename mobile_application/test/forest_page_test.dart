import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/forest/forest_controller.dart';
import 'package:solace_mobile/features/forest/forest_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  late SessionController sessions;
  late ForestController forest;

  setUp(() async {
    sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
    forest = ForestController(store: InMemoryForestStore(), sessions: sessions);
    await forest.load();
  });

  tearDown(() => forest.dispose());

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // Reduced motion keeps the whole pour short enough to play out in a test.
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(data: const MediaQueryData(disableAnimations: true, size: Size(432, 960)), child: ForestPage(controller: forest)),
    ));
    await tester.pump();
  }

  Future<void> playOut(WidgetTester tester) async {
    for (var i = 0; i < 80 && forest.waterWaiting; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('with nothing waiting it just shows the forest, quietly', (tester) async {
    await pumpPage(tester);
    expect(find.text('YOUR FOREST'), findsOneWidget);
    expect(find.byKey(const ValueKey('forest-stage')), findsOneWidget);
    expect(find.text('A new seed'), findsOneWidget);
    expect(find.text('0 trees grown'), findsOneWidget);
  });

  testWidgets('waters earned today are poured when the page opens, and then they are watched', (tester) async {
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    await sessions.saveSession(mode: CaptureMode.voice, text: 'hello');
    expect(forest.waiting, hasLength(2));
    await pumpPage(tester);
    await playOut(tester);

    expect(forest.waterWaiting, isFalse);
    expect(forest.garden.currentProgress, 3); // 1 for the check-in, 2 for the first voice journal
    expect(find.text('Seedling'), findsOneWidget); // stage 3
  });

  testWidgets('opening again shows the tree where it is, with nothing to pour', (tester) async {
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    await pumpPage(tester);
    await playOut(tester);
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);
    expect(forest.waiting, isEmpty);
    expect(find.text('Seed planted'), findsOneWidget);
  });

  testWidgets('leaving while it is pouring is safe', (tester) async {
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    await pumpPage(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
