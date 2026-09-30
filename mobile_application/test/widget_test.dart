import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/app_shell/nav_pill.dart';
import 'package:solace_mobile/features/app_shell/today_page.dart';
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

    expect(find.text(TodayPage.greetingForHour(DateTime.now().hour)), findsOneWidget);
    // The floating pill shows only the selected tab's label; the rest are
    // icon-only, with their names carried by semantics.
    expect(find.byType(SolaceNavPill), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.bySemanticsLabel('Journal'), findsOneWidget);
    expect(find.bySemanticsLabel('Insights'), findsOneWidget);
    expect(find.bySemanticsLabel('You'), findsOneWidget);
  });

  testWidgets('tapping a destination moves the label with it', (tester) async {
    final repository = InMemoryOnboardingRepository();
    await repository.complete();

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: repository,
        sessionController: _testSessionController(),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Journal'));
    await tester.pumpAndSettle();

    // The active tab is the one that carries a visible label, so Today's label
    // is gone and Journal's has appeared. Journal also titles its own page, so
    // it matches more than once.
    expect(find.text('Today'), findsNothing);
    expect(find.text('Journal'), findsWidgets);
  });
}

SessionController _testSessionController() {
  return SessionController(
    repository: InMemorySessionRepository(),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
}
