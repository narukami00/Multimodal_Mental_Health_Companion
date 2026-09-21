import 'package:flutter/material.dart';

enum AppTab { today, journal, insights, you }

extension AppTabPresentation on AppTab {
  String get label => switch (this) {
        AppTab.today => 'Today',
        AppTab.journal => 'Journal',
        AppTab.insights => 'Insights',
        AppTab.you => 'You',
      };

  IconData get icon => switch (this) {
        AppTab.today => Icons.wb_sunny_outlined,
        AppTab.journal => Icons.auto_stories_outlined,
        AppTab.insights => Icons.insights_outlined,
        AppTab.you => Icons.person_outline,
      };

  IconData get selectedIcon => switch (this) {
        AppTab.today => Icons.wb_sunny,
        AppTab.journal => Icons.auto_stories,
        AppTab.insights => Icons.insights,
        AppTab.you => Icons.person,
      };
}
