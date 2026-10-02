import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/insights/mood_tab.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

SessionRecord _at(int day, int hour, String mood) => SessionRecord(
  id: '$day-$hour',
  createdAt: DateTime(2026, 10, day, hour),
  mode: CaptureMode.text,
  text: 'x',
  mood: mood,
);

Future<SessionController> _controller(List<SessionRecord> records) async {
  final repository = InMemorySessionRepository();
  for (final r in records) {
    await repository.save(r);
  }
  final controller = SessionController(
    repository: repository,
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
  await controller.load();
  return controller;
}

Future<void> _pump(WidgetTester tester, SessionController controller) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MoodTab(
            sessionController: controller,
            clock: () => DateTime(2026, 10, 31, 20),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  testWidgets('with enough check-ins, shows the four parts of the day and what stands out', (
    tester,
  ) async {
    final controller = await tester.runAsync(
      () => _controller([
        for (var d = 1; d <= 10; d++) _at(d, 9, 'Steady'),
        for (var d = 1; d <= 5; d++) _at(d, 19, 'Wobbly'),
        for (var d = 6; d <= 8; d++) _at(d, 19, 'Steady'),
      ]),
    );
    await _pump(tester, controller!);

    expect(find.text('THROUGH THE DAY'), findsOneWidget);
    expect(find.byKey(const ValueKey('through-the-day')), findsOneWidget);
    for (final label in ['Morning', 'Afternoon', 'Evening', 'Night']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('In the evening, 5 of your 8 check-ins'), findsOneWidget);
  });

  testWidgets('with only a few check-ins, shows nothing about the day', (tester) async {
    final controller = await tester.runAsync(
      () => _controller([for (var d = 1; d <= 5; d++) _at(d, 9, 'Steady')]),
    );
    await _pump(tester, controller!);

    expect(find.text('THROUGH THE DAY'), findsNothing);
    expect(find.byKey(const ValueKey('mood-strip')), findsOneWidget);
  });
}
