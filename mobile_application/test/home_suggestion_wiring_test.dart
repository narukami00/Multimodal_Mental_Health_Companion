import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

/// Serves a fixed library so nothing waits on an asset read under fake async.
class _FixedLibrary implements ActivityLibraryRepository {
  const _FixedLibrary(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

final _library = _FixedLibrary([
  Activity(
    id: 'walk',
    title: 'Take a short easy walk',
    description: 'Walk at a comfortable pace for a few minutes.',
    type: ActivityType.movement,
    effort: ActivityEffort.low,
    durationMinutes: 5,
    contexts: const [],
    targetStates: const [],
    review: ActivityReviewMetadata(
      status: ActivityReviewStatus.approved,
      evidenceTier: ActivityEvidenceTier.lifestyle,
      reviewerRole: 'test',
      reviewedAt: DateTime(2026, 1, 1),
    ),
  ),
]);

/// An idea only arrives after the day's check-in, so by default there is one.
Future<SessionController> _sessionController({bool checkedIn = true}) async {
  final repository = InMemorySessionRepository();
  if (checkedIn) {
    await repository.save(
      SessionRecord(
        id: 'today',
        createdAt: DateTime.now(),
        mode: CaptureMode.text,
        mood: 'Steady',
      ),
    );
  }
  final controller = SessionController(
    repository: repository,
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
  await controller.load();
  return controller;
}

Future<void> _pumpShell(
  WidgetTester tester,
  SuggestionController suggestionController, {
  ProfileController? profileController,
  bool checkedIn = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final onboarding = InMemoryOnboardingRepository();
  await onboarding.complete();

  await tester.pumpWidget(
    SolaceApp(
      onboardingRepository: onboarding,
      sessionController: await _sessionController(checkedIn: checkedIn),
      suggestionController: suggestionController,
      profileController: profileController,
    ),
  );
  await tester.pump();
}

void main() {
  // These exercise the shell itself. Every earlier test covered the pieces —
  // the schedule, the engine, the card in isolation — and all of them passed
  // while the card could not appear at all, because the wiring between them was
  // never checked.
  testWidgets('a suggestion reaches the Home screen', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _library,
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpShell(tester, controller);

    expect(find.byKey(const ValueKey('task-accept')), findsOneWidget);
    expect(find.text('Take a short easy walk'), findsOneWidget);
  });

  testWidgets('nothing is shown before the library has loaded', (tester) async {
    // Without a warm-up the peek cannot choose anything, and Home must simply
    // show no card rather than an empty one.
    final controller = SuggestionController(
      libraryRepository: _library,
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();

    await _pumpShell(tester, controller);

    expect(find.byKey(const ValueKey('task-accept')), findsNothing);
  });

  testWidgets('no idea is offered before today check-in', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _library,
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpShell(tester, controller, checkedIn: false);

    expect(find.byKey(const ValueKey('task-accept')), findsNothing);
  });

  testWidgets('declining closes the idea and it does not come back', (
    tester,
  ) async {
    final controller = SuggestionController(
      libraryRepository: _library,
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpShell(tester, controller);
    await tester.tap(find.byKey(const ValueKey('task-decline')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-accept')), findsNothing);
    expect(controller.history.single.skipReason, SuggestionSkipReason.notNow);
  });

  testWidgets('trying it records one nudge, starts it, and leaves Home for the doing screen', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _library,
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpShell(tester, controller);
    await tester.tap(find.byKey(const ValueKey('task-accept')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final record = controller.history.single;
    expect(record.proactive, isTrue);
    // Started, not finished: nothing is concluded until they say they are done.
    expect(record.acceptedAt, isNotNull);
    expect(record.done, isNull);
    expect(record.status, SuggestionStatus.shown);
    expect(controller.doingNow()?.id, record.id);
    // The card faded out first, and the doing screen has taken its place.
    expect(find.byKey(const ValueKey('task-accept')), findsNothing);
    expect(find.text("YOU'RE ON THIS"), findsOneWidget);
  });

  testWidgets('rebuilding Home records the impression once', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _library,
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpShell(tester, controller);
    expect(find.byKey(const ValueKey('task-accept')), findsOneWidget);

    // Home rebuilds often. The impression is written once, and the idea stays
    // on screen even though showing it used up the day's budget.
    controller.notifyListeners();
    await tester.pump();
    await tester.pump();
    controller.notifyListeners();
    await tester.pump();

    expect(controller.history.single.status, SuggestionStatus.shown);
    expect(find.byKey(const ValueKey('task-accept')), findsOneWidget);
  });

  group('setup card', () {
    testWidgets('appears while setup is unfinished', (tester) async {
      // It could never render before: the completion flag was defaulted to
      // true, so Home always believed there was nothing left to do.
      final controller = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: InMemorySuggestionRepository(),
      );
      await controller.load();
      await controller.warmUp();

      await _pumpShell(tester, controller);

      expect(find.textContaining('Setup'), findsOneWidget);
    });

    testWidgets('disappears once setup is done', (tester) async {
      final controller = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: InMemorySuggestionRepository(),
      );
      await controller.load();
      await controller.warmUp();

      final profileController = ProfileController(
        repository: InMemoryProfileRepository(),
      );
      await profileController.load();
      await profileController.savePreferences(
        preferredActivities: const ['movement'],
        constraints: const [],
        interactionPreferences: const [],
        neverSuggest: const [],
      );
      await profileController.markBlockSkipped(QuizBlock.erqS);
      await profileController.markBlockSkipped(QuizBlock.gad7);
      await profileController.markBlockSkipped(QuizBlock.phq9);

      await _pumpShell(
        tester,
        controller,
        profileController: profileController,
      );

      expect(find.textContaining('Setup'), findsNothing);
    });
  });

  group('an idea in progress', () {
    const context = RecommendationContext(profileAgeDays: 20);

    Future<(SuggestionController, SuggestionRecord, String)> started() async {
      final controller = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: InMemorySuggestionRepository(),
      );
      await controller.load();
      await controller.warmUp();
      final recommendation = controller.peek(profile: const UserProfile(), context: context)!;
      final record = await controller.commit(recommendation, context: context, proactive: true);
      await controller.startDoing(record.id);
      return (controller, record, recommendation.activity.title);
    }

    testWidgets('takes the slot on Today: it is shown as being done, with nothing new offered', (tester) async {
      final (controller, _, title) = await started();

      await _pumpShell(tester, controller);

      expect(find.text(title), findsOneWidget);
      expect(find.text("I'm done"), findsOneWidget);
      expect(find.text('Something came up'), findsOneWidget);
      expect(find.text("I'll try it"), findsNothing);
    });

    testWidgets('"something came up" ends it with no verdict', (tester) async {
      final (controller, record, _) = await started();
      await _pumpShell(tester, controller);

      await tester.tap(find.byKey(const ValueKey('task-decline')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final ended = controller.history.firstWhere((r) => r.id == record.id);
      expect(ended.status, SuggestionStatus.skipped);
      expect(ended.skipReason, SuggestionSkipReason.notNow);
      expect(ended.done, isNull);
      expect(controller.doingNow(), isNull);
    });

    testWidgets('done writes the finishing time and asks how they feel now', (tester) async {
      final (controller, record, _) = await started();
      await _pumpShell(tester, controller);

      await tester.tap(find.byKey(const ValueKey('task-accept')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final finished = controller.history.firstWhere((r) => r.id == record.id);
      expect(finished.done, isTrue);
      expect(finished.completedAt, isNotNull);
      expect(find.text('How do you feel now?'), findsOneWidget);
    });
  });
}
