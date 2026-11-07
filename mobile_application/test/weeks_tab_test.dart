import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/insights/insights_page.dart';
import 'package:solace_mobile/features/insights/weeks_tab.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  final now = DateTime(2026, 3, 18, 10);

  Future<SessionController> controller(List<SessionRecord> records) async {
    final repository = InMemorySessionRepository();
    for (final r in records) {
      await repository.save(r);
    }
    final sessions = SessionController(repository: repository, emotionAnalyzer: const MockEmotionAnalyzer());
    await sessions.load();
    return sessions;
  }

  SessionRecord entry(DateTime at, String mood) =>
      SessionRecord(id: at.toIso8601String(), createdAt: at, mode: CaptureMode.text, mood: mood);

  Future<void> pumpTab(WidgetTester tester, SessionController sessions) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: WeeksTab(sessionController: sessions, clock: () => now))),
    ));
    await tester.pump();
  }

  testWidgets('before any week is over it says what will appear, and asks for nothing', (tester) async {
    await pumpTab(tester, await controller([entry(DateTime(2026, 3, 17), 'Steady')])); // this week only
    expect(find.text('Your first week will show up here'), findsOneWidget);
  });

  testWidgets('shows the bigger picture and a card for each finished week, newest first', (tester) async {
    final sessions = await controller([
      entry(DateTime(2026, 3, 3, 9), 'Steady'),
      entry(DateTime(2026, 3, 4, 9), 'Bright'),
      entry(DateTime(2026, 3, 10, 9), 'Steady'),
    ]);
    await pumpTab(tester, sessions);
    expect(find.byKey(const ValueKey('weeks-overall')), findsOneWidget);
    expect(find.text('Over 2 weeks, you showed up on 3 days.'), findsOneWidget);
    expect(find.text('9 to 15 Mar'), findsOneWidget);
    expect(find.text('2 to 8 Mar'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('week-2026-03-09'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('week-2026-03-02'))).dy));
  });

  testWidgets('is a tab on the Insights page', (tester) async {
    final sessions = await controller([entry(DateTime(2026, 3, 3, 9), 'Steady')]);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: InsightsPage(sessionController: sessions, clock: () => now)));
    await tester.pump();
    await tester.tap(find.text('Weeks'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('THE BIGGER PICTURE'), findsOneWidget);
  });
}
