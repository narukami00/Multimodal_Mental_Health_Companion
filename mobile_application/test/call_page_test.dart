import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/call/call_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  SafetyController safety() => SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );

  Future<void> pumpCall(WidgetTester tester) async {
    // Use a mobile-sized surface so dock controls are in-viewport.
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: CallPage(safetyController: safety())),
    );
    // Pump 2 s so the intro delay passes and conversation timer doesn't linger.
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('renders session chrome and toggles mic state', (tester) async {
    await pumpCall(tester);

    expect(find.text('Voice reflection'), findsOneWidget);
    expect(
      find.text('Take your time. Silence is welcome here.'),
      findsOneWidget,
    );
    expect(find.text('MIC ON'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.mic_none_rounded));
    await tester.tap(find.byIcon(Icons.mic_none_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MUTED'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.videocam_outlined).last);
    await tester.tap(find.byIcon(Icons.videocam_outlined).last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CAMERA ON · YOU ARE VISIBLE'), findsOneWidget);
  });

  testWidgets('ending the session opens the care overlay', (tester) async {
    await pumpCall(tester);

    await tester.ensureVisible(find.byIcon(Icons.call_end_rounded));
    await tester.tap(find.byIcon(Icons.call_end_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Take good care'), findsOneWidget);
    expect(find.text('Start a new session'), findsOneWidget);
    expect(find.text('Return home'), findsOneWidget);
  });
}
