import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/core/models/safety_assessment.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  testWidgets('urgent text interrupts before a session is saved', (tester) async {
    final sessionController = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
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
        sessionController: sessionController,
        safetyController: safetyController,
      ),
    );

    await tester.tap(find.text('Check in now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    const urgentText = 'I want to die and need help.';
    await tester.enterText(find.byType(TextField), urgentText);
    await tester.pump();
    expect(
      const KeywordSafetyScreener().assess(urgentText).level,
      SafetyLevel.urgentSupport,
    );
    await tester.tap(find.byKey(const ValueKey('text-check-in-save')));
    await tester.pumpAndSettle();

    // Urgent flags lead with the national emergency number.
    expect(find.textContaining('Call 999'), findsOneWidget);
    expect(sessionController.sessions, isEmpty);
    expect(safetyController.hasActiveFlag, isTrue);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('What feels present right now?'), findsOneWidget);
  });

  testWidgets('active safety state elevates the Today card', (tester) async {
    final safetyController = SafetyController(
      screener: const KeywordSafetyScreener(),
      repository: InMemorySafetyEventRepository(),
    );
    await safetyController.assessText(
      source: 'test',
      text: 'I feel completely overwhelmed.',
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
      ),
    );

    expect(find.textContaining('Support is'), findsOneWidget);
    expect(find.text('View support'), findsOneWidget);
  });
}
