import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/main.dart';

void main() {
  testWidgets('text-only onboarding completes without media access', (tester) async {
    final repository = InMemoryOnboardingRepository();

    await tester.pumpWidget(
      SolaceApp(onboardingRepository: repository),
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
}
