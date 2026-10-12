import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';

import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../../domain/insights/mood_insights.dart';
import '../footprint/phone_patterns_controller.dart';
import '../sessions/session_controller.dart';
import 'insight_widgets.dart';

/// The colour of each mood word. Colour is never the only carrier: every dot
/// has a tooltip with its word, and the legend names them.
const moodColors = {
  'Bright': Color(0xFFFFB534),
  'Steady': Color(0xFF8DBB9A),
  'Quiet': Color(0xFFB4ADD6),
  'Tender': Color(0xFFEBA3A8),
  'Wobbly': Color(0xFFE98B6B),
};

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Mood over time, from the mood words the person actually chose.
class MoodTab extends StatefulWidget {
  const MoodTab({
    required this.sessionController,
    this.phonePatterns,
    this.clock,
    super.key,
  });

  final SessionController sessionController;

  /// Optional: lets the nights-and-moods card use sensed nights.
  final PhonePatternsController? phonePatterns;
  final DateTime Function()? clock;

  @override
  State<MoodTab> createState() => _MoodTabState();
}

class _MoodTabState extends State<MoodTab> {
  List<DailyFeatures> _rows = const [];

  @override
  void initState() {
    super.initState();
    widget.phonePatterns?.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.phonePatterns?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final patterns = widget.phonePatterns;
    if (patterns == null) return;
    final rows = await patterns.storedDays();
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sessionController,
      builder: (context, _) {
        final now = (widget.clock ?? DateTime.now)();
        final sessions = widget.sessionController.sessions;
        final strip = moodStrip(sessions, now);
        final summary = moodStripSummary(strip);
        final nights = nightsAndMoods(_rows, sessions);
        final throughDay = moodThroughTheDay(sessions);

        if (summary == null) {
          return const InsightEmpty(
            icon: Icons.wb_twilight_rounded,
            title: 'Your mood words will gather here',
            body:
                'Each time you check in with a mood word, it adds a dot. After a '
                'few days you will see how your weeks have felt, in your own words.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InsightCard(
              key: const ValueKey('mood-strip'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THE LAST 30 DAYS',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: insightMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MoodGrid(strip: strip, today: dateOnly(now)),
                  const SizedBox(height: 14),
                  const _Legend(),
                  const SizedBox(height: 12),
                  InsightBody(summary, strong: true),
                ],
              ),
            ),
            if (throughDay != null) ...[
              const InsightLabel('THROUGH THE DAY'),
              _ThroughTheDay(data: throughDay),
            ],
            if (nights != null) ...[
              const InsightLabel('NIGHTS AND MOODS'),
              InsightCard(
                key: const ValueKey('nights-and-moods'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAEEF8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bedtime_rounded,
                        size: 19,
                        color: Color(0xFF5F6FA0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: InsightBody(nights.text)),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Weeks as rows, Monday to Sunday, today last. Empty days are quiet rings.
class _MoodGrid extends StatelessWidget {
  const _MoodGrid({required this.strip, required this.today});

  final List<MoodDay> strip;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final first = strip.first.day;
    final lead = first.weekday - 1;
    final cells = <MoodDay?>[
      for (var i = 0; i < lead; i++) null,
      ...strip,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rows = cells.length ~/ 7;

    return Column(
      children: [
        Row(
          children: [
            for (final d in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    d.substring(0, 1),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: insightMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: Center(child: _dot(cells[r * 7 + c], r * 7 + c))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dot(MoodDay? day, int index) {
    if (day == null) return const SizedBox(width: 26, height: 26);
    final isToday = day.day == today;
    final color = day.mood == null ? null : moodColors[day.mood];
    final label =
        '${_weekdays[day.day.weekday - 1]} ${day.day.day} ${_months[day.day.month - 1]}'
        ' · ${day.mood == null ? 'no check-in' : Moods.display(day.mood)}';
    return Tooltip(
      message: label,
      triggerMode: TooltipTriggerMode.tap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + index * 12),
        curve: Curves.easeOutBack,
        builder: (context, t, child) =>
            Transform.scale(scale: t.clamp(0.0, 1.2), child: child),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: isToday
                  ? insightInk
                  : color == null
                  ? const Color(0x1F3B2F26)
                  : Colors.transparent,
              width: isToday ? 2 : 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: [
      for (final entry in moodColors.entries)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: entry.value, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              Moods.display(entry.key),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: insightSoft,
              ),
            ),
          ],
        ),
    ],
  );
}

/// How the mood words were spread over the four parts of the day. Each part is
/// one stacked bar of the words chosen then, so it shows how many check-ins there
/// were as well as what they said. Descriptive only.
class _ThroughTheDay extends StatelessWidget {
  const _ThroughTheDay({required this.data});

  final MoodThroughTheDay data;

  static const _icons = {
    DayPart.morning: Icons.wb_twilight_rounded,
    DayPart.afternoon: Icons.wb_sunny_rounded,
    DayPart.evening: Icons.wb_cloudy_rounded,
    DayPart.night: Icons.nightlight_round,
  };

  @override
  Widget build(BuildContext context) {
    final most = data.parts.map((p) => p.total).reduce((a, b) => a > b ? a : b);
    return InsightCard(
      key: const ValueKey('through-the-day'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final part in data.parts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(_icons[part.part], size: 17, color: insightMuted),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: Text(
                      part.part.label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: insightInk,
                      ),
                    ),
                  ),
                  Expanded(child: _bar(part, most)),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${part.total}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: insightSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (data.noticing != null) ...[
            const SizedBox(height: 2),
            InsightBody(data.noticing!, strong: true),
          ],
        ],
      ),
    );
  }

  /// Segments are in proportion to the check-ins, and the whole bar to the
  /// busiest part, so a part with few check-ins looks like it has few.
  Widget _bar(DayPartMood part, int most) {
    if (part.total == 0) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: const Color(0xFFF4EEDF),
          borderRadius: BorderRadius.circular(99),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: part.total / most),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, width, _) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: width.clamp(0.05, 1.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final word in moodColors.keys)
                    if ((part.counts[word] ?? 0) > 0)
                      Expanded(
                        flex: part.counts[word]!,
                        child: Container(color: moodColors[word]),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
