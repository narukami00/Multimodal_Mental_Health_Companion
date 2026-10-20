import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/features/insights/insights_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

class _Library implements ActivityLibraryRepository {
  @override
  Future<List<Activity>> load() async => const [];
}

SessionController _controller() => SessionController(
  repository: InMemorySessionRepository(),
  emotionAnalyzer: const MockEmotionAnalyzer(),
);

Future<void> _pump(
  WidgetTester tester,
  SessionController sessions, {
  DateTime Function()? clock,
}) async {
  final suggestions = SuggestionController(
    libraryRepository: _Library(),
    suggestionRepository: InMemorySuggestionRepository(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: InsightsPage(
        sessionController: sessions,
        suggestionController: suggestions,
        clock: clock ?? () => DateTime(2026, 10, 31, 20),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('starts on Mood with an honest empty state, and nothing invented', (
    tester,
  ) async {
    await _pump(tester, _controller());

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Your mood words will gather here'), findsOneWidget);
    // The old demo content is gone for good.
    expect(find.text('EMOTIONAL DRIFT'), findsNothing);
    expect(find.text('NOTICINGS'), findsNothing);
    expect(find.textContaining('stepping outside'), findsNothing);
  });

  testWidgets('offers Mood and Helps, and no Phone or Moments without their data', (
    tester,
  ) async {
    await _pump(tester, _controller());

    expect(find.byKey(const ValueKey('insights-tab-mood')), findsOneWidget);
    expect(find.byKey(const ValueKey('insights-tab-helps')), findsOneWidget);
    expect(find.byKey(const ValueKey('insights-tab-phone')), findsNothing);
    expect(find.byKey(const ValueKey('insights-tab-moments')), findsNothing);
  });

  testWidgets('Helps explains what would fill it', (tester) async {
    await _pump(tester, _controller());

    await tester.tap(find.byKey(const ValueKey('insights-tab-helps')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Nothing to say yet, and that is fine'), findsOneWidget);
    expect(find.textContaining('three tries'), findsOneWidget);
  });

  testWidgets('switching tabs does not push the new tab down and then snap it back up', (tester) async {
    final sessions = _controller();
    await sessions.load();
    await sessions.saveSession(mode: CaptureMode.text, text: 'a quiet morning', mood: 'Steady');
    await _pump(tester, sessions, clock: DateTime.now); // Mood is now much taller than Helps
    final text = find.text('Nothing to say yet, and that is fine');

    await tester.tap(find.byKey(const ValueKey('insights-tab-helps')));
    await tester.pump(const Duration(milliseconds: 110)); // mid-transition: both tabs are in the tree
    final during = tester.getTopLeft(text).dy;
    await tester.pump(const Duration(milliseconds: 600));
    final after = tester.getTopLeft(text).dy;

    // It may still be rising by a few pixels; it must never sit far low (centred in the taller Mood tab).
    expect((during - after).abs(), lessThan(12));
  });

  testWidgets('a check-in with a mood word draws the strip and a plain summary', (
    tester,
  ) async {
    final sessions = _controller();
    await sessions.load();
    await sessions.saveSession(
      mode: CaptureMode.text,
      text: 'a quiet morning',
      mood: 'Steady',
    );
    await _pump(tester, sessions, clock: DateTime.now);

    expect(find.byKey(const ValueKey('mood-strip')), findsOneWidget);
    expect(
      find.text('You checked in on 1 of the last 30 days. Calm came up most, on 1.'),
      findsOneWidget,
    );
  });
}
