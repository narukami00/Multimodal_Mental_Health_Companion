import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/navigation/app_tab.dart';
import '../../domain/home/home_card_priority.dart';
import '../checkin/check_in_mode_page.dart';
import '../insights/insights_page.dart';
import '../journal/journal_page.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_page.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'today_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.sessionController,
    required this.safetyController,
    required this.profileController,
    required this.suggestionController,
    this.initialTab,
    super.key,
  });

  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;
  final SuggestionController suggestionController;
  final AppTab? initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppTab _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab ?? _tabFromUri();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.safetyController,
      builder: (context, _) {
        final safetyActive = widget.safetyController.hasActiveFlag;
        return Scaffold(
          body: IndexedStack(
            index: _selectedTab.index,
            children: [
              TodayPage(
                primaryCard: HomeCardPriority.select(
                  HomeState(safetyFlagActive: safetyActive),
                ),
                onStartCheckIn: safetyActive
                    ? () => _openSupport(context)
                    : () => _openCheckIn(context),
                onOpenSupport: () => _openSupport(context),
              ),
              JournalPage(sessionController: widget.sessionController),
              InsightsPage(sessionController: widget.sessionController),
              ProfilePage(
                profileController: widget.profileController,
                safetyController: widget.safetyController,
                suggestionController: widget.suggestionController,
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(context),
        );
      },
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFAFFFDF6),
        border: Border(
          top: BorderSide(color: Color(0x174A3728), width: 1.0),
        ),
        boxShadow: [
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

  Widget _buildTabItem(AppTab tab) {
    final isSelected = _selectedTab == tab;
    const activeColor = Color(0xFFC87F10);
    const inactiveColor = Color(0xFFA5937C);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = tab),
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
                color: isSelected ? const Color(0x28FFB534) : Colors.transparent,
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
        ),
      ),
    );
  }

  void _openSupport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportResourcesPage(
          safetyController: widget.safetyController,
          assessment:
              widget.safetyController.activeAssessment ??
              const SafetyAssessment.clear(),
          regionCode: Localizations.localeOf(context).countryCode ?? 'GLOBAL',
        ),
      ),
    );
  }
}
