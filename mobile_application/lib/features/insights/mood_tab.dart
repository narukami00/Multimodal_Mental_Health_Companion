import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';

import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../domain/insights/journal_breakdown.dart';
import '../../domain/insights/mood_insights.dart';
import '../footprint/phone_patterns_controller.dart';
import '../journal/session_detail_page.dart';
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

/// Mood over time, from how each journal entry read (older entries: the word picked at the time).
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

  void _openDay(MoodDay day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFDF6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => _DaySheet(
        day: day,
        onOpen: (session) {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SessionDetailPage(
                session: session,
                onDelete: (s) => widget.sessionController.deleteSession(s.id),
                onReanalyze: widget.sessionController.reanalyze,
              ),
            ),
          );
        },
      ),
    );
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
                  _MoodGrid(strip: strip, today: dateOnly(now), onTapDay: _openDay),
                  const SizedBox(height: 14),
                  const _Legend(),
                  const SizedBox(height: 12),
                  InsightBody(summary, strong: true),
                  const SizedBox(height: 6),
                  const Text(
                    'A dot split into colours is a day with more than one entry. Tap a day to see them.',
                    style: TextStyle(fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600, color: insightMuted),
                  ),
                ],
              ),
            ),
            const InsightLabel('YOUR JOURNALS'),
            _JournalBreakdownCard(breakdown: JournalBreakdown.from(sessions, now)),
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
  const _MoodGrid({required this.strip, required this.today, required this.onTapDay});

  final List<MoodDay> strip;
  final DateTime today;
  final ValueChanged<MoodDay> onTapDay;

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
    final words = day.entries.isEmpty ? <String>[] : day.moods;
    final names = {for (final w in words) Moods.display(w)}.join(', ');
    final label =
        '${_weekdays[day.day.weekday - 1]} ${day.day.day} ${_months[day.day.month - 1]}'
        ' · ${words.isEmpty ? 'no check-in' : '${words.length} ${words.length == 1 ? 'entry' : 'entries'}: $names'}';
    return Semantics(
      label: label,
      button: words.isNotEmpty,
      child: GestureDetector(
        key: ValueKey('mood-day-${dayKey(day.day)}'),
        behavior: HitTestBehavior.opaque,
        onTap: words.isEmpty ? null : () => onTapDay(day),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 300 + index * 12),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Transform.scale(scale: t.clamp(0.0, 1.2), child: child),
              child: CustomPaint(
                size: const Size(26, 26),
                painter: _DayDotPainter(
                  colors: [for (final w in words) moodColors[w] ?? const Color(0xFFB4ADD6)],
                  isToday: isToday,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One circle per day, cut into a slice per entry in the order they were made (clockwise from the top),
/// so a day with a low, an even and a calm entry shows all three colours instead of only the last.
class _DayDotPainter extends CustomPainter {
  const _DayDotPainter({required this.colors, required this.isToday});

  final List<Color> colors;
  final bool isToday;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = rect.center;
    final r = size.width / 2;
    if (colors.isEmpty) {
      canvas.drawCircle(
        c,
        r - 0.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isToday ? 2 : 1.2
          ..color = isToday ? insightInk : const Color(0x1F3B2F26),
      );
      return;
    }
    if (colors.length == 1) {
      canvas.drawCircle(c, r, Paint()..color = colors.first);
    } else {
      final sweep = 2 * math.pi / colors.length;
      for (var i = 0; i < colors.length; i++) {
        canvas.drawArc(rect, -math.pi / 2 + i * sweep, sweep, true, Paint()..color = colors[i]);
      }
      final gap = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.4;
      for (var i = 0; i < colors.length; i++) {
        final a = -math.pi / 2 + i * sweep;
        canvas.drawLine(c, c + Offset(r * math.cos(a), r * math.sin(a)), gap);
      }
    }
    if (isToday) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = insightInk,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DayDotPainter old) => old.colors.join() != colors.join() || old.isToday != isToday;
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

IconData _modeIcon(CaptureMode mode) => switch (mode) {
      CaptureMode.text => Icons.edit_outlined,
      CaptureMode.voice => Icons.graphic_eq_rounded,
      CaptureMode.video => Icons.videocam_outlined,
    };

String _modeName(CaptureMode mode) => switch (mode) {
      CaptureMode.text => 'Text',
      CaptureMode.voice => 'Voice',
      CaptureMode.video => 'Video',
    };

Color _colorForWord(String word) =>
    moodColors[Moods.values.firstWhere((m) => Moods.display(m) == word, orElse: () => 'Quiet')] ?? const Color(0xFFB4ADD6);

/// Every entry of one day: when, which kind, how it read, and the first words. Tap one to open it.
class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day, required this.onOpen});

  final MoodDay day;
  final ValueChanged<SessionRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final title = '${_weekdays[day.day.weekday - 1]} ${day.day.day} ${_months[day.day.month - 1]}';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          key: const ValueKey('mood-day-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: insightInk)),
            const SizedBox(height: 2),
            Text(
              '${day.entries.length} ${day.entries.length == 1 ? 'entry' : 'entries'}, in the order you made them',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: insightMuted),
            ),
            const SizedBox(height: 14),
            for (final e in day.entries) _DayEntryRow(entry: e, onTap: () => onOpen(e)),
          ],
        ),
      ),
    );
  }
}

class _DayEntryRow extends StatelessWidget {
  const _DayEntryRow({required this.entry, required this.onTap});

  final SessionRecord entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mood = entry.effectiveMood;
    final color = (mood == null ? null : moodColors[mood]) ?? const Color(0xFFB4ADD6);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.createdAt));
    final text = entry.text?.trim() ?? '';
    return InkWell(
      key: ValueKey('mood-day-entry-${entry.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(_modeIcon(entry.mode), size: 16, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${_modeName(entry.mode)} · $time',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: insightMuted)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
                        child: Text(
                          mood == null ? 'Not read yet' : Moods.display(mood),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: insightInk),
                        ),
                      ),
                    ],
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, color: insightSoft)),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFC6B28C)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The journal side of the emotional picture for the last 30 days: how many of each kind of entry, how
/// they read in all, what each kind tends to read as, and the overall lean. Descriptive, never a verdict.
class _JournalBreakdownCard extends StatelessWidget {
  const _JournalBreakdownCard({required this.breakdown});

  final JournalBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    if (b.isEmpty) {
      return const InsightCard(
        key: ValueKey('journal-breakdown'),
        child: InsightBody('No journal entries in the last 30 days yet.'),
      );
    }
    final maxMode = b.byMode.values.reduce((a, c) => a > c ? a : c);
    final lean = b.leaning;
    final energy = b.energyWord;
    return InsightCard(
      key: const ValueKey('journal-breakdown'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${b.total} ${b.total == 1 ? 'entry' : 'entries'} in the last ${b.days} days',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: insightInk),
          ),
          const SizedBox(height: 14),
          for (final mode in CaptureMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                key: ValueKey('journal-mode-${mode.name}'),
                children: [
                  Icon(_modeIcon(mode), size: 17, color: insightMuted),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 52,
                    child: Text(_modeName(mode),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: insightInk)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: maxMode == 0 ? 0 : (b.byMode[mode] ?? 0) / maxMode,
                        minHeight: 10,
                        backgroundColor: const Color(0xFFF4EEDF),
                        color: const Color(0xFFD9A441),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('${b.byMode[mode]}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: insightSoft)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Text('HOW THEY READ',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: insightMuted)),
          const SizedBox(height: 8),
          if (b.read == 0)
            const InsightBody('None of these entries has been read for how it felt yet.')
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(
                key: const ValueKey('journal-mood-bar'),
                children: [
                  for (final w in JournalBreakdown.wordOrder)
                    if ((b.moodCounts[w] ?? 0) > 0) Expanded(flex: b.moodCounts[w]!, child: Container(height: 12, color: _colorForWord(w))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final w in JournalBreakdown.wordOrder)
                  if ((b.moodCounts[w] ?? 0) > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: _colorForWord(w), shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text('$w ${b.moodCounts[w]} · ${(b.moodCounts[w]! * 100 / b.read).round()}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: insightSoft)),
                    ]),
              ],
            ),
            const SizedBox(height: 12),
            InsightBody(
              [
                if (b.dominantWord != null) '${b.dominantWord} came up most.',
                if (lean != null) 'Overall your entries read $lean${energy == null ? '' : ', with $energy energy'}.',
              ].join(' '),
              strong: true,
            ),
            for (final mode in CaptureMode.values)
              if (b.leanByMode[mode] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InsightBody('Your ${_modeName(mode).toLowerCase()} entries mostly read ${b.leanByMode[mode]!.toLowerCase()}.'),
                ),
          ],
        ],
      ),
    );
  }
}
