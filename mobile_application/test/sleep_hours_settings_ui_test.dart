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
  late ProfileController profileController;

  setUp(() {
    profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
  });

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
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
          sessionController: SessionController(
            repository: InMemorySessionRepository(),
            emotionAnalyzer: const MockEmotionAnalyzer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
  }

  /// Confirms the picker at whatever time it opened on.
  Future<void> confirmPicker(WidgetTester tester) async {
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('offers to set sleep hours without having guessed any', (
    tester,
  ) async {
    await profileController.load();
    await openSettings(tester);

    expect(find.text('Usual sleep hours'), findsOneWidget);
    expect(find.byKey(const ValueKey('sleep-set')), findsOneWidget);
    expect(find.byKey(const ValueKey('toggle-weekends-differ')), findsNothing);
    expect(profileController.profile.sleepHoursSet, isFalse);
  });

  testWidgets('choosing hours saves both ends only after both are confirmed', (
    tester,
  ) async {
    await profileController.load();
    await openSettings(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('sleep-set')));
    await tester.tap(find.byKey(const ValueKey('sleep-set')));
    await tester.pumpAndSettle();
    await confirmPicker(tester); // bedtime
    // Nothing is saved while the second picker is still open.
    expect(profileController.profile.sleepHoursSet, isFalse);
    await confirmPicker(tester); // wake time

    expect(profileController.profile.sleepStartMinutes, 23 * 60);
    expect(profileController.profile.sleepEndMinutes, 7 * 60);
    expect(find.text('11:00 PM to 7:00 AM'), findsOneWidget);
  });

  testWidgets('cancelling the second picker saves nothing', (tester) async {
    await profileController.load();
    await openSettings(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('sleep-set')));
    await tester.tap(find.byKey(const ValueKey('sleep-set')));
    await tester.pumpAndSettle();
    await confirmPicker(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(profileController.profile.sleepHoursSet, isFalse);
    expect(profileController.profile.sleepStartMinutes, isNull);
  });

  testWidgets('weekends differ only shows its hours once they are chosen', (
    tester,
  ) async {
    await profileController.load();
    await profileController.setSleepHours(
      startMinutes: 23 * 60,
      endMinutes: 7 * 60,
    );
    await openSettings(tester);

    final toggle = find.byKey(const ValueKey('toggle-weekends-differ'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    // Turning it on asks for the weekend hours straight away.
    await confirmPicker(tester);
    await confirmPicker(tester);

    expect(profileController.profile.weekendSleepDiffers, isTrue);
    expect(profileController.profile.weekendSleepStartMinutes, 23 * 60);
    expect(find.text('Weekends: 11:00 PM to 7:00 AM'), findsOneWidget);
  });

  testWidgets('dismissing the weekend picker leaves the switch off', (
    tester,
  ) async {
    await profileController.load();
    await profileController.setSleepHours(
      startMinutes: 23 * 60,
      endMinutes: 7 * 60,
    );
    await openSettings(tester);

    final toggle = find.byKey(const ValueKey('toggle-weekends-differ'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No switch left on with nothing behind it.
    expect(profileController.profile.weekendSleepDiffers, isFalse);
  });

  testWidgets('sleep hours can be copied to quiet hours, then the offer goes', (
    tester,
  ) async {
    await profileController.load();
    await profileController.setSleepHours(
      startMinutes: 23 * 60,
      endMinutes: 7 * 60,
    );
    await openSettings(tester);

    final offer = find.byKey(const ValueKey('sleep-use-as-quiet'));
    await tester.ensureVisible(offer);
    await tester.tap(offer);
    await tester.pumpAndSettle();

    expect(profileController.profile.quietHoursEnabled, isTrue);
    expect(profileController.profile.quietStartMinutes, 23 * 60);
    expect(find.byKey(const ValueKey('sleep-use-as-quiet')), findsNothing);
  });

  testWidgets('a skipped answer is acknowledged and can be undone', (
    tester,
  ) async {
    await profileController.load();
    await profileController.skipSleepHours();
    await openSettings(tester);

    expect(find.text('Skipped earlier. Set sleep hours'), findsOneWidget);
  });
}
