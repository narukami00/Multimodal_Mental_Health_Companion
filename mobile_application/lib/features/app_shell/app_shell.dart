import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../insights/moments_tab.dart';
import '../memory/companion_memory_context.dart';
import '../memory/what_sol_remembers_page.dart';
import '../memory/moment_proposal_card.dart';
import '../memory/moments_controller.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/navigation/app_tab.dart';
import '../../core/day_key.dart';
import '../../domain/home/baseline_progress.dart';
import '../../domain/home/home_card_priority.dart';
import '../../domain/suggestions/suggestion_schedule.dart';
import '../call/call_page.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_page.dart';
import '../checkin/check_in_mode_page.dart';
import '../insights/insights_page.dart';
import '../journal/journal_page.dart';
import '../footprint/break_prompt_card.dart';
import '../footprint/day_rhythm_card.dart';
import '../footprint/break_prompt_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_page.dart';
import '../profile/therapist_controller.dart';
import '../profile/baseline_quiz_page.dart';
import '../rhythm/rhythm_card.dart';
import '../rhythm/rhythm_detail_page.dart';
import '../rhythm/week_dots.dart';
import '../rhythm/welcome_back_notice.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
import '../suggestions/idea_push_sync.dart';
import '../suggestions/suggestion_card_surface.dart';
import '../suggestions/suggestion_controller.dart';
import '../suggestions/suggestion_context.dart';
import '../suggestions/suggestion_page.dart';
import 'setup_progress_badge.dart';
import 'check_in_task_card.dart';
import 'home_rail.dart';
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
    this.therapistController,
    this.phonePatterns,
    this.breakPrompts,
    this.moments,
    this.memory,
    this.initialTab,
    super.key,
  });

  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;
  final SuggestionController suggestionController;
  final ChatController? chatController;
  final TherapistController? therapistController;
  final PhonePatternsController? phonePatterns;
  final BreakPromptController? breakPrompts;
  final MomentsController? moments;
  final CompanionMemoryContext? memory;
  final AppTab? initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppTab _selectedTab;
  late final ChatController _chatController;
  late final bool _ownsChatController;
  final _ideaPushSync = IdeaPushSync();

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
    final now = DateTime.now();
    final profile = widget.profileController.profile;

    // An idea already on show stays until it is answered or expires, whatever
    // the budget now says: showing it is what used the budget up.
    final pending = widget.suggestionController.pendingProactive(now: now);
    if (pending != null &&
        !widget.safetyController.hasActiveFlag &&
        widget.sessionController.hasCheckedInOn(now)) {
      return SuggestionCardChoice(
        recommendation: pending.recommendation,
        context: buildRecommendationContext(
          profile: profile,
          sessions: widget.sessionController.sessions,
          now: now,
          extraTags: widget.breakPrompts?.activeThemes() ?? const [],
        ),
      );
    }
    if (!allowed) return null;

    final due = const SuggestionSchedule().isDue(
      history: widget.suggestionController.history,
      profileAgeDays: profileAgeInDays(profile),
      checkInCompletedToday: widget.sessionController.hasCheckedInOn(now),
      now: now,
    );
    if (!due) return null;

    final context = buildRecommendationContext(
      profile: profile,
      sessions: widget.sessionController.sessions,
      now: now,
      extraTags: widget.breakPrompts?.activeThemes() ?? const [],
    );
    final recommendation = widget.suggestionController.peek(
      profile: profile,
      context: context,
      now: now,
    );
    if (recommendation == null) return null;
    return SuggestionCardChoice(
      recommendation: recommendation,
      context: context,
    );
  }

  /// Writes down that an idea has been put on screen, once it actually is.
  ///
  /// Deferred to after the frame so building Home never writes, and safe to ask
  /// on every rebuild because the write is idempotent. A pending idea already
  /// has its record, so only a fresh pick reaches the controller.
  void _rememberShown(SuggestionCardChoice? choice) {
    if (choice == null ||
        widget.suggestionController.pendingProactive() != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.suggestionController.commit(
        choice.recommendation,
        context: choice.context,
        proactive: true,
      );
    });
  }

  /// The user did it. The record is written now, at the moment they responded,
  /// and they land straight on the rating step.
  Future<void> _acceptSuggestion(SuggestionCardChoice choice) async {
    final record = await widget.suggestionController.commit(
      choice.recommendation,
      context: choice.context,
      proactive: true,
    );
    // Accepting lands on the rating step, which treats the idea as done, so the
    // completion is written now. Without it the record stayed `shown`: the idea
    // came back after a restart and the card was left faded out until then.
    await widget.suggestionController.recordCompletion();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SuggestionPage(
          suggestionController: widget.suggestionController,
          profileController: widget.profileController,
          safetyController: widget.safetyController,
          sessionController: widget.sessionController,
          seededRecordId: record.id,
          extraEventTags: widget.breakPrompts?.activeThemes() ?? const [],
        ),
      ),
    );
  }

  /// Opens the rhythm page, where a rest day can be declared.
  void _openRhythm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RhythmDetailPage(
          sessionController: widget.sessionController,
          profileController: widget.profileController,
          suggestionController: widget.suggestionController,
        ),
      ),
    );
  }

  /// Opens the full details for the suggestion Home is showing.
  ///
  /// Nothing is recorded by opening it: seeing an idea in full is not the same
  /// as being offered it, and the record is written only when the user answers.
  void _openSuggestionDetails(SuggestionCardChoice? choice) {
    if (choice == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SuggestionPage(
          suggestionController: widget.suggestionController,
          profileController: widget.profileController,
          safetyController: widget.safetyController,
          sessionController: widget.sessionController,
          seededChoice: choice,
          extraEventTags: widget.breakPrompts?.activeThemes() ?? const [],
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
        final suggestionDue = const SuggestionSchedule().isDue(
          history: widget.suggestionController.history,
          profileAgeDays: profileAgeInDays(widget.profileController.profile),
          checkInCompletedToday: checkInCompletedToday,
          now: now,
          // Without this the switch never reached here, and every gate below
          // stayed shut no matter what the tuning said.
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
        _rememberShown(suggestionChoice);
        // After the frame, like the write above: building Home must not do I/O.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _ideaPushSync.sync(
            profile: widget.profileController.profile,
            history: widget.suggestionController.history,
            lastCheckInAt: widget.sessionController.lastCheckInAt,
          );
        });
        return Scaffold(
          // The capsule is an overlay, not a bottom bar. It is a child of the
          // body rather than bottomNavigationBar, so the Scaffold reserves no
          // strip for it and paints none of its own background behind it. The
          // page runs edge to edge underneath.
          body: Stack(
            children: [
              IndexedStack(
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
                // The task now lives inside the check-in card, so the separate
                // suggestion card is only used when there is no primary card to
                // attach it to.
                showSuggestion:
                    suggestionChoice != null &&
                    HomeCardPriority.select(homeState) == HomeCardType.support,
                taskOffer: suggestionChoice == null
                    ? null
                    : TaskOffer(
                        eyebrow: 'An idea for today',
                        title: suggestionChoice.activity.title,
                        description: suggestionChoice.activity.description,
                      ),
                weekDots: WeekDots(
                  checkedIn: [
                    for (var i = 6; i >= 0; i--)
                      widget.sessionController.hasCheckedInOn(
                        now.subtract(Duration(days: i)),
                      ),
                  ],
                  rested: [
                    for (var i = 6; i >= 0; i--)
                      widget.profileController.profile.restDays.contains(
                        dayKey(now.subtract(Duration(days: i))),
                      ),
                  ],
                  onTap: () => _openRhythm(context),
                ),
                homeRail: AnimatedBuilder(
                  animation: _chatController,
                  builder: (context, _) {
                    final last = _chatController.conversations.firstOrNull;
                    final lastMsg = last?.messages
                        .where((m) => (m.isVoice
                                ? (m.transcription ?? '')
                                : m.text)
                            .trim()
                            .isNotEmpty)
                        .lastOrNull;
                    return HomeRail(
                      journalCount: widget.sessionController.sessions.length,
                      lastMessage: last == null || lastMsg == null
                          ? null
                          : RailLastMessage(
                              text: (lastMsg.isVoice
                                      ? lastMsg.transcription!
                                      : lastMsg.text)
                                  .trim(),
                              fromUser: lastMsg.isUser,
                              when: last.dateStr,
                            ),
                      onJournal: () => _selectTab(AppTab.journal),
                      onConversations: () {
                        // Resume that exact thread, not whichever one happens
                        // to be active.
                        if (last != null) {
                          _chatController.switchConversation(last.id);
                        }
                        _openChat(context);
                      },
                    );
                  },
                ),
                dayRhythm: widget.phonePatterns == null
                    ? null
                    : DayRhythmCard(
                        phonePatterns: widget.phonePatterns!,
                        profileController: widget.profileController,
                      ),
                patternPrompt: widget.breakPrompts == null
                    ? null
                    : ListenableBuilder(
                        listenable: widget.breakPrompts!,
                        builder: (context, _) =>
                            BreakPromptCard(controller: widget.breakPrompts!),
                      ),
                momentPrompt: widget.moments == null
                    ? null
                    : MomentProposalCard(
                        controller: widget.moments!,
                        consent: widget.memory?.consent,
                        suppressed: () =>
                            widget.safetyController.hasActiveFlag ||
                            widget.profileController.profile.momentPromptsMuted,
                        onStopAsking: () =>
                            widget.profileController.setMomentPromptsMuted(true),
                      ),
                onTaskOpen: () => _openSuggestionDetails(suggestionChoice),
                onTaskAccept: () => _acceptSuggestion(suggestionChoice!),
                onTaskDecline: _declineSuggestion,
                // Only a tap now. Holding the shape used to open the most recent
                // conversation, but the rail's conversations tile already does
                // exactly that, and holding now fills the bubble with air and
                // pops it.
                onBlobTap: () => _openChat(context, startNew: true),
                suggestionCard: HomeSuggestionCard(
                  // Keyed by the activity so a genuinely new suggestion does not
                  // reuse the previous card's goodbye state.
                  key: ValueKey(suggestionChoice?.activity.id),
                  choice: suggestionChoice,
                  onAccept: _acceptSuggestion,
                  onDecline: _declineSuggestion,
                  onOpen: () => _openSuggestionDetails(suggestionChoice),
                  // Once the card has closed, ask for the next one so Home is
                  // not left waiting for some unrelated rebuild.
                  onVanished: () => setState(() {}),
                ),
                // The big setup card is gone: the tiny meter under the date
                // chip is now the only standing nudge. Hidden once setup is
                // done, and never shown to someone in a safety state, where it
                // would read as one more thing to do.
                setupProgressBadge: baseline.isComplete || safetyActive
                    ? null
                    : SetupProgressBadge(
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
              InsightsPage(
                sessionController: widget.sessionController,
                suggestionController: widget.suggestionController,
                phonePatterns: widget.phonePatterns,
                profileController: widget.profileController,
                breakPrompts: widget.breakPrompts,
                momentsTab: widget.moments == null
                    ? null
                    : MomentsInsightsTab(
                        moments: widget.moments!,
                        onManage: widget.memory == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => WhatSolRemembersPage(
                                    moments: widget.moments!,
                                    memory: widget.memory!,
                                    consent: widget.memory!.consent,
                                    profileController: widget.profileController,
                                    chat: _chatController,
                                  ),
                                ),
                              ),
                      ),
              ),
              ProfilePage(
                profileController: widget.profileController,
                safetyController: widget.safetyController,
                suggestionController: widget.suggestionController,
                sessionController: widget.sessionController,
                therapistController: widget.therapistController,
                phonePatterns: widget.phonePatterns,
                moments: widget.moments,
                memory: widget.memory,
                chatController: _chatController,
                extraEventTags: () =>
                    widget.breakPrompts?.activeThemes() ?? const [],
              ),
            ],
          ),
              // Sits on top of the view stack, above the pages.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SolaceNavCapsule(
                  selected: _selectedTab,
                  onSelect: _selectTab,
                ),
              ),
            ],
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
