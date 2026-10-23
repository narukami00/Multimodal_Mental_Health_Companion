import 'package:flutter/material.dart';

import '../memory/companion_memory_context.dart';
import '../memory/moments_controller.dart';
import '../../core/models/safety_assessment.dart';
import '../../data/contracts/onboarding_repository.dart';
import '../app_shell/app_shell.dart';
import '../call/call_page.dart';
import '../chat/chat_page.dart';
import '../chat/conversation_history.dart';
import '../chat/chat_controller.dart';
import '../checkin/check_in_mode_page.dart';
import '../checkin/text_check_in_page.dart';
import '../journal/session_detail_page.dart';
import '../footprint/break_prompt_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import '../profile/baseline_quiz_page.dart';
import '../profile/profile_controller.dart';
import '../profile/therapist_controller.dart';
import '../profile/habit_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import '../consent/consent_controller.dart';
import 'onboarding_flow.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    required this.repository,
    required this.sessionController,
    required this.safetyController,
    required this.profileController,
    required this.suggestionController,
    this.chatController,
    this.therapistController,
    this.habitController,
    this.phonePatterns,
    this.breakPrompts,
    this.moments,
    this.memory,
    this.consent,
    this.scheduleReminder,
    super.key,
  });

  final OnboardingRepository repository;
  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;
  final SuggestionController suggestionController;
  final ChatController? chatController;
  final TherapistController? therapistController;
  final HabitController? habitController;
  final PhonePatternsController? phonePatterns;
  final BreakPromptController? breakPrompts;
  final MomentsController? moments;
  final CompanionMemoryContext? memory;
  final ConsentController? consent;
  final Future<bool> Function(int minutes)? scheduleReminder;

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
        return ChatPage(
          safetyController: widget.safetyController,
          autoConnect: true,
        );
      }
      if (route == 'history') {
        return Scaffold(
          backgroundColor: const Color(0xFFFEFCE8),
          body: ConversationHistorySheet(
            onSelectThread: (_) {},
            onNewConversation: () {},
          ),
        );
      }
      if (route == 'call') {
        return CallPage(
          safetyController: widget.safetyController,
          profileController: widget.profileController,
        );
      }
      if (route == 'support' || route == 'emergency') {
        return SupportResourcesPage(
          safetyController: widget.safetyController,
          profileController: widget.profileController,
          assessment: const SafetyAssessment(
            level: SafetyLevel.urgentSupport,
            matchedSignals: ['manual_request'],
          ),
        );
      }
      if (route == 'baseline') {
        return BaselineQuizPage(
          profileController: widget.profileController,
          safetyController: widget.safetyController,
        );
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
        chatController: widget.chatController,
        therapistController: widget.therapistController,
        habitController: widget.habitController,
        phonePatterns: widget.phonePatterns,
        breakPrompts: widget.breakPrompts,
        moments: widget.moments,
        memory: widget.memory,
      );
    }

    return OnboardingFlow(
      repository: widget.repository,
      profileController: widget.profileController,
      consent: widget.consent,
      scheduleReminder: widget.scheduleReminder,
      onComplete: () => setState(() => _isComplete = true),
    );
  }
}
