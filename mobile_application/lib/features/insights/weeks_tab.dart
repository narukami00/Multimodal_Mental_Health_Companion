import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../domain/insights/weekly_recap.dart';
import '../goals/goals_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'insight_widgets.dart';
import 'mood_tab.dart' show moodColors;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _plum = Color(0xFF62518A);
const _lavender = Color(0xFFECE5FA);

/// Recaps of completed weeks with an entry, newest first.
class WeeksTab extends StatelessWidget {
  const WeeksTab({
    required this.sessionController,
    this.suggestionController,
    this.goals,
    this.clock,
    super.key,
  });

  final SessionController sessionController;
  final SuggestionController? suggestionController;

  /// The person's phone goals, so a week can say how they went. Null leaves the recaps as they were.
  final GoalsController? goals;
  final DateTime Function()? clock;

  static String rangeLabel(WeekRecap week) {
    final a = week.weekStart, b = week.weekEnd;
    return a.month == b.month
        ? '${a.day} to ${b.day} ${_months[b.month - 1]}'
        : '${a.day} ${_months[a.month - 1]} to ${b.day} ${_months[b.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        sessionController,
        if (suggestionController != null) suggestionController!,
        if (goals != null) goals!,
      ]),
      builder: (context, _) {
        final recaps = weeklyRecaps(
          sessionController.sessions,
          suggestionController?.history ?? const [],
          (clock ?? DateTime.now)(),
          goalDays: goals?.days ?? const [],
        );
        if (recaps.isEmpty) {
          return const InsightEmpty(
            icon: Icons.calendar_view_week_rounded,
            title: 'Your first week will show up here',
            body: 'After a week with a check-in ends, its recap appears here.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WeeksOverview(recaps: recaps),
            const InsightLabel('WEEK BY WEEK'),
            for (final week in recaps) ...[
              _WeekCard(week: week, latest: identical(week, recaps.first)),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _WeeksOverview extends StatelessWidget {
  const _WeeksOverview({required this.recaps});

  final List<WeekRecap> recaps;

  @override
  Widget build(BuildContext context) {
    final days = recaps.fold<int>(0, (total, week) => total + week.activeDays);
    final details = overallSummary(recaps)!.skip(1);
    return InsightCard(
      key: const ValueKey('weeks-overall'),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_lavender, Color(0xFFF8F3FF), Color(0xFFFFF2DD)],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _plum, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'THE BIGGER PICTURE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: _plum,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _WeekStat(
                  recaps.length,
                  recaps.length == 1
                      ? 'Week with an entry'
                      : 'Weeks with entries',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WeekStat(
                  days,
                  days == 1 ? 'Day you checked in' : 'Days you checked in',
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final line in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InsightBody(line),
              ),
          ],
        ],
      ),
    );
  }
}

class _WeekStat extends StatelessWidget {
  const _WeekStat(this.value, this.label);

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 30,
              height: 1.1,
              color: _plum,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: insightSoft,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week, required this.latest});

  final WeekRecap week;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final days = week.activeDays;
    return InsightCard(
      key: ValueKey(
        'week-${week.weekStart.toIso8601String().substring(0, 10)}',
      ),
      gradient: latest
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF7F1FF), Colors.white],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _lavender,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: _plum,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (latest)
                      const Text(
                        'LATEST RECAP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _plum,
                          letterSpacing: 0.7,
                        ),
                      ),
                    Text(
                      WeeksTab.rangeLabel(week),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: insightInk,
                      ),
                    ),
                    Text(
                      '$days ${days == 1 ? 'day' : 'days'} with a check-in',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: insightSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < _weekdays.length; i++)
                Expanded(
                  child: _DayTile(
                    weekday: _weekdays[i],
                    hasEntry: week.dayHasEntry[i],
                    mood: week.dayMoods[i],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in week.lines.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: InsightBody(line),
            ),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.weekday,
    required this.hasEntry,
    required this.mood,
  });

  final String weekday;
  final bool hasEntry;
  final String? mood;

  @override
  Widget build(BuildContext context) {
    final color = moodColors[mood] ?? const Color(0xFFB5A4D8);
    return Semantics(
      label:
          '$weekday, ${hasEntry ? (mood == null ? 'check-in' : Moods.display(mood)) : 'no entry'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            Container(
              height: 31,
              decoration: BoxDecoration(
                color: hasEntry
                    ? Color.lerp(Colors.white, color, 0.34)
                    : const Color(0xFFF4F1F7),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: hasEntry
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 12),
                    )
                  : const SizedBox(
                      width: 7,
                      height: 2,
                      child: ColoredBox(color: Color(0xFFCCC1D4)),
                    ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                weekday,
                style: TextStyle(
                  fontSize: 10.5,
                  color: hasEntry ? insightInk : insightSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
