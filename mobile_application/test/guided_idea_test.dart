import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
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

class _Library implements ActivityLibraryRepository {
  const _Library(this.activities);
  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

Activity _activity(String id, {ExerciseGuide? guide}) => Activity(
  id: id,
  title: 'Idea $id',
  description: 'A small thing to try.',
  type: ActivityType.mindfulness,
  effort: ActivityEffort.low,
  durationMinutes: 3,
  contexts: const [],
  targetStates: const [],
  guide: guide,
  review: ActivityReviewMetadata(
    status: ActivityReviewStatus.approved,
    evidenceTier: ActivityEvidenceTier.lifestyle,
    reviewerRole: 'test',
    reviewedAt: DateTime(2026, 1, 1),
  ),
);

void main() {
  Future<(SuggestionController, String)> started(Activity activity) async {
    final controller = SuggestionController(
      libraryRepository: _Library([activity]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();
    final record = await controller.commit(
      Recommendation.restored(activity, null),
      context: const RecommendationContext(profileAgeDays: 20),
      fresh: true,
    );
    await controller.startDoing(record.id);
    return (controller, record.id);
  }

  Future<void> open(WidgetTester tester, SuggestionController controller, String id) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
    await profile.ensureFirstRun();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SuggestionPage(
          suggestionController: controller,
          profileController: profile,
          safetyController: SafetyController(screener: const KeywordSafetyScreener(), repository: InMemorySafetyEventRepository()),
          sessionController: SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer()),
          resumeRecordId: id,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a guided idea offers its exercise, and finishing it counts as done', (tester) async {
    final (controller, id) = await started(_activity('a', guide: ExerciseGuide.grounding));
    await open(tester, controller, id);

    expect(find.byKey(const ValueKey('begin-guided')), findsOneWidget);
    expect(find.text("I'm done"), findsOneWidget, reason: 'finishing without the exercise stays possible');

    await tester.tap(find.byKey(const ValueKey('begin-guided')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-begin')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('grounding-next')));
      await tester.pumpAndSettle();
    }
    expect(controller.history.single.done, isNull, reason: 'not done until they finish');
    await tester.tap(find.byKey(const ValueKey('exercise-finish')));
    await tester.pumpAndSettle();

    expect(controller.history.single.done, isTrue);
    expect(controller.history.single.status, SuggestionStatus.completed);
    expect(find.text('How do you feel now?'), findsOneWidget);
  });

  testWidgets('stopping the exercise early leaves the idea still being done', (tester) async {
    final (controller, id) = await started(_activity('a', guide: ExerciseGuide.breathing));
    await open(tester, controller, id);

    await tester.tap(find.byKey(const ValueKey('begin-guided')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exercise-stop')));
    await tester.pumpAndSettle();

    expect(controller.history.single.done, isNull);
    expect(find.byKey(const ValueKey('begin-guided')), findsOneWidget);
  });

  testWidgets('an ordinary idea has no exercise button and keeps its "I\'m done"', (tester) async {
    final (controller, id) = await started(_activity('plain'));
    await open(tester, controller, id);

    expect(find.byKey(const ValueKey('begin-guided')), findsNothing);
    expect(find.text("I'm done"), findsOneWidget);
  });
}
