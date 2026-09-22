import 'package:flutter/material.dart';

import '../../data/contracts/onboarding_repository.dart';
import '../app_shell/app_shell.dart';
import '../call/call_page.dart';
import '../checkin/check_in_mode_page.dart';
import '../chat/chat_page.dart';
import '../checkin/text_check_in_page.dart';
import '../journal/session_detail_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'onboarding_flow.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    required this.repository,
    required this.sessionController,
    required this.safetyController,
    required this.profileController,
    required this.suggestionController,
    super.key,
  });

  final OnboardingRepository repository;
  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;
  final SuggestionController suggestionController;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late bool _isComplete;

  @override
  void initState() {
    super.initState();
    _isComplete = widget.repository.isComplete || _shouldSkipOnboarding();
  }

  bool _shouldSkipOnboarding() {
    try {
      return Uri.base.queryParameters['skip_onboarding'] == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final route = Uri.base.queryParameters['route'];
      if (route == 'chat') {
        return ChatPage(safetyController: widget.safetyController);
      }
      if (route == 'call') {
        return CallPage(safetyController: widget.safetyController);
      }
      if (route == 'checkin') {
        return CheckInModePage(
          sessionController: widget.sessionController,
          safetyController: widget.safetyController,
        );
      }
      if (route == 'text_checkin' || route == 'checkin_text') {
        return TextCheckInPage(
          sessionController: widget.sessionController,
          safetyController: widget.safetyController,
        );
      }
      if (route == 'session_detail') {
        final session = widget.sessionController.sessions.isNotEmpty
            ? widget.sessionController.sessions.first
            : null;
        if (session != null) {
          return SessionDetailPage(session: session);
        }
      }
    } catch (_) {}

    if (_isComplete || _shouldSkipOnboarding()) {
      return AppShell(
        sessionController: widget.sessionController,
        safetyController: widget.safetyController,
        profileController: widget.profileController,
        suggestionController: widget.suggestionController,
      );
    }

    return OnboardingFlow(
      repository: widget.repository,
      onComplete: () => setState(() => _isComplete = true),
    );
  }
}
