import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/models/memory_moment.dart';
import '../../core/widgets/visual_kit.dart';
import '../../domain/insights/what_helped.dart';
import '../art/activity_art.dart';

bool get _quiet {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// What the Today page puts in the space below its cards: one quiet card. The
/// painted sky behind the bottom of the page is [SkyBackdrop].
///
/// The card is chosen by what is true for this person, never by a quota:
/// what has lifted them (from their own before-and-after answers), otherwise a
/// moment they chose to keep, otherwise a minute to breathe. It carries no
/// counts to chase and no streaks.
class TodayFooter extends StatelessWidget {
  const TodayFooter({
    required this.helped,
    required this.keptMoments,
    required this.now,
    super.key,
  });

  /// Kinds of activity they said left them lighter, most reliable first.
  final List<HelpedKind> helped;

  /// Moments they agreed to keep, newest first.
  final List<MemoryMoment> keptMoments;
  final DateTime now;

  /// The headline for a kind that has lifted them. Worded as a tendency in what
  /// they reported, and never as a cause: it is built from fixed phrases so it
  /// reads naturally whatever the activity was called.
  static String headlineFor(ActivityType type) => switch (type) {
    ActivityType.movement => 'A little movement tends to lift you',
    ActivityType.social => 'Time with people tends to lift you',
    ActivityType.creative => 'Making something tends to lift you',
    ActivityType.nature => 'Time outside tends to lift you',
    ActivityType.mindfulness => 'A quiet moment tends to lift you',
    ActivityType.learning => 'Learning something tends to lift you',
    ActivityType.productivity => 'Finishing a small task tends to lift you',
  };

  /// "You felt lighter 3 of 4 times." A report of what they said.
  static String detailFor(HelpedKind kind) => kind.lighter == kind.tries
      ? 'You felt lighter after it, all ${kind.tries} times.'
      : 'You felt lighter after it ${kind.lighter} of ${kind.tries} times.';

  /// Which period of the day the scene shows, and its caption.
  static (String, String) periodFor(int hour) {
    if (hour < 5) return ('night', 'Late. Rest is allowed.');
    if (hour < 8) return ('dawn', 'Early light. Nothing needs doing yet.');
    if (hour < 12) return ('morning', 'Morning. Take it as it comes.');
    if (hour < 17) return ('afternoon', 'Afternoon. Nothing needs doing.');
    if (hour < 20) return ('evening', 'Evening. You can slow down.');
    return ('night', 'Night. Rest is allowed.');
  }

  @override
  Widget build(BuildContext context) {
    final Widget card;
    if (helped.isNotEmpty) {
      card = _LiftedCard(kind: helped.first);
    } else if (keptMoments.isNotEmpty) {
      // A different kept moment each day, so it stays a small surprise.
      final index =
          (now.year * 400 + now.month * 31 + now.day) % keptMoments.length;
      card = _MomentEcho(moment: keptMoments[index]);
    } else {
      card = const _BreatheCard();
    }
    return card;
  }
}

class _LiftedCard extends StatelessWidget {
  const _LiftedCard({required this.kind});

  final HelpedKind kind;

  @override
  Widget build(BuildContext context) {
    return KitCard(
      key: const ValueKey('today-lifted'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: ActivityArt(
              type: kind.type,
              circle: true,
              animate: !_quiet,
              progress: _quiet ? 0.5 : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WHAT HAS LIFTED YOU',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: kitMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  TodayFooter.headlineFor(kind.type),
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: kitInk,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < math.min(kind.tries, 6); i++)
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < kind.lighter ? kitAmber : kitLine,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        TodayFooter.detailFor(kind),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: kitSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentEcho extends StatelessWidget {
  const _MomentEcho({required this.moment});

  final MemoryMoment moment;

  @override
  Widget build(BuildContext context) {
    return KitCard(
      key: const ValueKey('today-moment'),
      color: const Color(0xFFFFF8EC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, size: 14, color: kitCoral),
              SizedBox(width: 6),
              Text(
                'A GOOD MOMENT YOU KEPT',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: kitMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '“${moment.text}”',
            style: const TextStyle(
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: kitInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// The fallback: a slow circle to breathe with. Nothing to read and nothing to
/// do; it is only there.
class _BreatheCard extends StatefulWidget {
  const _BreatheCard();

  @override
  State<_BreatheCard> createState() => _BreatheCardState();
}

class _BreatheCardState extends State<_BreatheCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );
  Timer? _label;
  String _text = 'Breathe in';

  @override
  void initState() {
    super.initState();
    if (!_quiet) {
      _c.repeat(reverse: true);
      _label = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        setState(
          () => _text = _text == 'Breathe in' ? 'Breathe out' : 'Breathe in',
        );
      });
    } else {
      _c.value = 0.5;
    }
  }

  @override
  void dispose() {
    _label?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KitCard(
      key: const ValueKey('today-breathe'),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_c.value);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 40 + 32 * t,
                      height: 40 + 32 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kitAmber.withValues(alpha: 0.16),
                      ),
                    ),
                    Container(
                      width: 30 + 20 * t,
                      height: 30 + 20 * t,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFD27A), Color(0xFFFFA05A)],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A MINUTE FOR YOU',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: kitMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _text,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: kitInk,
                  ),
                ),
                const Text(
                  'Follow the circle, as slowly as you like.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kitSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sky behind the bottom of the Today page: no card, no edge. It is anchored
/// to the bottom of the screen and fades upward into the page background, so as
/// the content scrolls over it, it reads as part of the page itself.
class SkyBackdrop extends StatelessWidget {
  const SkyBackdrop({required this.hour, this.height = 300, super.key});

  /// 0 to 24, with minutes as a fraction.
  final double hour;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (_, caption) = TodayFooter.periodFor(hour.floor());
    return IgnorePointer(
      child: Semantics(
        label: caption,
        child: SizedBox(
          key: const ValueKey('today-sky'),
          width: double.infinity,
          height: height,
          child: CustomPaint(painter: SkyPainter(hour)),
        ),
      ),
    );
  }
}

class SkyPainter extends CustomPainter {
  SkyPainter(this.hour);

  final double hour;

  static bool _isNight(double h) => h < 5 || h >= 20;

  /// Top and bottom sky colours for the hour. Pastel, so the page stays light
  /// even at night.
  static (Color, Color) skyFor(double h) {
    if (h < 5) return (const Color(0xFF8C90D6), const Color(0xFFB9A8E6));
    if (h < 8) return (const Color(0xFFFFC9A8), const Color(0xFFFFE2B8));
    if (h < 17) return (const Color(0xFFBFE3F5), const Color(0xFFFFF0C8));
    if (h < 20) return (const Color(0xFFFFA874), const Color(0xFFFFD79A));
    return (const Color(0xFF8C90D6), const Color(0xFFB9A8E6));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (top, bottom) = skyFor(hour);
    // Transparent at the top, so it melts into whatever the page is.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            top.withValues(alpha: 0),
            top.withValues(alpha: 0.35),
            bottom.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Offset.zero & size),
    );

    final night = _isNight(hour);
    // The sun crosses from left to right between 5 and 20; the moon between 20
    // and 5. Both ride a shallow arc in the lower half of the backdrop.
    final span = night ? ((hour >= 20 ? hour - 20 : hour + 4) / 9.0) : ((hour - 5) / 15.0);
    final t = span.clamp(0.0, 1.0);
    final cx = size.width * (0.14 + 0.72 * t);
    final cy = size.height * (0.78 - 0.30 * math.sin(math.pi * t));

    if (night) {
      final star = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.75);
      final r = math.Random(7);
      for (var i = 0; i < 16; i++) {
        canvas.drawCircle(
          Offset(r.nextDouble() * size.width, size.height * (0.35 + r.nextDouble() * 0.3)),
          0.6 + r.nextDouble() * 1.0,
          star,
        );
      }
      canvas.drawCircle(Offset(cx, cy), 26, Paint()..color = const Color(0xFFFFF3C9).withValues(alpha: 0.25));
      canvas.drawCircle(Offset(cx, cy), 14, Paint()..color = const Color(0xFFFFF3C9));
      canvas.drawCircle(Offset(cx + 5, cy - 3), 12, Paint()..color = top.withValues(alpha: 0.9));
    } else {
      final sunColor = hour < 8 || hour >= 17 ? const Color(0xFFFFB066) : const Color(0xFFFFD35C);
      canvas.drawCircle(Offset(cx, cy), 46, Paint()..color = sunColor.withValues(alpha: 0.18));
      canvas.drawCircle(Offset(cx, cy), 30, Paint()..color = sunColor.withValues(alpha: 0.28));
      canvas.drawCircle(Offset(cx, cy), 18, Paint()..color = sunColor);
    }

    // Two soft hills along the bottom edge.
    final hill1 = Path()
      ..moveTo(0, size.height * 0.88)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.74, size.width * 0.6, size.height * 0.87)
      ..quadraticBezierTo(size.width * 0.84, size.height * 0.95, size.width, size.height * 0.83)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final hill2 = Path()
      ..moveTo(0, size.height * 0.95)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.84, size.width, size.height * 0.96)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      hill1,
      Paint()..color = night ? const Color(0xFF7A7ECB).withValues(alpha: 0.55) : const Color(0xFFE6B982).withValues(alpha: 0.45),
    );
    canvas.drawPath(
      hill2,
      Paint()..color = night ? const Color(0xFF6A6EBB).withValues(alpha: 0.6) : const Color(0xFFD99F66).withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(SkyPainter old) => old.hour != hour;
}
