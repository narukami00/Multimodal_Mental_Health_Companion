import 'package:flutter/material.dart';
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
import 'features/onboarding/onboarding_gate.dart';
import 'features/profile/profile_controller.dart';
import 'features/safety/safety_controller.dart';
import 'features/sessions/session_controller.dart';
import 'features/suggestions/suggestion_controller.dart';
import 'providers/mock/mock_providers.dart';
import 'providers/safety/keyword_safety_screener.dart';
import 'services/check_in_reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final sessionController = SessionController(
    repository: SharedPreferencesSessionRepository(preferences),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
  await sessionController.load();
  if (sessionController.sessions.isEmpty) {
    await sessionController.seedInitialSessions();
  }
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
    await CheckInReminderService.instance.scheduleDaily(
      minutesPastMidnight: profileController.profile.reminderMinutes,
    );
  }
  final suggestionController = SuggestionController(
    libraryRepository: AssetActivityLibraryRepository(),
    suggestionRepository: SharedPreferencesSuggestionRepository(preferences),
  );
  await suggestionController.load();

  runApp(
    SolaceApp(
      onboardingRepository: SharedPreferencesOnboardingRepository(preferences),
      sessionController: sessionController,
      safetyController: safetyController,
      profileController: profileController,
      suggestionController: suggestionController,
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
