import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  testWidgets('saved text session appears in Journal and opens detail', (tester) async {
    final sessionController = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessionController.saveSession(
      mode: CaptureMode.text,
      text: 'A note from today.',
      mood: 'steady',
    );
    final onboardingRepository = InMemoryOnboardingRepository();
    await onboardingRepository.complete();

    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: onboardingRepository,
        sessionController: sessionController,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Journal'));
    await tester.pumpAndSettle();
    expect(find.text('A note from today.'), findsOneWidget);
    expect(find.text('TEXT CHECK-IN'), findsOneWidget);

    await tester.tap(find.text('A note from today.'));
    await tester.pumpAndSettle();
    expect(find.text('OVERALL FEEL'), findsOneWidget);
    expect(find.text('A note from today.'), findsOneWidget);
  });
}
