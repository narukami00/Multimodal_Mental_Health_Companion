import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
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

    await tester.tap(find.text('Check in now'));
    await tester.pumpAndSettle();
    expect(find.text('How would you like to check in?'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(find.text('What feels present right now?'), findsOneWidget);

    expect(find.text('A quick word for it'), findsNothing); // the mood is read from the entry, not picked
    await tester.enterText(find.byType(TextField), 'A little more settled than yesterday.');
    await tester.pump();
    await tester.tap(find.text('Keep this moment'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('no-reading')), findsOneWidget); // the mock analyzer gives no real reading
    expect(find.text('A little more settled than yesterday.'), findsOneWidget);
    expect(sessionController.sessions, hasLength(1));
  });

  testWidgets('Rest today records rest without saving a session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessionController = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    final profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
    final onboardingRepository = InMemoryOnboardingRepository();
    await onboardingRepository.complete();

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: onboardingRepository,
        sessionController: sessionController,
        profileController: profileController,
      ),
    );

    await tester.tap(find.text('Check in now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();

    final restButton = find.byKey(const ValueKey('rest-today-checkin'));
    await tester.ensureVisible(restButton);
    await tester.pumpAndSettle();
    await tester.tap(restButton);
    await tester.pumpAndSettle();

    // Rest is its own mark: nothing is written as a reflection.
    expect(profileController.restDays, hasLength(1));
    expect(sessionController.sessions, isEmpty);
  });
}
