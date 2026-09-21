import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  testWidgets('text-only onboarding completes without media access', (tester) async {
    final repository = InMemoryOnboardingRepository();

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: repository,
        sessionController: _testSessionController(),
      ),
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Check in your way.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera & mic are'), findsOneWidget);

    await tester.tap(find.text("I'll use text"));
    await tester.pumpAndSettle();
    expect(find.text('Support is always nearby.'), findsOneWidget);
    expect(repository.usesMedia, isFalse);

    await tester.tap(find.text('Start checking in'));
    await tester.pumpAndSettle();

    expect(repository.isComplete, isTrue);
    expect(find.text('Good to see you'), findsOneWidget);
  });

  testWidgets('onboarding resumes from its saved page', (tester) async {
    final repository = InMemoryOnboardingRepository();
    await repository.setCurrentPage(2);

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: repository,
        sessionController: _testSessionController(),
      ),
    );

    expect(find.textContaining('Camera & mic are'), findsOneWidget);
    expect(find.text('Allow access'), findsOneWidget);
    expect(find.text("I'll use text"), findsOneWidget);
  });
}

SessionController _testSessionController() {
  return SessionController(
    repository: InMemorySessionRepository(),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
}
