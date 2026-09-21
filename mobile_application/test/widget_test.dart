import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  testWidgets('fresh users enter trust-first onboarding', (tester) async {
    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: InMemoryOnboardingRepository(),
        sessionController: _testSessionController(),
      ),
    );

    expect(find.textContaining('A calm space to'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('completed onboarding opens the four-tab shell', (tester) async {
    final repository = InMemoryOnboardingRepository();
    await repository.complete();

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: repository,
        sessionController: _testSessionController(),
      ),
    );

    expect(find.text('Good to see you'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });
}

SessionController _testSessionController() {
  return SessionController(
    repository: InMemorySessionRepository(),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
}
