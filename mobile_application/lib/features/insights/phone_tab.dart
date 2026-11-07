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
                  if (i > 0)
                    const Divider(height: 18, color: Color(0x143B2F26)),
                  Row(
                    children: [
                      const Icon(
                        Icons.bookmark_rounded,
                        size: 16,
                        color: Color(0xFFB57A12),
                      ),
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
        minutes:
            byDay[dayKey(DateTime(today.year, today.month, today.day - back))],
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

class _WeekWaveState extends State<_WeekWave>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF3D4C78);
  static const _muted = Color(0xFF5A6787);
  late final AnimationController _draw;
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  static String _date(DateTime day) => '${day.day} ${_months[day.month - 1]}';
  static String _weekday(DateTime day) => _weekdays[day.weekday - 1];

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final values = [for (final day in days) day.minutes];
    final known = values.whereType<int>();
    final peak = known.reduce(math.max);
    final low = known.reduce(math.min);
    final lastKnown = days.lastWhere((day) => day.minutes != null);
    final picked = days.indexWhere((day) => day.day == _picked);
    final selected = picked < 0 ? days.indexOf(lastKnown) : picked;
    final day = days[selected];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final labelWidth = MediaQuery.textScalerOf(context).scale(10.5) * 3.2;

    return InsightCard(
      key: const ValueKey('week-wave'),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE6EDFC), Color(0xFFF7F5FF), Color(0xFFFFF8EA)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFD7E2F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.show_chart_rounded,
                  size: 20,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Screen time',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      '${_date(days.first.day)} – ${_date(days.last.day)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            day.minutes == null ? 'No reading' : durationLabel(day.minutes!),
            key: const ValueKey('phone-wave-reading'),
            style: const TextStyle(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          Text(
            '${_weekday(day.day)}, ${_date(day.day)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x286173AC)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(
                      constraints.maxWidth,
                      labelWidth * days.length,
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 106,
                          width: double.infinity,
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _WavePainter(
                                values: values,
                                peak: peak,
                                selected: selected,
                                reveal: reduceMotion
                                    ? const AlwaysStoppedAnimation(1)
                                    : _draw,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < days.length; i++)
                              Expanded(
                                child: _dayButton(
                                  days[i],
                                  selected: i == selected,
                                  index: i,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _RangePill(label: 'Low', value: durationLabel(low)),
              _RangePill(label: 'High', value: durationLabel(peak)),
            ],
          ),
          if (known.length < days.length) ...[
            const SizedBox(height: 8),
            const Text(
              'Dashes mark days without a complete reading.',
              style: TextStyle(
                fontSize: 11.5,
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayButton(WaveDay day, {required bool selected, required int index}) {
    final weekday = _weekday(day.day);
    void select() => setState(() => _picked = day.day);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$weekday ${_date(day.day)}, ${day.minutes == null ? 'no reading' : durationLabel(day.minutes!)}',
      onTap: select,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: selected ? const Color(0xFFFFEDCB) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('phone-wave-day-$index'),
            excludeFromSemantics: true,
            onTap: select,
            child: Semantics(
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: Text(
                    weekday,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangePill extends StatelessWidget {
  const _RangePill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFDDE6F8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '$label · $value',
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: _WeekWaveState._ink,
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.values,
    required this.peak,
    required this.selected,
    required this.reveal,
  }) : super(repaint: reveal);

  final List<int?> values;
  final int peak;
  final int selected;
  final Animation<double> reveal;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 13.0;
    final baseline = size.height - 12;
    final step = size.width / values.length;
    double x(int i) => step * (i + 0.5);
    final guide = Paint()..color = const Color(0x1A6173AC);
    for (final y in [top, (top + baseline) / 2, baseline]) {
      canvas.drawLine(Offset(x(0), y), Offset(x(values.length - 1), y), guide);
    }
    canvas.drawLine(
      Offset(x(selected), top),
      Offset(x(selected), baseline),
      Paint()
        ..color = const Color(0x69CE9135)
        ..strokeWidth = 1.3,
    );

    final points = [
      for (var i = 0; i < values.length; i++)
        if (values[i] case final int value)
          Offset(x(i), baseline - (baseline - top) * value / math.max(peak, 1))
        else
          null,
    ];
    final line = Paint()
      ..color = const Color(0xFF526DB6)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6;
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x626F8DE0), Color(0x006F8DE0)],
      ).createShader(Offset.zero & size);
    final gap = Paint()
      ..color = const Color(0xFF8290B0)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    canvas.save();
    final visible = Curves.easeOutCubic.transform(reveal.value) * size.width;
    canvas.clipRect(Rect.fromLTWH(0, 0, visible, size.height));
    // Each run is painted independently so an unknown day breaks the curve.
    var run = <Offset>[];
    for (final point in points) {
      if (point == null) {
        _drawRun(canvas, run, line, fill, baseline);
        run = [];
      } else {
        run.add(point);
      }
    }
    _drawRun(canvas, run, line, fill, baseline);
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (point == null) {
        canvas.drawLine(
          Offset(x(i) - 3, baseline),
          Offset(x(i) + 3, baseline),
          gap,
        );
      } else {
        final active = i == selected;
        canvas.drawCircle(
          point,
          active ? 5.5 : 3.8,
          Paint()..color = active ? const Color(0xFFAC6D15) : line.color,
        );
        canvas.drawCircle(
          point,
          active ? 3.0 : 1.8,
          Paint()..color = Colors.white,
        );
      }
    }
    canvas.restore();
  }

  void _drawRun(
    Canvas canvas,
    List<Offset> points,
    Paint line,
    Paint fill,
    double baseline,
  ) {
    if (points.length < 2) return;
    final curve = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final mid = (a.dx + b.dx) / 2;
      curve.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(curve)
      ..lineTo(points.last.dx, baseline)
      ..lineTo(points.first.dx, baseline)
      ..close();
    canvas.drawPath(area, fill);
    canvas.drawPath(curve, line);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.reveal != reveal ||
      old.selected != selected ||
      old.peak != peak ||
      old.values != values;
}
