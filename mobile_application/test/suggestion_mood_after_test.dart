import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/contracts/provider_contracts.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/safety/support_resources_page.dart';
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

/// Reads every note as the given mood at the given confidence, or as nothing when [mood] is null.
class _Reads implements EmotionAnalyzer {
  const _Reads(this.mood, this.tier);

  final String? mood;
  final String tier;

  @override
  Future<List<EmotionResult>> analyze(SessionInput input) async => [
    EmotionResult(
      sessionId: input.sessionId,
      modality: EmotionModality.text,
      timestamp: DateTime(2026, 10, 1),
      modelVersion: 'test',
      mood: mood,
      tier: tier,
    ),
  ];
}

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

    Future<void> openOnDecide(WidgetTester tester, {EmotionAnalyzer analyzer = const MockEmotionAnalyzer()}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      suggestionController = _controller();
      sessionController = SessionController(
        repository: InMemorySessionRepository(),
        emotionAnalyzer: analyzer,
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

    testWidgets('after doing an idea, picking a word records how they feel', (tester) async {
      await openOnDecide(tester);

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      expect(find.text('How do you feel now?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('feel-Steady')));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final record = suggestionController.currentRecord!;
      expect(record.moodAfter, 'Steady');
      // Taken from the check-in made just before the idea was offered.
      expect(record.moodBefore, 'Wobbly');
      expect(record.done, isTrue);
      expect(find.text('Thanks for telling me'), findsOneWidget);
    });

    testWidgets('skipping records no mood and costs nothing', (tester) async {
      await openOnDecide(tester);

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip this'));
      await tester.pumpAndSettle();

      final record = suggestionController.history.single;
      expect(record.moodAfter, isNull);
      expect(record.done, isTrue);
    });

    testWidgets('Save does nothing until something is chosen or written', (tester) async {
      await openOnDecide(tester);

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('How do you feel now?'), findsOneWidget);
      expect(suggestionController.history.single.moodAfter, isNull);
    });

    testWidgets('with no word picked, a note the model reads clearly stands in for it', (tester) async {
      await openOnDecide(tester, analyzer: const _Reads('upbeat', 'clear'));

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'That was lovely, I feel so much lighter');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final record = suggestionController.history.single;
      expect(record.moodAfter, 'Bright');
      expect(record.comment, 'That was lovely, I feel so much lighter');
    });

    testWidgets('a note the model only hints at records the note, not a mood', (tester) async {
      await openOnDecide(tester, analyzer: const _Reads('upbeat', 'hint'));

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'It was fine I suppose');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final record = suggestionController.history.single;
      expect(record.moodAfter, isNull);
      expect(record.comment, 'It was fine I suppose');
    });

    testWidgets('a note the model could not read records the note, not a mood', (tester) async {
      await openOnDecide(tester, analyzer: const _Reads(null, 'clear'));

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hmm');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(suggestionController.history.single.moodAfter, isNull);
    });

    testWidgets('a picked word wins over what the note reads as', (tester) async {
      await openOnDecide(tester, analyzer: const _Reads('upbeat', 'clear'));

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feel-Wobbly')));
      await tester.enterText(find.byType(TextField), 'Everything is great');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(suggestionController.history.single.moodAfter, 'Wobbly');
    });

    testWidgets('a note that raises a safety concern shows support first and saves nothing yet', (tester) async {
      await openOnDecide(tester);

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'I want to kill myself');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(SupportResourcesPage), findsOneWidget);
      expect(suggestionController.history.single.comment, isNull);
    });

    testWidgets('"I didn\'t actually do this" takes the completion back, so nothing is learned from it', (tester) async {
      await openOnDecide(tester);

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      expect(suggestionController.history.single.done, isTrue);

      await tester.tap(find.byKey(const ValueKey('not-actually-done')));
      await tester.pumpAndSettle();

      final record = suggestionController.history.single;
      expect(record.done, isFalse);
      expect(record.status, SuggestionStatus.skipped);
      expect(record.skipReason, SuggestionSkipReason.notNow);
      expect(record.moodAfter, isNull);
    });

    testWidgets('the step still fits when the text is enlarged', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openOnDecide(tester);

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feel-Steady')));
      await tester.tap(find.byKey(const ValueKey('again-yes')));
      await tester.enterText(find.byType(TextField), 'A bit of fresh air helped.');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
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

  });

  group('what makes a completion eligible for a late review', () {
    test('one that already has how they felt is not offered again', () async {
      final controller = _controller();
      await controller.load();
      await controller.suggest(profile: const UserProfile(), context: _context);
      await controller.recordCompletion();
      final id = controller.currentRecord!.id;
      expect(controller.pendingRating(), isNotNull);

      await controller.recordMoodAfter(recordId: id, moodAfter: 'Steady');

      expect(controller.pendingRating(), isNull);
    });

    test('a completion taken back is never offered, and counts as not done', () async {
      final controller = _controller();
      await controller.load();
      await controller.suggest(profile: const UserProfile(), context: _context);
      await controller.recordCompletion();
      final id = controller.currentRecord!.id;

      await controller.markNotDone(id);

      expect(controller.pendingRating(), isNull);
      expect(controller.currentRecord!.done, isFalse);
      expect(controller.currentRecord!.status, SuggestionStatus.skipped);
    });
  });
}
