import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/journal/journal_search.dart';
import 'package:solace_mobile/features/chat/highlighted_text.dart';
import 'package:solace_mobile/features/journal/journal_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  group('journal_search & JournalFilter date range', () {
    test('matchesJournalQuery matches multi-term text, mood, and mode', () {
      final entry = SessionRecord(
        id: 's1',
        createdAt: DateTime(2026, 11, 10, 14),
        mode: CaptureMode.voice,
        text: 'Took a slow walk by the river and felt lighter.',
        mood: 'Calm',
      );
      expect(matchesJournalQuery(entry, 'river walk'), isTrue);
      expect(matchesJournalQuery(entry, 'calm voice'), isTrue);
      expect(matchesJournalQuery(entry, 'river mountain'), isFalse);
    });

    test('journalSearchSnippet centers long text around distant match', () {
      final longText =
          '${'A' * 80} breathing exercise helped settle my racing thoughts today.';
      final snippet = journalSearchSnippet(longText, 'breathing');
      expect(snippet, startsWith('...'));
      expect(snippet, contains('breathing'));
    });

    test('JournalFilter respects inclusive startDate and endDate bounds', () {
      final older = SessionRecord(
        id: 'old',
        createdAt: DateTime(2026, 10, 20, 23, 30),
        mode: CaptureMode.text,
        text: 'Old entry',
      );
      final inside = SessionRecord(
        id: 'in',
        createdAt: DateTime(2026, 11, 10, 23, 45),
        mode: CaptureMode.text,
        text: 'Inside entry',
      );
      final newer = SessionRecord(
        id: 'new',
        createdAt: DateTime(2026, 11, 12, 8),
        mode: CaptureMode.text,
        text: 'Newer entry',
      );

      final filter = JournalFilter(
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 10),
      );
      expect(filter.isActive, isTrue);
      expect(filter.matches(older), isFalse);
      expect(filter.matches(inside), isTrue);
      expect(filter.matches(newer), isFalse);
    });
  });

  group('JournalPage search and time range UI', () {
    late SessionController sessions;

    setUp(() async {
      final now = DateTime.now();
      final repo = InMemorySessionRepository();
      await repo.save(
        SessionRecord(
          id: 'today-1',
          createdAt: now.subtract(const Duration(minutes: 10)),
          mode: CaptureMode.text,
          text: 'Morning coffee and quiet breathing before work',
          mood: 'Calm',
        ),
      );
      await repo.save(
        SessionRecord(
          id: 'old-1',
          createdAt: now.subtract(const Duration(days: 14)),
          mode: CaptureMode.voice,
          text: 'Long evening walk through the park',
          mood: 'Upbeat',
        ),
      );
      sessions = SessionController(
        repository: repo,
        emotionAnalyzer: const MockEmotionAnalyzer(),
      );
      await sessions.load();
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: JournalPage(sessionController: sessions)),
        ),
      );
      await tester.pump();
    }

    testWidgets('search button filters entries and highlights matching keywords',
        (tester) async {
      await pump(tester);

      expect(find.byKey(const ValueKey('journal-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-filter')), findsOneWidget);
      expect(find.text('Long evening walk through the park'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('journal-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('journal-search-field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('journal-search-field')),
        'breathing',
      );
      await tester.pump();

      expect(find.text('1 entry'), findsOneWidget);
      expect(find.text('Long evening walk through the park'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is HighlightedText &&
              w.query == 'breathing' &&
              w.text.contains('breathing'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('journal-search-clear')));
      await tester.pump();
      expect(find.text('Long evening walk through the park'), findsOneWidget);
    });

    testWidgets('filter sheet supports time range presets and date pickers',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('journal-filter')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('filter-range-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-range-today')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-range-7d')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-range-30d')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-range-custom')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-date-from')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-date-to')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-range-today')));
      await tester.pump();
      expect(find.text('Apply · 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-apply')));
      await tester.pumpAndSettle();

      expect(find.text('Morning coffee and quiet breathing before work'),
          findsOneWidget);
      expect(find.text('Long evening walk through the park'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('journal-active-clear')));
      await tester.pump();
      expect(find.text('Long evening walk through the park'), findsOneWidget);
    });
  });
}
