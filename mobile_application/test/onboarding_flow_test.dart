import 'package:flutter/material.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
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
    expect(find.textContaining('Want a daily'), findsOneWidget);

    await tester.tap(find.text('Not now'));
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
  _voiceAndVideoPageTests();
  _reminderPageTests();
}

Future<ProfileController> _reachSleepPage(
  WidgetTester tester,
  InMemoryOnboardingRepository repository,
) async {
  final profileController = ProfileController(
    repository: InMemoryProfileRepository(),
  );
  await profileController.load();
  await repository.setCurrentPage(5);

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
    await repository.setCurrentPage(6);
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
    await repository.setCurrentPage(7);
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
    expect(find.textContaining('Want a daily'), findsOneWidget);
  });

  testWidgets('leaving the name blank, or skipping, keeps nothing and is fine', (tester) async {
    final profile = await reach(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(profile.profile.displayName, anyOf(isNull, isEmpty));
    expect(find.textContaining('Want a daily'), findsOneWidget);
  });
}

void _voiceAndVideoPageTests() {
  Future<(InMemoryOnboardingRepository, ConsentController)> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = InMemoryOnboardingRepository();
    await repository.setCurrentPage(2);
    final consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    await tester.pumpWidget(SolaceApp(
      onboardingRepository: repository,
      sessionController: _testSessionController(),
      consentController: consent,
    ));
    await tester.pumpAndSettle();
    return (repository, consent);
  }

  testWidgets('choosing voice and video leads to the reading choices, which are off until switched on', (tester) async {
    final (repository, consent) = await start(tester);
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();

    expect(find.textContaining('What may Solace'), findsOneWidget);
    expect(consent.isGranted(ConsentKey.emotionEstimate), isFalse);
    expect(consent.isGranted(ConsentKey.faceFeatures), isFalse);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('onboarding-consent-face')), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.faceFeatures), isFalse); // the face switch waits for the voice one

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('onboarding-consent-voice')), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.emotionEstimate), isTrue);
    expect(consent.isGranted(ConsentKey.faceFeatures), isFalse);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('onboarding-consent-voice')), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.emotionEstimate), isFalse); // a considered no, changeable any time
    expect(repository.usesMedia, isTrue);
  });

  testWidgets('then the offline models are offered, with the speech model first and the camera models only if the face is allowed', (tester) async {
    final (_, consent) = await start(tester);
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    Future<void> panelLoads() async {
      for (var i = 0; i < 20 && find.byKey(const ValueKey('models-panel')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // it looks at the phone's files
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    expect(find.textContaining('Journal anywhere'), findsOneWidget);
    await panelLoads();
    expect(find.text('Offline transcription'), findsOneWidget);
    expect(find.text('Read my face on this phone'), findsNothing);
    expect(find.textContaining('needs to be on right now'), findsOneWidget);

    await consent.grant(ConsentKey.emotionEstimate); // the face needs the voice reading's OK first
    await consent.grant(ConsentKey.faceFeatures);
    await tester.pump();
    await panelLoads();
    expect(find.text('Read my face on this phone'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('When do you usually'), findsOneWidget);
  });

  testWidgets('someone who chooses text never sees the voice and video pages', (tester) async {
    await start(tester);
    await tester.tap(find.text("I'll use text"));
    await tester.pumpAndSettle();
    expect(find.textContaining('When do you usually'), findsOneWidget);
  });
}

void _reminderPageTests() {
  Future<ProfileController> reach(WidgetTester tester, Future<bool> Function(int) schedule) async {
    final repository = InMemoryOnboardingRepository();
    final profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
    await repository.setCurrentPage(8);
    await tester.pumpWidget(SolaceApp(
      onboardingRepository: repository,
      sessionController: _testSessionController(),
      profileController: profile,
      scheduleReminder: schedule,
    ));
    await tester.pumpAndSettle();
    return profile;
  }

  testWidgets('a reminder is only claimed once it was really scheduled', (tester) async {
    int? scheduledAt;
    final profile = await reach(tester, (minutes) async {
      scheduledAt = minutes;
      return true;
    });
    await tester.tap(find.text('Set a reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(scheduledAt, isNotNull);
    expect(profile.profile.reminderEnabled, isTrue);
    expect(profile.profile.reminderMinutes, scheduledAt);
    expect(find.text('Support is always nearby.'), findsOneWidget);
  });

  testWidgets('when notifications are off, no reminder is claimed, and the person is told', (tester) async {
    final profile = await reach(tester, (_) async => false);
    await tester.tap(find.text('Set a reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(profile.profile.reminderEnabled, isFalse);
    expect(find.textContaining('No reminder was set'), findsOneWidget);
  });

  testWidgets('"Not now" sets nothing', (tester) async {
    var asked = false;
    final profile = await reach(tester, (_) async {
      asked = true;
      return true;
    });
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(asked, isFalse);
    expect(profile.profile.reminderEnabled, isFalse);
    expect(find.text('Support is always nearby.'), findsOneWidget);
  });
}
