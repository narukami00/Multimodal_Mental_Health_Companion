import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/navigation/app_tab.dart';
import '../../domain/home/baseline_progress.dart';
import '../../domain/home/home_card_priority.dart';
import '../../domain/suggestions/suggestion_schedule.dart';
import '../../domain/suggestions/suggestion_tuning.dart';
import '../call/call_page.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_page.dart';
import '../checkin/check_in_mode_page.dart';
import '../insights/insights_page.dart';
import '../journal/journal_page.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_page.dart';
import '../profile/baseline_quiz_page.dart';
import '../rhythm/rhythm_card.dart';
import '../rhythm/welcome_back_notice.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_card_surface.dart';
import '../suggestions/suggestion_controller.dart';
import '../suggestions/suggestion_context.dart';
import '../suggestions/suggestion_page.dart';
import 'baseline_setup_card.dart';
import 'home_suggestion_card.dart';
import 'nav_pill.dart';
import 'today_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.sessionController,
    required this.safetyController,
    required this.profileController,
    required this.suggestionController,
    this.chatController,
    this.initialTab,
    super.key,
  });

  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;
  final SuggestionController suggestionController;
  final ChatController? chatController;
  final AppTab? initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppTab _selectedTab;
  late final ChatController _chatController;
  late final bool _ownsChatController;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab ?? _tabFromUri();
    if (widget.chatController != null) {
      _chatController = widget.chatController!;
      _ownsChatController = false;
    } else {
      _chatController = ChatController();
      _ownsChatController = true;
      _chatController.load();
    }
  }

  @override
  void dispose() {
    if (_ownsChatController) {
      _chatController.dispose();
    }
    super.dispose();
  }

  static AppTab _tabFromUri() {
    try {
      final tabParam = Uri.base.queryParameters['tab']?.toLowerCase();
      return switch (tabParam) {
        'today' => AppTab.today,
        'journal' => AppTab.journal,
        'insights' => AppTab.insights,
        'you' => AppTab.you,
        _ => AppTab.today,
      };
    } catch (_) {
      return AppTab.today;
    }
  }

  /// Everything Home's state is derived from.
  ///
  /// Built once so the subscriptions are not re-made on every rebuild.
  late final Listenable _homeInputs = Listenable.merge([
    widget.safetyController,
    widget.sessionController,
    widget.profileController,
    widget.suggestionController,
  ]);

  /// The suggestion to offer, or null if there is nothing to show.
  ///
  /// Both gates live here so the card can never be shown empty. Asking the
  /// schedule for a verdict and the engine for content separately is what let
  /// them disagree: the schedule said a nudge was due, the engine's own cap
  /// said no, and the card silently rendered nothing.
  SuggestionCardChoice? _peekSuggestion({required bool allowed}) {
    if (!allowed) return null;

    final now = DateTime.now();
    final profile = widget.profileController.profile;
    // Temporary: while the design is being tried out, the budget is off so the
    // card keeps coming back. See SuggestionTuning.
    const ignoreBudget = SuggestionTuning.alwaysOfferForTesting;

    final due = const SuggestionSchedule().isDue(
      history: widget.suggestionController.history,
      profileAgeDays: profileAgeInDays(profile),
      checkInCompletedToday: widget.sessionController.hasCheckedInOn(now),
      now: now,
      ignoreBudget: ignoreBudget,
    );
    if (!due) return null;

    final context = buildRecommendationContext(
      profile: profile,
      sessions: widget.sessionController.sessions,
      now: now,
    );
    final recommendation = widget.suggestionController.peek(
      profile: profile,
      context: context,
      now: now,
      ignoreBudget: ignoreBudget,
    );
    if (recommendation == null) return null;
    return SuggestionCardChoice(
      recommendation: recommendation,
      context: context,
    );
  }

  /// The user did it. The record is written now, at the moment they responded,
  /// and they land straight on the rating step.
  Future<void> _acceptSuggestion(SuggestionCardChoice choice) async {
    final record = await widget.suggestionController.commit(
      choice.recommendation,
      context: choice.context,
      proactive: true,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SuggestionPage(
          suggestionController: widget.suggestionController,
          profileController: widget.profileController,
          safetyController: widget.safetyController,
          sessionController: widget.sessionController,
          seededRecordId: record.id,
        ),
      ),
    );
  }

  /// "Not today", recorded so the card does not simply return on the next
  /// rebuild. Declining is still free: it never counts against the activity.
  Future<void> _declineSuggestion() async {
    // The card was on screen, so a suggestion is available regardless of where
    // the schedule now stands.
    final choice = _peekSuggestion(allowed: true);
    if (choice == null) return;
    final record = await widget.suggestionController.commit(
      choice.recommendation,
      context: choice.context,
      proactive: true,
    );
    await widget.suggestionController.dismissRecord(
      record.id,
      reason: SuggestionSkipReason.notNow,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Home reads from all of these. Listening only to the safety controller
      // meant a check-in, a completed setup, or an accepted suggestion left the
      // card showing whatever it had at first build.
      animation: _homeInputs,
      builder: (context, _) {
        final safetyActive = widget.safetyController.hasActiveFlag;
        final now = DateTime.now();
        final checkInCompletedToday = widget.sessionController.hasCheckedInOn(
          now,
        );
        // Temporary: while the design is being tried out, the budget is off so
        // the card keeps coming back. See SuggestionTuning.
        const ignoreBudget = SuggestionTuning.alwaysOfferForTesting;
        final suggestionDue = const SuggestionSchedule().isDue(
          history: widget.suggestionController.history,
          profileAgeDays: profileAgeInDays(widget.profileController.profile),
          checkInCompletedToday: checkInCompletedToday,
          now: now,
          // Without this the switch never reached here, and every gate below
          // stayed shut no matter what the tuning said.
          ignoreBudget: ignoreBudget,
        );
        final baseline = BaselineProgress.of(widget.profileController.profile);
        final homeState = HomeState(
          safetyFlagActive: safetyActive,
          checkInCompletedToday: checkInCompletedToday,
          // Real setup state, so the onboarding card can actually appear. It
          // used to default to complete and could never render.
          onboardingComplete: baseline.isComplete,
          suggestionDue: suggestionDue,
        );
        final showSuggestion = HomeCardPriority.showSuggestion(homeState);
        final suggestionChoice = _peekSuggestion(allowed: showSuggestion);
        return Scaffold(
          body: IndexedStack(
            index: _selectedTab.index,
            children: [
              TodayPage(
                chatController: _chatController,
                ambientAudioEnabled:
                    widget.profileController.profile.ambientAudioEnabled,
                rhythmCard: RhythmCard(
                  sessionController: widget.sessionController,
                  profileController: widget.profileController,
                  suggestionController: widget.suggestionController,
                ),
                welcomeBackNotice: WelcomeBackNotice(
                  sessionController: widget.sessionController,
                  profileController: widget.profileController,
                ),
                primaryCard: HomeCardPriority.select(homeState),
                // Derived from what will actually be drawn, so Home can never
                // reserve space for a card that has nothing in it.
                showSuggestion: suggestionChoice != null,
                suggestionCard: HomeSuggestionCard(
                  // Keyed by the activity so a genuinely new suggestion does not
                  // reuse the previous card's goodbye state.
                  key: ValueKey(suggestionChoice?.activity.id),
                  choice: suggestionChoice,
                  onAccept: _acceptSuggestion,
                  onDecline: _declineSuggestion,
                  // Once the card has closed, ask for the next one so Home is
                  // not left waiting for some unrelated rebuild.
                  onVanished: () => setState(() {}),
                ),
                // Hidden once setup is done, and never shown to someone in a
                // safety state, where it would read as one more thing to do.
                setupCard: baseline.isComplete || safetyActive
                    ? null
                    : BaselineSetupCard(
                        progress: baseline,
                        onContinue: () => _openSetup(context),
                      ),
                onContinueSetup: () => _openSetup(context),
                onStartCheckIn: safetyActive
                    ? () => _openSupport(context)
                    : () => _openCheckIn(context),
                onOpenSupport: () => _openSupport(context),
                onOpenChat: () => _openChat(context),
                onStartNewChat: () => _openChat(context, startNew: true),
                onOpenCall: () => _openCall(context),
              ),
              JournalPage(sessionController: widget.sessionController),
              InsightsPage(sessionController: widget.sessionController),
              ProfilePage(
                profileController: widget.profileController,
                safetyController: widget.safetyController,
                suggestionController: widget.suggestionController,
                sessionController: widget.sessionController,
              ),
            ],
          ),
          // Not extendBody: the Scaffold reserves the pill's space, so content
          // can never be cut off underneath it. The pill still floats visually,
          // since the area around it is transparent to the page behind.
          bottomNavigationBar: SolaceNavPill(
            selected: _selectedTab,
            onSelect: _selectTab,
          ),
        );
      },
    );
  }

  /// Switches tab, giving a gentle haptic cue when the user has enabled them.
  void _selectTab(AppTab tab) {
    if (_selectedTab == tab) return;
    if (widget.profileController.profile.hapticsEnabled) {
      // Best effort: never block navigation on the haptics channel.
      unawaited(HapticFeedback.selectionClick());
    }
    setState(() => _selectedTab = tab);
  }

  void _openCheckIn(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckInModePage(
          sessionController: widget.sessionController,
          safetyController: widget.safetyController,
          profileController: widget.profileController,
        ),
      ),
    );
  }

  /// Opens the baseline reflection quiz, where setup is continued.
  void _openSetup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BaselineQuizPage(
          profileController: widget.profileController,
          safetyController: widget.safetyController,
        ),
      ),
    );
  }

  void _openSupport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportResourcesPage(
          safetyController: widget.safetyController,
          profileController: widget.profileController,
          assessment:
              widget.safetyController.activeAssessment ??
              const SafetyAssessment.clear(),
        ),
      ),
    );
  }

  void _openChat(BuildContext context, {bool startNew = false}) {
    if (startNew) {
      _chatController.startNewConversation();
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          safetyController: widget.safetyController,
          profileController: widget.profileController,
          chatController: _chatController,
          autoConnect: true,
        ),
      ),
    ).then((_) {
      _chatController.pruneEmptyConversations();
    });
  }

  void _openCall(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallPage(
          safetyController: widget.safetyController,
          profileController: widget.profileController,
          chatController: _chatController,
        ),
      ),
    );
  }
}
