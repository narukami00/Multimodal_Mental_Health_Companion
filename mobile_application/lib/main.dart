import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/solace_palette.dart';
import 'data/contracts/onboarding_repository.dart';
import 'data/repositories/asset_activity_library_repository.dart';
import 'data/repositories/in_memory_profile_repository.dart';
import 'data/repositories/in_memory_safety_event_repository.dart';
import 'data/repositories/in_memory_suggestion_repository.dart';
import 'data/repositories/shared_preferences_onboarding_repository.dart';
import 'data/repositories/shared_preferences_profile_repository.dart';
import 'data/repositories/shared_preferences_safety_event_repository.dart';
import 'data/repositories/shared_preferences_session_repository.dart';
import 'data/repositories/shared_preferences_suggestion_repository.dart';
import 'domain/rhythm/reminder_lapse_policy.dart';
import 'features/checkin/check_in_mode_page.dart';
import 'features/onboarding/onboarding_gate.dart';
import 'features/profile/profile_controller.dart';
import 'features/safety/safety_controller.dart';
import 'features/sessions/session_controller.dart';
import 'features/suggestions/suggestion_controller.dart';
import 'providers/mock/mock_providers.dart';
import 'providers/safety/keyword_safety_screener.dart';
import 'services/check_in_reminder_service.dart';
import 'services/check_in_widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final sessionController = SessionController(
    repository: SharedPreferencesSessionRepository(preferences),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
  await sessionController.load();
  final safetyController = SafetyController(
    screener: const KeywordSafetyScreener(),
    repository: SharedPreferencesSafetyEventRepository(preferences),
  );
  await safetyController.load();
  final profileController = ProfileController(
    repository: SharedPreferencesProfileRepository(preferences),
  );
  await profileController.load();
  await profileController.ensureFirstRun();

  // Restore the daily reminder in case the OS dropped it (for example after a
  // reboot or an app update). If the user has been away a long time, stop
  // nudging them instead: the reminder only ever gets quieter, never louder.
  await CheckInReminderService.instance.initialize();
  final daysSinceLastCheckIn = ReminderLapsePolicy.daysSince(
    sessionController.lastCheckInAt,
  );
  if (ReminderLapsePolicy.shouldPauseReminder(daysSinceLastCheckIn)) {
    if (profileController.profile.reminderEnabled) {
      await profileController.setReminderEnabled(false);
    }
    await CheckInReminderService.instance.cancel();
  } else if (profileController.profile.reminderEnabled) {
    final result = await CheckInReminderService.instance.scheduleDaily(
      minutesPastMidnight: profileController.profile.reminderMinutes,
    );
    if (!result.isScheduled) {
      // Keep the stored preference honest rather than claiming a reminder that
      // is not actually registered with Android.
      await profileController.setReminderEnabled(false);
    }
  }
  final suggestionController = SuggestionController(
    libraryRepository: AssetActivityLibraryRepository(),
    suggestionRepository: SharedPreferencesSuggestionRepository(preferences),
  );
  await suggestionController.load();
  // Loaded at startup so Home can ask whether a suggestion is due without
  // waiting on an asset read during a rebuild.
  await suggestionController.warmUp();

  final navigatorKey = GlobalKey<NavigatorState>();

  void openCheckInFromWidget(Uri? uri) {
    if (uri == null || uri.host != 'checkin') return;
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => CheckInModePage(
          sessionController: sessionController,
          safetyController: safetyController,
          profileController: profileController,
        ),
      ),
    );
  }

  // Keep the home-screen widget in step, but only when the line it shows
  // actually changes, so unrelated settings edits do not redraw it.
  String? lastWidgetPrompt;

  Future<void> refreshCheckInWidget() async {
    final prompt = CheckInWidgetService.promptFor(
      checkedInToday: CheckInWidgetService.checkedInToday(
        sessionController.sessions,
      ),
      restingToday: CheckInWidgetService.restingToday(
        profileController.restDays,
      ),
    );
    if (prompt == lastWidgetPrompt) return;
    lastWidgetPrompt = prompt;
    await CheckInWidgetService.instance.push(prompt);
  }

  sessionController.addListener(refreshCheckInWidget);
  profileController.addListener(refreshCheckInWidget);
  await refreshCheckInWidget();

  // Tapping the widget opens the check-in flow, whether the app was cold
  // started by the tap or is already running.
  HomeWidget.widgetClicked.listen(openCheckInFromWidget);
  final launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
  if (launchUri != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => openCheckInFromWidget(launchUri),
    );
  }

  runApp(
    SolaceApp(
      onboardingRepository: SharedPreferencesOnboardingRepository(preferences),
      sessionController: sessionController,
      safetyController: safetyController,
      profileController: profileController,
      suggestionController: suggestionController,
      navigatorKey: navigatorKey,
    ),
  );
}

class SolaceApp extends StatelessWidget {
  SolaceApp({
    required this.onboardingRepository,
    required this.sessionController,
    SafetyController? safetyController,
    ProfileController? profileController,
    SuggestionController? suggestionController,
    this.navigatorKey,
    super.key,
  }) : safetyController =
           safetyController ??
           SafetyController(
             screener: const KeywordSafetyScreener(),
             repository: InMemorySafetyEventRepository(),
           ),
       profileController =
           profileController ??
           ProfileController(repository: InMemoryProfileRepository()),
       suggestionController = suggestionController ??
           SuggestionController(
             libraryRepository: AssetActivityLibraryRepository(),
             suggestionRepository: InMemorySuggestionRepository(),
           );

  final OnboardingRepository onboardingRepository;
  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;
  final SuggestionController suggestionController;

  /// Lets the home-screen widget push the check-in flow from outside the tree.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    // Rebuild the theme whenever the user switches palette.
    return AnimatedBuilder(
      animation: profileController,
      builder: (context, _) {
        final palette = SolaceColors.of(
          SolacePaletteId.fromId(profileController.profile.paletteId),
        );
        return MaterialApp(
          title: 'Solace',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(palette: palette),
          home: OnboardingGate(
            repository: onboardingRepository,
            sessionController: sessionController,
            safetyController: safetyController,
            profileController: profileController,
            suggestionController: suggestionController,
          ),
        );
      },
    );
  }
}

// Kept as an alias while early integrations migrate to the product name.
typedef MainApp = SolaceApp;
