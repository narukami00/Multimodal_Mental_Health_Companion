import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'data/contracts/onboarding_repository.dart';
import 'data/repositories/shared_preferences_onboarding_repository.dart';
import 'data/repositories/in_memory_safety_event_repository.dart';
import 'data/repositories/shared_preferences_safety_event_repository.dart';
import 'data/repositories/shared_preferences_session_repository.dart';
import 'features/onboarding/onboarding_gate.dart';
import 'features/safety/safety_controller.dart';
import 'features/sessions/session_controller.dart';
import 'providers/mock/mock_providers.dart';
import 'providers/safety/keyword_safety_screener.dart';

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

  runApp(
    SolaceApp(
      onboardingRepository: SharedPreferencesOnboardingRepository(preferences),
      sessionController: sessionController,
      safetyController: safetyController,
    ),
  );
}

class SolaceApp extends StatelessWidget {
  SolaceApp({
    required this.onboardingRepository,
    required this.sessionController,
    SafetyController? safetyController,
    super.key,
  }) : safetyController = safetyController ??
            SafetyController(
              screener: const KeywordSafetyScreener(),
              repository: InMemorySafetyEventRepository(),
            );

  final OnboardingRepository onboardingRepository;
  final SessionController sessionController;
  final SafetyController safetyController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: OnboardingGate(
        repository: onboardingRepository,
        sessionController: sessionController,
        safetyController: safetyController,
      ),
    );
  }
}

// Kept as an alias while early integrations migrate to the product name.
typedef MainApp = SolaceApp;
