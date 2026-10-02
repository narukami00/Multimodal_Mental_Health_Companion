import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../../domain/footprint/day_rhythm.dart';
import '../footprint/break_prompt_card.dart';
import '../footprint/break_prompt_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import '../profile/profile_controller.dart';
import 'insight_widgets.dart';
import 'phone_patterns_section.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Phone patterns: what is usual, the last week as a wave, and the shifts the
/// person has named. Every part is hidden or says so when there is no data.
class PhoneTab extends StatefulWidget {
  const PhoneTab({
    required this.phonePatterns,
    required this.profileController,
    this.breakPrompts,
    this.clock,
    super.key,
  });

  final PhonePatternsController phonePatterns;
  final ProfileController profileController;
  final BreakPromptController? breakPrompts;
  final DateTime Function()? clock;

  @override
  State<PhoneTab> createState() => _PhoneTabState();
}

class _PhoneTabState extends State<PhoneTab> {
  List<DailyFeatures> _rows = const [];

  @override
  void initState() {
    super.initState();
    widget.phonePatterns.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.phonePatterns.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final rows = await widget.phonePatterns.storedDays();
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.clock ?? DateTime.now)();
    final week = weekOfScreenTime(_rows, now);
    final named = widget.breakPrompts?.answered ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (week != null) ...[
          const InsightLabel('THE LAST WEEK'),
          _WeekWave(days: week),
        ],
        PhonePatternsSection(
          phonePatterns: widget.phonePatterns,
          profileController: widget.profileController,
          clock: widget.clock,
        ),
        if (named.isNotEmpty) ...[
          const InsightLabel('SHIFTS YOU NAMED'),
          InsightCard(
            key: const ValueKey('named-shifts'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < named.length; i++) ...[
                  if (i > 0) const Divider(height: 18, color: Color(0x143B2F26)),
                  Row(
                    children: [
                      const Icon(Icons.bookmark_rounded, size: 16, color: Color(0xFFB57A12)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InsightBody(
                          named[i].theme == null
                              ? 'Nothing in particular'
                              : BreakPromptCard.themeLabel(named[i].theme!),
                          strong: true,
                        ),
                      ),
                      Text(
                        '${named[i].decidedAt!.day} ${_months[named[i].decidedAt!.month - 1]}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: insightMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Text(
              'The times you said something was going on. Only you see this.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: insightMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One day of the week wave.
class WaveDay {
  const WaveDay({required this.day, required this.minutes});
  final DateTime day;
  final int? minutes;
}

/// The last seven days up to yesterday, oldest first, or null when fewer than
/// three of them have screen time (not enough to draw a wave honestly).
List<WaveDay>? weekOfScreenTime(List<DailyFeatures> rows, DateTime now) {
  final today = dateOnly(now);
  final byDay = {
    for (final row in rows)
      if (row.hasUsage && row.usageComplete && row.screenOnMinutes != null)
        row.dayKey: row.screenOnMinutes!,
  };
  final days = [
    for (var back = 7; back >= 1; back--)
      WaveDay(
        day: DateTime(today.year, today.month, today.day - back),
        minutes: byDay[dayKey(DateTime(today.year, today.month, today.day - back))],
      ),
  ];
  return days.where((d) => d.minutes != null).length >= 3 ? days : null;
}

class _WeekWave extends StatefulWidget {
  const _WeekWave({required this.days});
  final List<WaveDay> days;

  @override
  State<_WeekWave> createState() => _WeekWaveState();
}

class _WeekWaveState extends State<_WeekWave> with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _draw.forward();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = [for (final d in widget.days) if (d.minutes != null) d.minutes!];
    final peak = known.reduce(math.max);
    final low = known.reduce(math.min);
    return InsightCard(
      key: const ValueKey('week-wave'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 120,
            child: AnimatedBuilder(
              animation: _draw,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _WavePainter(
                  values: [for (final d in widget.days) d.minutes?.toDouble()],
                  progress: Curves.easeOutCubic.transform(_draw.value),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final d in widget.days)
                Expanded(
                  child: Center(
                    child: Text(
                      _weekdays[d.day.weekday - 1].substring(0, 1),
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
          const SizedBox(height: 10),
          InsightBody(
            'Screen time ran from ${durationLabel(low)} to ${durationLabel(peak)} '
            'this week.',
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.values, required this.progress});

  final List<double?> values;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final known = [for (final v in values) if (v != null) v];
    final hi = known.reduce(math.max);
    final lo = math.min(known.reduce(math.min), hi * 0.5);
    final range = math.max(hi - lo, 1);
    const pad = 14.0;
    final step = size.width / values.length;

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      points.add(
        Offset(step * (i + 0.5), pad + (size.height - pad * 2) * (1 - (v - lo) / range)),
      );
    }
    if (points.length < 2) return;

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }

    final metric = line.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);

    final fill = Path.from(drawn);
    final tip = metric.getTangentForOffset(metric.length * progress)?.position ?? points.last;
    fill
      ..lineTo(tip.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x40FFB534), Color(0x00FFB534)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFB534),
    );
    for (final p in points) {
      if (p.dx <= tip.dx + 0.5) {
        canvas.drawCircle(p, 4.2, Paint()..color = Colors.white);
        canvas.drawCircle(
          p,
          4.2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = const Color(0xFFFFB534),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.values != values;
}
