import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/domain/footprint/life_pulse_policy.dart';
import 'package:solace_mobile/features/footprint/life_pulse_card.dart';
import 'package:solace_mobile/features/footprint/life_pulse_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('life pulse prompts every ~36h when no safety or anomaly prompt is active', () async {
    var now = DateTime(2026, 11, 10, 10);
    final prefs = await SharedPreferences.getInstance();
    final controller = LifePulseController(
      preferences: prefs,
      clock: () => now,
      safetyActive: () => false,
      breakPromptActive: () => false,
    );

    await controller.refresh();
    expect(controller.current, isNotNull);

    await controller.answer(moodTag: 'stressed', note: 'Exam prep week');
    expect(controller.current, isNull);
    expect(controller.latestFreshSignal?.note, 'Exam prep week');
    expect(controller.activeThemes(), ['work']);

    // 20h later: still within 36h cooldown.
    now = now.add(const Duration(hours: 20));
    await controller.refresh();
    expect(controller.current, isNull);

    // 37h total after decision: re-prompts gently.
    now = now.add(const Duration(hours: 17));
    await controller.refresh();
    expect(controller.current, isNotNull);
  });

  test('suppresses life pulse while safety support or break prompt is active', () async {
    var safety = true;
    var anomaly = false;
    final prefs = await SharedPreferences.getInstance();
    final controller = LifePulseController(
      preferences: prefs,
      clock: () => DateTime(2026, 11, 10, 10),
      safetyActive: () => safety,
      breakPromptActive: () => anomaly,
    );

    await controller.refresh();
    expect(controller.current, isNull);

    safety = false;
    anomaly = true;
    await controller.refresh();
    expect(controller.current, isNull);

    anomaly = false;
    await controller.refresh();
    expect(controller.current, isNotNull);
  });

  test('mute, dismiss and clearAll behave cleanly', () async {
    var now = DateTime(2026, 11, 10, 10);
    final prefs = await SharedPreferences.getInstance();
    final controller = LifePulseController(
      preferences: prefs,
      clock: () => now,
    );

    await controller.refresh();
    expect(controller.current, isNotNull);

    await controller.dismiss();
    expect(controller.current, isNull);

    now = now.add(lifePulseCadence + const Duration(hours: 1));
    await controller.refresh();
    expect(controller.current, isNotNull);

    await controller.setEnabled(false);
    expect(controller.enabled, isFalse);
    expect(controller.current, isNull);

    await controller.setEnabled(true);
    expect(controller.enabled, isTrue);
    expect(controller.current, isNotNull);

    await controller.answer(moodTag: 'sleep', note: 'Woke up early');
    expect(controller.latestFreshSignal, isNotNull);

    await controller.clearAll();
    expect(controller.latestFreshSignal, isNull);
    expect(controller.entries, isEmpty);
  });

  testWidgets('LifePulseCard greets user by name and saves quick note + chat trigger', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = LifePulseController(
      preferences: prefs,
      clock: () => DateTime(2026, 11, 10, 11),
    );
    await controller.refresh();

    var openedChat = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, __) => LifePulseCard(
                controller: controller,
                displayName: 'Rafsan',
                onStartChatWithContext: () => openedChat = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('life-pulse-card')), findsOneWidget);
    expect(find.text('Hey Rafsan, everything alright?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('life-pulse-note-toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('life-pulse-stressed')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('life-pulse-note-input')),
      'Deadlines piling up',
    );
    await tester.tap(find.byKey(const ValueKey('life-pulse-chat')));
    await tester.pumpAndSettle();

    expect(openedChat, isTrue);
    expect(controller.latestFreshSignal?.moodTag, 'stressed');
    expect(controller.latestFreshSignal?.note, 'Deadlines piling up');
    expect(find.byKey(const ValueKey('life-pulse-card')), findsNothing);
  });
}
