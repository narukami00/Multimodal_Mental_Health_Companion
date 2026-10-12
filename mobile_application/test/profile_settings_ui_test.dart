import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/profile/profile_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  late InMemorySessionRepository sessionRepository;
  late SessionController sessionController;
  late ProfileController profileController;

  setUp(() {
    sessionRepository = InMemorySessionRepository();
    sessionController = SessionController(
      repository: sessionRepository,
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
  });

  Widget harness() {
    return MaterialApp(
      theme: AppTheme.light(),
      home: ProfilePage(
        profileController: profileController,
        safetyController: SafetyController(
          screener: const KeywordSafetyScreener(),
          repository: InMemorySafetyEventRepository(),
        ),
        suggestionController: SuggestionController(
          libraryRepository: AssetActivityLibraryRepository(),
          suggestionRepository: InMemorySuggestionRepository(),
        ),
        sessionController: sessionController,
      ),
    );
  }

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  testWidgets('shows the saved display name and member-since date', (
    tester,
  ) async {
    await profileController.load();
    await profileController.saveIdentity(displayName: 'Rafsan');
    await profileController.ensureFirstRun();

    await pumpProfile(tester);

    expect(find.text('Rafsan'), findsOneWidget);
    expect(find.textContaining('Member since'), findsOneWidget);
  });

  testWidgets('prompts for a name when none is set', (tester) async {
    await profileController.load();

    await pumpProfile(tester);

    expect(find.text('Add your name'), findsOneWidget);
    expect(find.text('Welcome to Solace'), findsOneWidget);
  });

  testWidgets('the settings sheet never overflows a real phone screen and the country is reachable', (
    tester,
  ) async {
    await profileController.load();
    tester.view.physicalSize = const Size(1080, 2400); // a Galaxy S21: 411 x 914 logical
    tester.view.devicePixelRatio = 2.625;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('country-ZZ')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('country-ZZ')));
    await tester.pumpAndSettle();
    expect(profileController.profile.countryCode, 'ZZ');
    expect(tester.takeException(), isNull); // no "bottom overflowed" error
  });

  testWidgets('app settings sheet exposes real palette choices', (
    tester,
  ) async {
    await profileController.load();

    await pumpProfile(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Gentle Haptics'), findsOneWidget);
    expect(find.text('Soft Ambient Breath Audio'), findsOneWidget);
    expect(find.text('Warm Cream'), findsOneWidget);
    expect(find.text('Soft Twilight'), findsOneWidget);

    // The reminder is a real control with a scheduled time, not a placeholder.
    expect(find.text('Daily check-in reminder'), findsOneWidget);
    expect(find.text('8:30 PM'), findsOneWidget);
  });

  testWidgets('reminder fails closed when notifications are unavailable', (
    tester,
  ) async {
    await profileController.load();

    await pumpProfile(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();

    expect(profileController.profile.reminderEnabled, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('setting-reminder')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    // Never claim a reminder that cannot actually be delivered.
    expect(profileController.profile.reminderEnabled, isFalse);
  });

  testWidgets('selecting a palette persists it', (tester) async {
    await profileController.load();

    await pumpProfile(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-softTwilight')));
    await tester.pumpAndSettle();

    expect(profileController.profile.paletteId, 'softTwilight');
  });

  testWidgets('toggling haptics off persists the preference', (tester) async {
    await profileController.load();

    await pumpProfile(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();

    expect(profileController.profile.hapticsEnabled, isTrue);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('toggle-haptics')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(profileController.profile.hapticsEnabled, isFalse);
  });

  testWidgets('settings sheet reflects changes without being reopened', (
    tester,
  ) async {
    await profileController.load();

    await pumpProfile(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();

    Switch hapticsSwitch() => tester.widget<Switch>(
          find.descendant(
            of: find.byKey(const ValueKey('toggle-haptics')),
            matching: find.byType(Switch),
          ),
        );

    expect(hapticsSwitch().value, isTrue);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('toggle-haptics')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    // The sheet is still open and already shows the new state.
    expect(find.text('Daily check-in reminder'), findsOneWidget);
    expect(hapticsSwitch().value, isFalse);
  });

  testWidgets('quiet hours appear only once idea nudges are on', (tester) async {
    await profileController.load();

    await pumpProfile(tester);
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('toggle-idea-push')), findsOneWidget);
    expect(find.byKey(const ValueKey('toggle-quiet-hours')), findsNothing);

    await profileController.setIdeaPushEnabled(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('toggle-quiet-hours')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiet-start')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('toggle-quiet-hours')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('toggle-quiet-hours')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(profileController.profile.quietHoursEnabled, isTrue);
    expect(find.byKey(const ValueKey('quiet-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiet-end')), findsOneWidget);
  });
}
