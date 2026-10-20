import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/app_shell/today_page.dart';
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
    expect(find.textContaining('When do you usually'), findsOneWidget);
    expect(repository.usesMedia, isFalse);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Where are you'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('What should I'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Support is always nearby.'), findsOneWidget);

    await tester.tap(find.text('Start checking in'));
    await tester.pumpAndSettle();

    expect(repository.isComplete, isTrue);
    expect(find.text(TodayPage.greetingForHour(DateTime.now().hour)), findsOneWidget);
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

  _sleepPageTests();
  _countryPageTests();
  _namePageTests();
}

Future<ProfileController> _reachSleepPage(
  WidgetTester tester,
  InMemoryOnboardingRepository repository,
) async {
  final profileController = ProfileController(
    repository: InMemoryProfileRepository(),
  );
  await profileController.load();
  await repository.setCurrentPage(3);

  await tester.pumpWidget(
    SolaceApp(
      onboardingRepository: repository,
      sessionController: _testSessionController(),
      profileController: profileController,
    ),
  );
  await tester.pumpAndSettle();
  return profileController;
}

void _sleepPageTests() {
  testWidgets('sleep question can be skipped and counts as an answer', (
    tester,
  ) async {
    final repository = InMemoryOnboardingRepository();
    final profile = await _reachSleepPage(tester, repository);

    expect(find.textContaining('When do you usually'), findsOneWidget);
    expect(profile.profile.sleepHoursAnswered, isFalse);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(profile.profile.sleepHoursSkipped, isTrue);
    expect(profile.profile.sleepHoursSet, isFalse);
    expect(find.textContaining('Where are you'), findsOneWidget);
  });

  testWidgets('the top Skip on the sleep page is the same honest skip', (
    tester,
  ) async {
    final repository = InMemoryOnboardingRepository();
    final profile = await _reachSleepPage(tester, repository);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(profile.profile.sleepHoursSkipped, isTrue);
    expect(find.textContaining('Where are you'), findsOneWidget);
  });

  testWidgets('choosing hours saves them and moves on', (tester) async {
    final repository = InMemoryOnboardingRepository();
    final profile = await _reachSleepPage(tester, repository);

    await tester.tap(find.text('Set my sleep hours'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // bedtime
    await tester.pumpAndSettle();
    expect(profile.profile.sleepHoursSet, isFalse);
    await tester.tap(find.text('OK')); // wake time
    await tester.pumpAndSettle();

    expect(profile.profile.sleepStartMinutes, 23 * 60);
    expect(profile.profile.sleepEndMinutes, 7 * 60);
    expect(profile.profile.sleepHoursSkipped, isFalse);
    expect(find.textContaining('Where are you'), findsOneWidget);
  });

  testWidgets('dismissing a picker saves nothing and stays on the page', (
    tester,
  ) async {
    final repository = InMemoryOnboardingRepository();
    final profile = await _reachSleepPage(tester, repository);

    await tester.tap(find.text('Set my sleep hours'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(profile.profile.sleepHoursAnswered, isFalse);
    expect(find.textContaining('When do you usually'), findsOneWidget);
  });
}

SessionController _testSessionController() {
  return SessionController(
    repository: InMemorySessionRepository(),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
}


void _countryPageTests() {
  testWidgets('the country page defaults to Bangladesh and saves a change', (
    tester,
  ) async {
    final repository = InMemoryOnboardingRepository();
    final profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
    await repository.setCurrentPage(4);
    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: repository,
        sessionController: _testSessionController(),
        profileController: profile,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Where are you'), findsOneWidget);
    expect(profile.profile.countryCode, 'BD');
    expect(find.text('Emergency number 999'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('country-ZZ')));
    await tester.tap(find.byKey(const ValueKey('country-ZZ')));
    await tester.pumpAndSettle();
    expect(profile.profile.countryCode, 'ZZ');

    await tester.ensureVisible(find.byKey(const ValueKey('country-BD')));
    await tester.tap(find.byKey(const ValueKey('country-BD')));
    await tester.pumpAndSettle();
    expect(profile.profile.countryCode, 'BD');
  });
}

void _namePageTests() {
  Future<ProfileController> reach(WidgetTester tester) async {
    final repository = InMemoryOnboardingRepository();
    final profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
    await repository.setCurrentPage(5);
    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: repository,
        sessionController: _testSessionController(),
        profileController: profile,
      ),
    );
    await tester.pumpAndSettle();
    return profile;
  }

  testWidgets('a name typed here is kept, and moves on to the safety page', (tester) async {
    final profile = await reach(tester);
    expect(find.textContaining('What should I'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('onboarding-name')), '  Rafsan ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(profile.profile.displayName, 'Rafsan');
    expect(find.text('Support is always nearby.'), findsOneWidget);
  });

  testWidgets('leaving the name blank, or skipping, keeps nothing and is fine', (tester) async {
    final profile = await reach(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(profile.profile.displayName, anyOf(isNull, isEmpty));
    expect(find.text('Support is always nearby.'), findsOneWidget);
  });
}
