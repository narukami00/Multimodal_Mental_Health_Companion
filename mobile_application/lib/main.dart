import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'data/contracts/onboarding_repository.dart';
import 'data/repositories/shared_preferences_onboarding_repository.dart';
import 'features/onboarding/onboarding_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    SolaceApp(
      onboardingRepository: SharedPreferencesOnboardingRepository(preferences),
    ),
  );
}

class SolaceApp extends StatelessWidget {
  const SolaceApp({
    required this.onboardingRepository,
    super.key,
  });

  final OnboardingRepository onboardingRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: OnboardingGate(repository: onboardingRepository),
    );
  }
}

// Kept as an alias while early integrations migrate to the product name.
typedef MainApp = SolaceApp;
