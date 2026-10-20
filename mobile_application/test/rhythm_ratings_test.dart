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
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/rhythm/rhythm_detail_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_page.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

/// Serves a fixed library so these tests never wait on an asset read.
class _FixedLibrary implements ActivityLibraryRepository {
  const _FixedLibrary(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

final _library = _FixedLibrary([
  Activity(
    id: 'breathing-space',
    title: 'Three quiet breaths',
    description: 'A short pause to notice your breathing.',
    type: ActivityType.mindfulness,
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

SuggestionRecord _rated({
  required int? rating,
  String activityId = 'breathing-space',
}) {
  return SuggestionRecord(
    id: 'seed-$activityId-$rating-${DateTime.now().microsecondsSinceEpoch}',
    activityId: activityId,
    shownAt: DateTime(2026, 9, 20),
    contextTags: const [],
    status: SuggestionStatus.completed,
    rating: rating,
  );
}

/// Starts the idea and says it is done, which lands on the "how do you feel now" step.
Future<void> _didIt(WidgetTester tester) async {
  final start = find.text("I'll do it");
  await tester.ensureVisible(start);
  await tester.pumpAndSettle();
  await tester.tap(start);
  await tester.pumpAndSettle();
  await tester.tap(find.text("I'm done"));
  await tester.pumpAndSettle();
}

Future<void> _pumpNotTodayPage(
  WidgetTester tester,
  SuggestionController suggestionController, {
  ProfileController? profile,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: SuggestionPage(
        suggestionController: suggestionController,
        profileController: profile ??
            ProfileController(
              repository: InMemoryProfileRepository(),
            ),
        safetyController: SafetyController(
          screener: const KeywordSafetyScreener(),
          repository: InMemorySafetyEventRepository(),
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('Suggestion rating capture', () {
    late SuggestionController suggestionController;
    late ProfileController profileController;

    setUp(() {
      suggestionController = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: InMemorySuggestionRepository(),
      );
      profileController = ProfileController(
        repository: InMemoryProfileRepository(),
      );
    });

    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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
          ),
        ),
      );
      // The page loads its suggestion asynchronously and shows a spinner while
      // it does, so settle by pumping rather than waiting for stillness.
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('never invents a rating the user did not choose', (
      tester,
    ) async {
      await pumpPage(tester);

      await _didIt(tester);

      final completed = suggestionController.history
          .where((record) => record.status == SuggestionStatus.completed);
      expect(completed, hasLength(1));
      // Previously every completion was silently stored as a 5.
      expect(completed.single.rating, isNull);
      expect(completed.single.useful, isNull);
    });

    testWidgets('completion is recorded before the rating is asked for', (
      tester,
    ) async {
      await pumpPage(tester);

      // Saying it is done counts straight away, so walking away from the
      // rating step still leaves the completion recorded.
      await _didIt(tester);

      expect(find.text('How do you feel now?'), findsOneWidget);
      final completed = suggestionController.history.single;
      expect(completed.status, SuggestionStatus.completed);
      expect(completed.done, isTrue);
    });

    testWidgets('"yes, again" is a positive verdict and is not a made-up star rating', (tester) async {
      await pumpPage(tester);
      await _didIt(tester);

      await tester.tap(find.byKey(const ValueKey('again-yes')));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final completed = suggestionController.history.single;
      expect(completed.useful, SuggestionUsefulness.up);
      expect(completed.rating, isNull);
      expect(completed.done, isTrue);
    });

    testWidgets('"not really" counts as not helpful', (tester) async {
      await pumpPage(tester);
      await _didIt(tester);

      await tester.tap(find.byKey(const ValueKey('again-no')));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(suggestionController.history.single.useful, SuggestionUsefulness.down);
    });

    testWidgets('skipping the rating leaves the completion intact', (
      tester,
    ) async {
      await pumpPage(tester);
      await _didIt(tester);

      await tester.tap(find.text('Skip this'));
      await tester.pumpAndSettle();

      final completed = suggestionController.history.single;
      // Not rating is a real answer, and it does not undo having done it.
      expect(completed.rating, isNull);
      expect(completed.useful, isNull);
      expect(completed.done, isTrue);
      expect(completed.status, SuggestionStatus.completed);
    });
  });

  group('Not today', () {
    late SuggestionController suggestionController;

    setUp(() {
      suggestionController = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: InMemorySuggestionRepository(),
      );
    });

    testWidgets('"not for me" is recorded with its reason', (tester) async {
      await _pumpNotTodayPage(tester, suggestionController);

      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not for me'));
      await tester.pumpAndSettle();

      final record = suggestionController.history.single;
      expect(record.status, SuggestionStatus.skipped);
      expect(record.skipReason, SuggestionSkipReason.notForMe);
      // Refusing is not a completion.
      expect(record.done, isNull);
      // And the closing screen says what it actually changed.
      expect(find.textContaining('leave this one out'), findsOneWidget);
    });

    testWidgets('"I\'m resting today" is no verdict on the idea, and marks the day as rest', (tester) async {
      final profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();
      await profile.ensureFirstRun();
      await _pumpNotTodayPage(tester, suggestionController, profile: profile);

      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('not-today-resting')));
      await tester.pumpAndSettle();

      final record = suggestionController.history.single;
      expect(record.status, SuggestionStatus.skipped);
      // The same as "not now": the engine reads it as no verdict, so the idea can come back.
      expect(record.skipReason, SuggestionSkipReason.notNow);
      expect(record.done, isNull);
      expect(profile.restDays, hasLength(1));
      expect(find.text('Rest is part of it'), findsOneWidget);

      // A mis-tap can be taken back.
      await tester.tap(find.byKey(const ValueKey('undo-rest')));
      await tester.pumpAndSettle();
      expect(profile.restDays, isEmpty);
    });

    testWidgets('"too much right now" is recorded with its reason', (
      tester,
    ) async {
      await _pumpNotTodayPage(tester, suggestionController);

      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Too much right now'));
      await tester.pumpAndSettle();

      expect(
        suggestionController.history.single.skipReason,
        SuggestionSkipReason.tooHard,
      );
    });

    testWidgets('a refusal does not push another idea', (tester) async {
      await _pumpNotTodayPage(tester, suggestionController);

      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not right now'));
      await tester.pumpAndSettle();

      expect(
        suggestionController.history.single.skipReason,
        SuggestionSkipReason.notNow,
      );
      expect(find.text('Another idea'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('What you rated', () {
    late SuggestionController suggestionController;

    setUp(() {
      suggestionController = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: InMemorySuggestionRepository(),
      );
    });

    Future<void> pumpDetail(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: RhythmDetailPage(
            sessionController: SessionController(
              repository: InMemorySessionRepository(),
              emotionAnalyzer: const MockEmotionAnalyzer(),
            ),
            profileController: ProfileController(
              repository: InMemoryProfileRepository(),
            ),
            suggestionController: suggestionController,
            libraryRepository: _library,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('stays empty when the user has not rated anything', (
      tester,
    ) async {
      await suggestionController.load();
      await pumpDetail(tester);

      await tester.scrollUntilVisible(
        find.text('WHAT YOU RATED'),
        300,
      );
      expect(
        find.text('Nothing to show yet. Try a couple of things first.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the user their own ratings with the sample count', (
      tester,
    ) async {
      final repository = InMemorySuggestionRepository();
      await repository.saveRecord(_rated(rating: 4));
      await repository.saveRecord(_rated(rating: 5));
      await repository.saveRecord(_rated(rating: 3));

      suggestionController = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: repository,
      );
      await suggestionController.load();

      await pumpDetail(tester);
      await tester.scrollUntilVisible(find.text('WHAT YOU RATED'), 300);

      expect(
        find.textContaining('Three quiet breaths: you rated 4 of 5 as helpful'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Based on 3 tries. Your ratings only.'),
        findsOneWidget,
      );
    });

    testWidgets('hides thin data rather than implying a pattern', (
      tester,
    ) async {
      final repository = InMemorySuggestionRepository();
      await repository.saveRecord(_rated(rating: 5));
      await repository.saveRecord(_rated(rating: 5));

      suggestionController = SuggestionController(
        libraryRepository: _library,
        suggestionRepository: repository,
      );
      await suggestionController.load();

      await pumpDetail(tester);
      await tester.scrollUntilVisible(find.text('WHAT YOU RATED'), 300);

      expect(find.textContaining('you rated'), findsNothing);
    });
  });
}
