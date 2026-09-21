import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'data/contracts/onboarding_repository.dart';
import 'data/repositories/shared_preferences_onboarding_repository.dart';
import 'data/repositories/shared_preferences_session_repository.dart';
import 'features/onboarding/onboarding_gate.dart';
import 'features/sessions/session_controller.dart';
import 'providers/mock/mock_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final sessionController = SessionController(
    repository: SharedPreferencesSessionRepository(preferences),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
  await sessionController.load();

  runApp(
    SolaceApp(
      onboardingRepository: SharedPreferencesOnboardingRepository(preferences),
      sessionController: sessionController,
    ),
  );
}

class SolaceApp extends StatelessWidget {
  const SolaceApp({
    required this.onboardingRepository,
    required this.sessionController,
    super.key,
  });

  final OnboardingRepository onboardingRepository;
  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: OnboardingGate(
        repository: onboardingRepository,
        sessionController: sessionController,
      ),
    );
  }
}

// Kept as an alias while early integrations migrate to the product name.
typedef MainApp = SolaceApp;
