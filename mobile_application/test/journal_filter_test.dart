import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/journal/journal_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  late SessionController sessions;

  setUp(() async {
    sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    // Legacy picked words stand in for model moods: effectiveMood falls back to them.
    await sessions.saveSession(mode: CaptureMode.text, text: 'tired one', mood: 'Tender');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await sessions.saveSession(mode: CaptureMode.voice, text: 'tense one', mood: 'Wobbly');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await sessions.saveSession(mode: CaptureMode.text, text: 'plain one');
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: JournalPage(sessionController: sessions))));
    await tester.pump();
  }

  testWidgets('the filter icon narrows entries by how they read and by kind, and can be reset', (tester) async {
    await pump(tester);
    expect(find.text('tired one'), findsOneWidget);
    expect(find.text('tense one'), findsOneWidget);
    expect(find.text('plain one'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('journal-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journal-filter-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('filter-mood-Low')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('tired one'), findsOneWidget);
    expect(find.text('tense one'), findsNothing);
    expect(find.text('plain one'), findsNothing);

    // kind of entry combines with the mood
    await tester.tap(find.byKey(const ValueKey('journal-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-mode-voice')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('filter-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('journal-nothing-matches')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('journal-clear-filter')));
    await tester.pumpAndSettle();
    expect(find.text('tired one'), findsOneWidget);
    expect(find.text('tense one'), findsOneWidget);
    expect(find.text('plain one'), findsOneWidget);
  });

  testWidgets('"Not read yet" finds entries without any reading', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('journal-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-mood-Not read yet')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('plain one'), findsOneWidget);
    expect(find.text('tired one'), findsNothing);
  });
}
