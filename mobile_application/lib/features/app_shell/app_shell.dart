import 'package:flutter/material.dart';

import '../../core/navigation/app_tab.dart';
import '../../domain/home/home_card_priority.dart';
import '../placeholders/feature_placeholder_page.dart';
import 'today_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _selectedTab = AppTab.today;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTab.index,
        children: [
          TodayPage(
            primaryCard: HomeCardPriority.select(const HomeState()),
          ),
          const FeaturePlaceholderPage(
            title: 'Your journal',
            description: 'Past check-ins and reflections will live here.',
            icon: Icons.auto_stories_outlined,
          ),
          const FeaturePlaceholderPage(
            title: 'Your insights',
            description: 'Gentle patterns will appear here as your history grows.',
            icon: Icons.insights_outlined,
          ),
          const FeaturePlaceholderPage(
            title: 'You',
            description: 'Profile, privacy, sharing, and settings will live here.',
            icon: Icons.person_outline,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab.index,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = AppTab.values[index]);
        },
        destinations: [
          for (final tab in AppTab.values)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
