import 'package:flutter/material.dart';

import '../../domain/insights/weekly_recap.dart';
import '../profile/profile_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';

/// The card on Today that says last week's recap is ready.
///
/// It shows for the first few days after a week ends, until it is opened or dismissed once; then it is gone, and the
/// next finished week brings a new one (dressed a little differently). It never nags and never counts anything missed.
class WeeklyRecapCard extends StatelessWidget {
  const WeeklyRecapCard({
    required this.sessionController,
    required this.profileController,
    required this.onOpen,
    this.suggestionController,
    this.clock,
    super.key,
  });

  final SessionController sessionController;
  final ProfileController profileController;
  final SuggestionController? suggestionController;

  /// Takes the person to the Weeks tab.
  final VoidCallback onOpen;
  final DateTime Function()? clock;

  static const _looks = [
    (title: 'Your week is ready', icon: Icons.auto_awesome_rounded, tint: Color(0xFFFFF4DA), accent: Color(0xFFB57A12)),
    (title: 'Last week, at a glance', icon: Icons.wb_twilight_rounded, tint: Color(0xFFEAF4EA), accent: Color(0xFF4F8A52)),
    (title: 'A look back at your week', icon: Icons.local_florist_rounded, tint: Color(0xFFF1EDFA), accent: Color(0xFF6E73C8)),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sessionController, profileController]),
      builder: (context, _) {
        final now = (clock ?? DateTime.now)();
        final recaps = weeklyRecaps(sessionController.sessions, suggestionController?.history ?? const [], now);
        final week = RecapNudge.forToday(recaps, now, profileController.profile.recapSeenWeek);
        if (week == null) return const SizedBox.shrink();

        final look = _looks[RecapNudge.variantFor(week.weekStart)];
        final key = RecapNudge.weekKey(week.weekStart);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            key: const ValueKey('recap-card'),
            color: look.tint,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                await profileController.markRecapSeen(key);
                onOpen();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
                child: Row(
                  children: [
                    Icon(look.icon, color: look.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(look.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: look.accent)),
                          const SizedBox(height: 2),
                          Text(week.lines.first, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4, color: Color(0xFF6C5E50))),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('recap-card-dismiss'),
                      tooltip: 'Not now',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: const Color(0xFFA69883),
                      onPressed: () => profileController.markRecapSeen(key),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
