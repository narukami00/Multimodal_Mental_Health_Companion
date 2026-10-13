import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/safety_assessment.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/profile/quiz_questions.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  test('scores stay unavailable until an atomic block is complete', () {
    var profile = const UserProfile(gad7Answers: {'gad7_1': 2});

    expect(profile.gad7Complete, isFalse);
    expect(scoreFor(profile, QuizBlock.gad7), isNull);
    expect(profile.baselineCompletedAt, isNull);

    profile = profile.copyWith(
      gad7Answers: {
        for (var index = 1; index <= 7; index++) 'gad7_$index': index % 4,
      },
    );

    expect(profile.gad7Complete, isTrue);
    expect(scoreFor(profile, QuizBlock.gad7), 12);

    const skipped = UserProfile(
      preferencesCompleted: true,
      skippedBlocks: ['erqS', 'gad7', 'phq9'],
    );
    expect(skipped.baselineComplete, isTrue);
  });

  testWidgets('nonzero PHQ-9 item 9 opens support before completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
    final safetyController = SafetyController(
      screener: const KeywordSafetyScreener(),
      repository: InMemorySafetyEventRepository(),
    );
    final onboardingRepository = InMemoryOnboardingRepository();
    await onboardingRepository.complete();

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: onboardingRepository,
        sessionController: SessionController(
          repository: InMemorySessionRepository(),
          emotionAnalyzer: const MockEmotionAnalyzer(),
        ),
        safetyController: safetyController,
        profileController: profileController,
      ),
    );

    await tester.tap(find.bySemanticsLabel('You'));
    await tester.pumpAndSettle();
    final continueBaseline = find.text('Continue baseline');
    await tester.scrollUntilVisible(continueBaseline, 300);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(continueBaseline);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Movement'));
    await tester.pump();
    final continueButton = find.text('Continue to questions');
    await tester.scrollUntilVisible(continueButton, 300);
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    for (var index = 0; index < 6; index++) {
      await _tapAndSettle(tester, 'Strongly disagree');
    }
    for (var index = 0; index < 7; index++) {
      await _tapAndSettle(tester, 'Not at all');
    }
    for (var index = 0; index < 8; index++) {
      await _tapAndSettle(tester, 'Not at all');
    }

    await _tapAndSettle(tester, 'Several days');

    // Urgent flags lead with the national emergency number.
    expect(find.textContaining('Call 999'), findsOneWidget);
    expect(safetyController.latestEvent?.source, 'phq9_item_9');
    expect(safetyController.latestEvent?.level, SafetyLevel.urgentSupport);
    expect(profileController.profile.baselineCompletedAt, isNull);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('A useful starting point'), findsOneWidget);
    expect(profileController.profile.baselineComplete, isTrue);
    expect(profileController.profile.baselineCompletedAt, isNotNull);
  });
}

Future<void> _tapAndSettle(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
