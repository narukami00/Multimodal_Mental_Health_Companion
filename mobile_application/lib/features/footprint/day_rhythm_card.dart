import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/daily_features.dart';
import '../../domain/footprint/day_rhythm.dart';
import '../profile/phone_patterns_page.dart';
import '../profile/profile_controller.dart';
import 'phone_patterns_controller.dart';

const _ink = Color(0xFF3A3125);
const _muted = Color(0xFF6B5B43);
const _amber = Color(0xFFFFB534);
const _night = Color(0xFF7C8DB8);

/// Home: yesterday as a 24-hour ring. Quiet when there is nothing real to show
/// (turned off, or no finished day yet), and never an assessment of the day.
class DayRhythmCard extends StatefulWidget {
  const DayRhythmCard({
    required this.phonePatterns,
    required this.profileController,
    this.clock,
    super.key,
  });

  final PhonePatternsController phonePatterns;
  final ProfileController profileController;
  final DateTime Function()? clock;

  @override
  State<DayRhythmCard> createState() => _DayRhythmCardState();
}

class _DayRhythmCardState extends State<DayRhythmCard> {
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

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhonePatternsPage(
          phonePatterns: widget.phonePatterns,
          profileController: widget.profileController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rhythm = dayRhythm(_rows, (widget.clock ?? DateTime.now)());
    if (rhythm == null) return const SizedBox.shrink();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      container: true,
      label: 'Yesterday on your phone. ${rhythm.caption}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          key: const ValueKey('day-rhythm-card'),
          borderRadius: BorderRadius.circular(26),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x143B2F26)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: DayRhythmRing(rhythm: rhythm, animate: !reduceMotion),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YESTERDAY ON YOUR PHONE',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFFA69883),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rhythm.caption,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          const _Key(color: _amber, label: 'Screen on'),
                          if (rhythm.hasNight) const _Key(color: _night, label: 'Phone down'),
                          if (rhythm.usualHours != null)
                            const _Key(color: Color(0xFFD9CBB0), label: 'Your usual'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _muted),
      ),
    ],
  );
}

/// The 24-hour ring itself, sized by its parent. Shared by Home and by
/// My phone patterns.
class DayRhythmRing extends StatefulWidget {
  const DayRhythmRing({
    required this.rhythm,
    required this.animate,
    this.showTotal = true,
    super.key,
  });
  final DayRhythm rhythm;
  final bool animate;

  /// Whether the centre says how long the screen was on. A page that already
  /// says so beside the ring turns it off and shows "24 hours" instead.
  final bool showTotal;

  @override
  State<DayRhythmRing> createState() => _DayRhythmRingState();
}

class _DayRhythmRingState extends State<DayRhythmRing> with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _grow.forward();
      _breathe.repeat(reverse: true);
    } else {
      _grow.value = 1;
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rhythm;
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_grow, _breathe]),
              builder: (context, _) => CustomPaint(
                painter: _RingPainter(
                  rhythm: r,
                  grow: Curves.easeOutCubic.transform(_grow.value),
                  breathe: Curves.easeInOut.transform(_breathe.value),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.showTotal ? _compact(r.totalMinutes) : '24',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              Text(
                widget.showTotal ? 'screen on' : 'hours',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.rhythm, required this.grow, required this.breathe});

  final DayRhythm rhythm;
  final double grow;
  final double breathe;

  // Midnight at the top, clockwise.
  static double _angle(double hours) => -math.pi / 2 + hours / 24 * 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    final inner = outer * 0.64;
    final maxLen = outer - inner - 4;

    // The overnight arc, drawn first and calm, just inside the ticks.
    if (rhythm.hasNight) {
      final start = rhythm.sleepStartMinute! / 60;
      var end = rhythm.sleepEndMinute! / 60;
      if (end <= start) end += 24;
      final rect = Rect.fromCircle(center: center, radius: inner - 6);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = _night.withValues(alpha: 0.55 + 0.15 * breathe);
      canvas.drawArc(rect, _angle(start), (end - start) / 24 * 2 * math.pi * grow, false, paint);
    }

    final usual = rhythm.usualHours;
    for (var h = 0; h < 24; h++) {
      final mid = _angle(h + 0.5);
      final dir = Offset(math.cos(mid), math.sin(mid));

      // What an ordinary hour has looked like: a faint tick behind.
      if (usual != null) {
        final len = 2 + maxLen * usual[h] * grow;
        canvas.drawLine(
          center + dir * inner,
          center + dir * (inner + len),
          Paint()
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFD9CBB0).withValues(alpha: 0.55),
        );
      }

      // Staggered so the day draws itself around the ring.
      final delay = h / 24 * 0.5;
      final local = ((grow - delay) / (1 - 0.5)).clamp(0.0, 1.0);
      final share = rhythm.hours[h];
      final pulse = 1 + 0.035 * (breathe - 0.5) * 2 * (share > 0.05 ? 1 : 0);
      final len = (2 + maxLen * share * pulse) * local;
      final alpha = (0.35 + 0.65 * share).clamp(0.0, 1.0);
      canvas.drawLine(
        center + dir * inner,
        center + dir * (inner + len),
        Paint()
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = (share <= 0 ? const Color(0xFFEFE6D4) : _amber).withValues(alpha: alpha),
      );
    }

    // Four quiet anchors so the ring reads as a clock without any numbers.
    final dot = Paint()..color = const Color(0xFFBCAC8E);
    for (final h in [0, 6, 12, 18]) {
      final a = _angle(h.toDouble());
      canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * (outer + 0), 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.rhythm != rhythm || old.grow != grow || old.breathe != breathe;
}

/// "9h 56m": short enough to sit inside the ring.
String _compact(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
