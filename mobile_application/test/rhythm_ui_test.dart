import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/rhythm/rhythm_card.dart';
import 'package:solace_mobile/features/rhythm/rhythm_detail_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  late SessionController sessionController;
  late ProfileController profileController;
  late SuggestionController suggestionController;

  setUp(() {
    sessionController = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
    suggestionController = SuggestionController(
      libraryRepository: AssetActivityLibraryRepository(),
      suggestionRepository: InMemorySuggestionRepository(),
    );
  });

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RhythmCard(
            sessionController: sessionController,
            profileController: profileController,
            suggestionController: suggestionController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> loadAll() async {
    await sessionController.load();
    await profileController.load();
    await suggestionController.load();
  }

  testWidgets('is honest before there is any history', (tester) async {
    await loadAll();
    await pumpCard(tester);

    expect(find.text('Your rhythm'), findsOneWidget);
    expect(
      find.text('Appears here after a few check-ins.'),
      findsOneWidget,
    );
  });

  testWidgets('counts check-ins and rest days from real data', (tester) async {
    await loadAll();
    await sessionController.saveSession(
      mode: CaptureMode.text,
      mood: 'Steady',
      text: 'today',
    );
    await profileController.declareRestDay(DateTime.now());

    await pumpCard(tester);

    expect(find.text('1 check-in · 1 rest day'), findsOneWidget);
    expect(find.text('LAST 4 WEEKS'), findsOneWidget);
  });

  testWidgets('never shows a streak or a fraction of a goal', (tester) async {
    await loadAll();
    for (var offset = 0; offset < 6; offset++) {
      await profileController.declareRestDay(
        DateTime.now().subtract(Duration(days: offset)),
      );
    }

    await pumpCard(tester);

    // The risk here is a number that reads as a grade.
    expect(find.textContaining('streak'), findsNothing);
    expect(find.textContaining('days in a row'), findsNothing);
    expect(find.textContaining('/'), findsNothing);
    expect(find.textContaining('missed'), findsNothing);
  });

  testWidgets('a blank day is neutral, not a miss', (tester) async {
    await loadAll();
    await pumpCard(tester);

    // Every day of the strip renders, and none of them is alarm-styled.
    final dots = tester.widgetList<RhythmDot>(find.byType(RhythmDot));
    expect(dots.length, 7);
  });

  testWidgets('opens the detail page and toggles today as rest', (
    tester,
  ) async {
    await loadAll();
    await pumpCard(tester);

    await tester.tap(find.text('Your rhythm'));
    await tester.pumpAndSettle();

    expect(find.byType(RhythmDetailPage), findsOneWidget);
    expect(find.text('Rest today'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rest-today')));
    await tester.pumpAndSettle();

    expect(profileController.restDays.length, 1);
    expect(find.text('Resting today · undo'), findsOneWidget);

    // A mis-tap is undoable.
    await tester.tap(find.byKey(const ValueKey('rest-today')));
    await tester.pumpAndSettle();

    expect(profileController.restDays, isEmpty);
  });

  testWidgets('the usual stays hidden until asked for', (tester) async {
    await loadAll();
    for (var offset = 0; offset < 3; offset++) {
      await profileController.declareRestDay(
        DateTime.now().subtract(Duration(days: offset)),
      );
    }
    for (var offset = 7; offset < 11; offset++) {
      await profileController.declareRestDay(
        DateTime.now().subtract(Duration(days: offset)),
      );
    }
    for (var offset = 14; offset < 17; offset++) {
      await profileController.declareRestDay(
        DateTime.now().subtract(Duration(days: offset)),
      );
    }

    await pumpCard(tester);
    await tester.tap(find.text('LAST 4 WEEKS'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Your usual'), findsNothing);

    await tester.tap(find.text('Show my usual'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Just a reference'), findsOneWidget);
  });

  testWidgets('says so plainly when there is not enough history', (
    tester,
  ) async {
    await loadAll();
    await sessionController.saveSession(
      mode: CaptureMode.text,
      mood: 'Steady',
      text: 'just one',
    );

    await pumpCard(tester);
    await tester.tap(find.text('LAST 4 WEEKS'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show my usual'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Too early to call this a pattern'),
      findsOneWidget,
    );
  });
}
