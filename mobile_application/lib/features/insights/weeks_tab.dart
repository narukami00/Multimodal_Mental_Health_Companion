import 'package:flutter/material.dart';

import '../../domain/insights/weekly_recap.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'insight_widgets.dart';
import 'mood_tab.dart' show moodColors;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// "Weeks": a short, plain recap of each finished week, and an overall picture built from all of them.
///
/// A recap only describes what happened. There is no score and no comparison between weeks, and a quiet week is just a
/// quiet week. Weeks with nothing in them are not listed.
class WeeksTab extends StatelessWidget {
  const WeeksTab({required this.sessionController, this.suggestionController, this.clock, super.key});

  final SessionController sessionController;
  final SuggestionController? suggestionController;
  final DateTime Function()? clock;

  static String rangeLabel(WeekRecap week) {
    final a = week.weekStart, b = week.weekEnd;
    return a.month == b.month ? '${a.day} to ${b.day} ${_months[b.month - 1]}' : '${a.day} ${_months[a.month - 1]} to ${b.day} ${_months[b.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sessionController, if (suggestionController != null) suggestionController!]),
      builder: (context, _) {
        final recaps = weeklyRecaps(
          sessionController.sessions,
          suggestionController?.history ?? const [],
          (clock ?? DateTime.now)(),
        );
        if (recaps.isEmpty) {
          return const InsightEmpty(
            icon: Icons.calendar_view_week_rounded,
            title: 'Your first week will show up here',
            body: 'When a week is over, a short recap of it appears here. Nothing to do: just check in when you want to.',
          );
        }
        final overall = overallSummary(recaps)!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InsightCard(
              key: const ValueKey('weeks-overall'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('THE BIGGER PICTURE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: insightMuted)),
                  const SizedBox(height: 8),
                  for (final line in overall) Padding(padding: const EdgeInsets.only(bottom: 4), child: InsightBody(line, strong: line == overall.first)),
                ],
              ),
            ),
            const InsightLabel('WEEK BY WEEK'),
            for (final week in recaps) ...[_WeekCard(week: week), const SizedBox(height: 12)],
          ],
        );
      },
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week});

  final WeekRecap week;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      key: ValueKey('week-${week.weekStart.toIso8601String().substring(0, 10)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(WeeksTab.rangeLabel(week), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: insightInk)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Semantics(
                  label: '${_initials[i]}: ${week.dayHasEntry[i] ? (week.dayMoods[i] ?? 'checked in') : 'no entry'}',
                  child: Column(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: week.dayHasEntry[i] ? (moodColors[week.dayMoods[i]] ?? const Color(0xFFD9CFBF)) : Colors.transparent,
                          border: Border.all(color: week.dayHasEntry[i] ? Colors.transparent : insightLine, width: 1.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_initials[i], style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: insightMuted)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in week.lines) Padding(padding: const EdgeInsets.only(bottom: 3), child: InsightBody(line)),
        ],
      ),
    );
  }
}
