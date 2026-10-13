import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/profile/baseline_quiz_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

/// A finished baseline: preferences chosen, one questionnaire answered, two skipped.
Future<ProfileController> _finished() async {
  final controller = ProfileController(repository: InMemoryProfileRepository());
  await controller.load();
  await controller.savePreferences(
    preferredActivities: const ['Movement'],
    constraints: const ['Short moments'],
    interactionPreferences: const ['Gentle tone'],
    neverSuggest: const ['Exercise'],
  );
  for (var i = 1; i <= 6; i++) {
    await controller.saveAnswer(block: QuizBlock.erqS, questionId: 'erqS_$i', value: 3);
  }
  await controller.markBlockSkipped(QuizBlock.gad7);
  await controller.markBlockSkipped(QuizBlock.phq9);
  await controller.markBaselineComplete();
  return controller;
}

void main() {
  group('resetting the baseline', () {
    test('clears the answers, the skips and the completion date, and keeps what fits the person', () async {
      final controller = await _finished();
      expect(controller.profile.baselineComplete, isTrue);
      expect(controller.profile.baselineCompletedAt, isNotNull);

      await controller.resetBaseline();
      final p = controller.profile;
      expect(p.erqSAnswers, isEmpty);
      expect(p.skippedBlocks, isEmpty);
      expect(p.baselineCompletedAt, isNull);
      expect(p.baselineComplete, isFalse);
      expect(p.preferencesCompleted, isTrue); // kept
      expect(p.preferredActivities, ['Movement']);
    });

    test('can clear what fits the person as well, and touches nothing else', () async {
      final controller = await _finished();
      await controller.setCountry('BD');
      await controller.resetBaseline(includePreferences: true);
      final p = controller.profile;
      expect(p.preferencesCompleted, isFalse);
      expect(p.preferredActivities, isEmpty);
      expect(p.neverSuggest, isEmpty);
      expect(p.countryCode, 'BD'); // unrelated settings stay
    });
  });

  group('on the baseline page', () {
    Future<ProfileController> pump(WidgetTester tester) async {
      final controller = await _finished();
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final safety = SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: BaselineQuizPage(profileController: controller, safetyController: safety),
      ));
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('a finished baseline shows its scores as rings, with a way to redo it', (tester) async {
      await pump(tester);
      expect(find.text('A useful starting point'), findsOneWidget);
      expect(find.byKey(const ValueKey('baseline-scores')), findsOneWidget);
      expect(find.byKey(const ValueKey('baseline-redo-button')), findsOneWidget);
    });

    testWidgets('redoing asks first, then starts the questions again', (tester) async {
      final controller = await pump(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('baseline-redo-button')));
      await tester.tap(find.byKey(const ValueKey('baseline-redo-button')));
      await tester.pumpAndSettle();
      expect(find.text('Redo the quiz?'), findsOneWidget);

      // "Keep my answers" changes nothing
      await tester.tap(find.text('Keep my answers'));
      await tester.pumpAndSettle();
      expect(controller.profile.baselineComplete, isTrue);

      await tester.ensureVisible(find.byKey(const ValueKey('baseline-redo-button')));
      await tester.tap(find.byKey(const ValueKey('baseline-redo-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('baseline-reset-confirm')));
      await tester.pumpAndSettle();

      expect(controller.profile.baselineComplete, isFalse);
      expect(controller.profile.erqSAnswers, isEmpty);
      expect(find.text('A useful starting point'), findsNothing);
      expect(find.byKey(const ValueKey('baseline-section-1')), findsOneWidget); // back on the first question set
    });

    testWidgets('the finished view can go back to "what fits you" without losing answers', (tester) async {
      await pump(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('baseline-fits-button')));
      await tester.tap(find.byKey(const ValueKey('baseline-fits-button')));
      await tester.pumpAndSettle();
      expect(find.text('What fits you?'), findsOneWidget);
      expect(find.text('Movement'), findsOneWidget);
    });
  });
}
