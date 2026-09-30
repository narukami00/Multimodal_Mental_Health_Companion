import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/navigation/app_tab.dart';
import '../../core/theme/solace_palette.dart';
import '../../domain/home/home_card_priority.dart';
import '../../domain/suggestions/suggestion_schedule.dart';
import '../call/call_page.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_page.dart';
import '../checkin/check_in_mode_page.dart';
import '../insights/insights_page.dart';
import '../journal/journal_page.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_page.dart';
import '../rhythm/rhythm_card.dart';
import '../rhythm/welcome_back_notice.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_card_surface.dart';
import '../suggestions/suggestion_controller.dart';
import '../suggestions/suggestion_context.dart';
import '../suggestions/suggestion_page.dart';
import 'home_suggestion_card.dart';
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

  /// Builds the context a suggestion would be chosen in, and asks the engine
  /// whether there is one — without recording anything.
  ///
  /// This runs on every rebuild, so it must stay read-only. Recording here
  /// would inflate the very counts the confidence gate depends on.
  SuggestionCardChoice? _peekSuggestion() {
    final profile = widget.profileController.profile;
    final context = buildRecommendationContext(
      profile: profile,
      sessions: widget.sessionController.sessions,
    );
    final recommendation = widget.suggestionController.peek(
      profile: profile,
      context: context,
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
    final choice = _peekSuggestion();
    if (choice == null) return;
    final record = await widget.suggestionController.commit(
      choice.recommendation,
      context: choice.context,
    );
    await widget.suggestionController.dismissRecord(
      record.id,
      reason: SuggestionSkipReason.notNow,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.safetyController,
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
        );
        final homeState = HomeState(
          safetyFlagActive: safetyActive,
          checkInCompletedToday: checkInCompletedToday,
          suggestionDue: suggestionDue,
        );
        final showSuggestion = HomeCardPriority.showSuggestion(homeState);
        final suggestionChoice = showSuggestion ? _peekSuggestion() : null;
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
                showSuggestion: showSuggestion,
                suggestionCard: HomeSuggestionCard(
                  // Keyed by the activity so a genuinely new suggestion does not
                  // reuse the previous card's goodbye state.
                  key: ValueKey(suggestionChoice?.activity.id),
                  choice: suggestionChoice,
                  onAccept: _acceptSuggestion,
                  onDecline: _declineSuggestion,
                ),
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
          bottomNavigationBar: _buildBottomNav(context),
        );
      },
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Container(width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(
            color: colors.ink.withValues(alpha: 0.09),
            width: 1.0,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F78501E),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final tab in AppTab.values) _buildTabItem(tab),
            ],
          ),
        ),
      ),
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

  Widget _buildTabItem(AppTab tab) {
    final colors = SolaceColors.from(context);
    final isSelected = _selectedTab == tab;
    // Amber stays constant across palettes for brand contrast; only the
    // inactive ink follows the palette neutrals.
    const activeColor = Color(0xFFC87F10);
    final inactiveColor = colors.mutedInk;

    return Expanded(
      child: InkWell(
        onTap: () => _selectTab(tab),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.amber.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSelected ? tab.selectedIcon : tab.icon,
                size: 22,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
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
