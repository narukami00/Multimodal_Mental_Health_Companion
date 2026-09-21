import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  testWidgets('Today opens a text check-in and saves its detail', (tester) async {
    final sessionController = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    final onboardingRepository = InMemoryOnboardingRepository();
    await onboardingRepository.complete();

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: onboardingRepository,
        sessionController: sessionController,
      ),
    );

    await tester.tap(find.text('Start a check-in'));
    await tester.pumpAndSettle();
    expect(find.text('How would you like to check in?'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(find.text('What feels present right now?'), findsOneWidget);

    await tester.tap(find.text('Steady'));
    await tester.enterText(find.byType(TextField), 'A little more settled than yesterday.');
    await tester.tap(find.text('Keep this moment'));
    await tester.pumpAndSettle();

    expect(find.text('HOW THIS SESSION FELT'), findsOneWidget);
    expect(find.text('A little more settled than yesterday.'), findsOneWidget);
    expect(sessionController.sessions, hasLength(1));
  });
}
