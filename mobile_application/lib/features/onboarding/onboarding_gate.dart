import 'package:flutter/material.dart';

import '../../data/contracts/onboarding_repository.dart';
import '../app_shell/app_shell.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../sessions/session_controller.dart';
import 'onboarding_flow.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    required this.repository,
    required this.sessionController,
    required this.safetyController,
    required this.profileController,
    super.key,
  });

  final OnboardingRepository repository;
  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late bool _isComplete;

  @override
  void initState() {
    super.initState();
    _isComplete = widget.repository.isComplete;
  }

  @override
  Widget build(BuildContext context) {
    if (_isComplete) {
      return AppShell(
        sessionController: widget.sessionController,
        safetyController: widget.safetyController,
        profileController: widget.profileController,
      );
    }

    return OnboardingFlow(
      repository: widget.repository,
      onComplete: () => setState(() => _isComplete = true),
    );
  }
}
