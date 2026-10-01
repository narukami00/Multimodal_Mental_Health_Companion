import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_page.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

class _FixedLibrary implements ActivityLibraryRepository {
  const _FixedLibrary(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

Activity _activity() {
  return Activity(
    id: 'only',
    title: 'A short walk',
    description: 'A small thing to try.',
    type: ActivityType.movement,
    effort: ActivityEffort.low,
    durationMinutes: 10,
    contexts: const [],
    targetStates: const [],
    review: ActivityReviewMetadata(
      status: ActivityReviewStatus.approved,
      evidenceTier: ActivityEvidenceTier.lifestyle,
      reviewerRole: 'test',
      reviewedAt: DateTime(2026, 1, 1),
    ),
  );
}

SuggestionController _controller() => SuggestionController(
  libraryRepository: _FixedLibrary([_activity()]),
  suggestionRepository: InMemorySuggestionRepository(),
);

const _context = RecommendationContext(profileAgeDays: 20);

void main() {
  group('SuggestionController.recordMoodAfter', () {
    Future<(SuggestionController, String)> doneIdea() async {
      final controller = _controller();
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
      );
      await controller.recordCompletion();
      return (controller, controller.currentRecord!.id);
    }

    test('stores how they feel now and the mood from before', () async {
      final (controller, id) = await doneIdea();

      await controller.recordMoodAfter(
        recordId: id,
        moodAfter: 'Steady',
        moodBefore: 'Wobbly',
      );

      final record = controller.currentRecord!;
      expect(record.moodAfter, 'Steady');
      expect(record.moodBefore, 'Wobbly');
      // Saying how they feel is not a rating and must not disturb the rest.
      expect(record.done, isTrue);
      expect(record.useful, isNull);
      expect(record.status, SuggestionStatus.completed);
    });

    test('an idea they did not do gets no mood after it', () async {
      final controller = _controller();
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
      );

      await controller.recordMoodAfter(
        recordId: controller.currentRecord!.id,
        moodAfter: 'Bright',
      );

      expect(controller.currentRecord!.moodAfter, isNull);
    });

    test('an unknown record is ignored rather than throwing', () async {
      final (controller, _) = await doneIdea();

      await controller.recordMoodAfter(recordId: 'nope', moodAfter: 'Bright');

      expect(controller.currentRecord!.moodAfter, isNull);
    });

    test('saying it again replaces the earlier answer', () async {
      final (controller, id) = await doneIdea();

      await controller.recordMoodAfter(recordId: id, moodAfter: 'Quiet');
      await controller.recordMoodAfter(recordId: id, moodAfter: 'Bright');

      expect(controller.currentRecord!.moodAfter, 'Bright');
    });
  });

  group('SuggestionPage closing screen', () {
    late SuggestionController suggestionController;
    late SessionController sessionController;
    late ProfileController profileController;

    Future<void> openOnDecide(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      suggestionController = _controller();
      sessionController = SessionController(
        repository: InMemorySessionRepository(),
        emotionAnalyzer: const MockEmotionAnalyzer(),
      );
      profileController = ProfileController(
        repository: InMemoryProfileRepository(),
      );
      await profileController.load();
      await profileController.ensureFirstRun();
      await sessionController.saveSession(
        mode: CaptureMode.text,
        mood: 'Wobbly',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SuggestionPage(
            suggestionController: suggestionController,
            profileController: profileController,
            safetyController: SafetyController(
              screener: const KeywordSafetyScreener(),
              repository: InMemorySafetyEventRepository(),
            ),
            sessionController: sessionController,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('after doing an idea, one tap records how they feel', (
      tester,
    ) async {
      await openOnDecide(tester);

      await tester.tap(find.text('I did it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip this'));
      await tester.pumpAndSettle();

      expect(find.text('How do you feel now?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('feel-Steady')));
      await tester.pumpAndSettle();

      final record = suggestionController.currentRecord!;
      expect(record.moodAfter, 'Steady');
      // Taken from the check-in made just before the idea was offered.
      expect(record.moodBefore, 'Wobbly');
      expect(record.done, isTrue);
      expect(find.text('Noted, thank you.'), findsOneWidget);
    });

    testWidgets('ignoring the question records nothing and costs nothing', (
      tester,
    ) async {
      await openOnDecide(tester);

      await tester.tap(find.text('I did it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip this'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      final record = suggestionController.history.single;
      expect(record.moodAfter, isNull);
      expect(record.done, isTrue);
    });

    testWidgets('declining an idea never asks how they feel', (tester) async {
      await openOnDecide(tester);

      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not right now'));
      await tester.pumpAndSettle();

      expect(find.text('How do you feel now?'), findsNothing);
      expect(find.byKey(const ValueKey('feel-Steady')), findsNothing);
    });

    testWidgets('it is asked after a rating too', (tester) async {
      await openOnDecide(tester);

      await tester.tap(find.text('I did it'));
      await tester.pumpAndSettle();
      // Rate with the fourth star.
      await tester.tapAt(
        tester.getCenter(find.byType(CustomPaint).at(3)),
      );
      await tester.pumpAndSettle();

      expect(find.text('How do you feel now?'), findsOneWidget);
    });
  });
}
