import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Which stretch of the day the scene is painted for.
enum DayPart { dawn, day, dusk, night }

/// What the scene is told about the person's day. Pure, so what it decides can be tested without painting.
///
/// The mood trend is used only for tone: lighter and slower when things have been heavy, never to say
/// anything about the person. Nothing here is shown as a number or a verdict.
class IdeaScene {
  const IdeaScene({required this.hour, required this.level, required this.trend, required this.tries});

  /// [moodScores] are daily mood scores, oldest first, from -1 to 1 (as [dailyMoodScores] gives them).
  factory IdeaScene.from({required DateTime now, required List<double> moodScores, required int tries}) {
    double mean(Iterable<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
    final level = mean(moodScores);
    var trend = 0.0;
    if (moodScores.length >= 3) {
      final half = moodScores.length ~/ 2;
      trend = mean(moodScores.sublist(moodScores.length - half)) - mean(moodScores.sublist(0, half));
    }
    return IdeaScene(
      hour: now.hour + now.minute / 60,
      level: level.clamp(-1.0, 1.0).toDouble(),
      trend: trend.clamp(-1.0, 1.0).toDouble(),
      tries: tries,
    );
  }

  final double hour;

  /// The recent average mood, -1 to 1 (0 with nothing to go on).
  final double level;

  /// Recent days against the days before them, -1 (down) to 1 (up).
  final double trend;

  /// Ideas finished so far, shown as small lights in the scene.
  final int tries;

  DayPart get part {
    if (hour >= 5 && hour < 9) return DayPart.dawn;
    if (hour >= 9 && hour < 16) return DayPart.day;
    if (hour >= 16 && hour < 20) return DayPart.dusk;
    return DayPart.night;
  }

  /// Things have been heavy lately: the scene turns softer and slower, and the words get smaller.
  bool get gentle => level < -0.1 || trend < -0.3;

  /// How fast things drift: slower when gentle.
  double get pace => gentle ? 0.55 : 1.0;

  String get invitation {
    if (gentle) return 'Something small, if you feel like it.';
    return switch (part) {
      DayPart.dawn => 'A small something to start the day?',
      DayPart.day => 'A small something for the day?',
      DayPart.dusk => 'Something gentle for the evening?',
      DayPart.night => 'Something quiet before sleep?',
    };
  }
}

/// The Helps tab's way in: "Want to try something?" over a scene that follows the time of day and the
/// person's recent mood. With an idea already under way, the same card shows that instead, with the two ways
/// to end it, and there is no way to ask for another until it is finished or dropped.
class IdeasInvitationCard extends StatefulWidget {
  const IdeasInvitationCard({
    required this.scene,
    required this.onStart,
    this.doingTitle,
    this.onResume,
    this.onDone,
    this.onInterrupt,
    super.key,
  });

  final IdeaScene scene;
  final VoidCallback onStart;

  /// The idea under way, when there is one.
  final String? doingTitle;
  final VoidCallback? onResume;
  final VoidCallback? onDone;
  final VoidCallback? onInterrupt;

  @override
  State<IdeasInvitationCard> createState() => _IdeasInvitationCardState();
}

class _IdeasInvitationCardState extends State<IdeasInvitationCard> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still when the person has asked their phone for less motion, and in tests (a loop never settles).
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!still && !_isTestEnvironment) {
      if (!_started) {
        _loop.repeat();
        _started = true;
      }
    } else if (_started) {
      _loop.stop();
      _started = false;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    final night = scene.part == DayPart.night;
    final ink = night ? const Color(0xFFFFF6E6) : const Color(0xFF3A3125);
    final soft = night ? const Color(0xCCFFF6E6) : const Color(0xFF6C5E50);
    final doing = widget.doingTitle != null;
    final lines = doing ? "Take your time. This will be here when you're done." : scene.invitation;

    return Semantics(
      container: true,
      label: doing ? "You're on ${widget.doingTitle}" : 'Want to try something? ${scene.invitation}',
      child: ClipRRect(
        key: const ValueKey('ideas-invitation'),
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) => CustomPaint(painter: _ScenePainter(scene, _loop.value)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doing ? "YOU'RE ON THIS" : 'AN IDEA, WHEN YOU WANT ONE',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: soft),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    doing ? widget.doingTitle! : 'Want to try something?',
                    style: TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: ink),
                  ),
                  const SizedBox(height: 4),
                  Text(lines, style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: soft)),
                  if (!doing && scene.tries > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      scene.tries == 1 ? '1 tried so far' : '${scene.tries} tried so far',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: soft),
                    ),
                  ],
                  const SizedBox(height: 120),
                  if (doing)
                    Row(
                      children: [
                        Expanded(
                          child: _Pill(
                            key: const ValueKey('ideas-done'),
                            label: "I'm done",
                            filled: true,
                            night: night,
                            onTap: widget.onDone,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Pill(
                            key: const ValueKey('ideas-interrupt'),
                            label: 'Something came up',
                            filled: false,
                            night: night,
                            onTap: widget.onInterrupt,
                          ),
                        ),
                      ],
                    )
                  else
                    _Pill(
                      key: const ValueKey('ideas-start'),
                      label: 'Show me an idea',
                      filled: true,
                      night: night,
                      onTap: widget.onStart,
                    ),
                ],
              ),
            ),
            if (doing && widget.onResume != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 120,
                child: GestureDetector(
                  key: const ValueKey('ideas-resume'),
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onResume,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.filled, required this.night, required this.onTap, super.key});

  final String label;
  final bool filled;
  final bool night;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = night ? const Color(0xFFFFF6E6) : const Color(0xFF3A3125);
    return Material(
      color: filled ? (night ? const Color(0x33FFFFFF) : const Color(0xE6FFFFFF)) : Colors.transparent,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: fg.withValues(alpha: 0.35))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: fg),
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.t);

  final IdeaScene scene;

  /// 0 to 1, looping.
  final double t;

  static const _sky = {
    DayPart.dawn: (Color(0xFFFAD9C5), Color(0xFFFFB78A)),
    DayPart.day: (Color(0xFFFFF1CF), Color(0xFFFFD28A)),
    DayPart.dusk: (Color(0xFFF0BFAA), Color(0xFFC58FB6)),
    DayPart.night: (Color(0xFF3E3C66), Color(0xFF7D6B9E)),
  };

  static const _body = {
    DayPart.dawn: Color(0xFFFFD29A),
    DayPart.day: Color(0xFFFFC857),
    DayPart.dusk: Color(0xFFFF9E6B),
    DayPart.night: Color(0xFFFFF3D6),
  };

  /// Lighter and flatter when gentle, so the scene never competes with a hard day.
  Color _soften(Color c) => scene.gentle ? Color.lerp(c, const Color(0xFFF7EFE6), 0.28)! : c;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final (top, bottom) = _sky[scene.part]!;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_soften(top), _soften(bottom)]).createShader(rect),
    );

    final night = scene.part == DayPart.night;
    final speed = scene.pace;
    final drift = t * speed;

    // Stars, a few, twinkling.
    if (night) {
      final r = math.Random(7);
      for (var i = 0; i < 22; i++) {
        final x = r.nextDouble() * w, y = r.nextDouble() * h * 0.55;
        final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin((drift * 2 + i * 0.37) * 2 * math.pi));
        canvas.drawCircle(Offset(x, y), 0.8 + r.nextDouble() * 1.1, Paint()..color = Colors.white.withValues(alpha: 0.55 * tw));
      }
    }

    // The sun or moon crosses the sky with the hour.
    final hour = scene.hour;
    final p = night ? (((hour >= 20 ? hour - 20 : hour + 4) / 10).clamp(0.0, 1.0)) : (((hour - 5) / 15).clamp(0.0, 1.0));
    final c = Offset(w * (0.12 + 0.76 * p), h * (0.62 - 0.38 * math.sin(math.pi * p)));
    final bodyColor = _body[scene.part]!;
    final breathe = 1 + 0.04 * math.sin(drift * 2 * math.pi);
    canvas.drawCircle(
      c,
      70 * breathe,
      Paint()..shader = RadialGradient(colors: [bodyColor.withValues(alpha: scene.gentle ? 0.35 : 0.5), bodyColor.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: 70 * breathe)),
    );
    canvas.drawCircle(c, 17, Paint()..color = _soften(bodyColor));

    // Hills, drifting very slowly.
    Path hill(double base, double amp, double phase, double freq) {
      final path = Path()..moveTo(0, h);
      for (double x = 0; x <= w; x += 4) {
        final y = base + amp * math.sin((x / w * freq + phase + drift * 0.5) * 2 * math.pi);
        path.lineTo(x, y);
      }
      return path..lineTo(w, h)..close();
    }

    final deep = Color.lerp(bottom, night ? const Color(0xFF211F3D) : const Color(0xFF8A5A3C), night ? 0.5 : 0.28)!;
    canvas.drawPath(hill(h * 0.74, 7, 0.0, 1.1), Paint()..color = _soften(Color.lerp(bottom, deep, 0.45)!));
    canvas.drawPath(hill(h * 0.82, 9, 0.35, 0.9), Paint()..color = _soften(Color.lerp(bottom, deep, 0.75)!));
    canvas.drawPath(hill(h * 0.9, 6, 0.7, 1.4), Paint()..color = _soften(deep));

    // A few motes rising, fewer when gentle.
    final motes = scene.gentle ? 6 : 12;
    final mr = math.Random(3);
    for (var i = 0; i < motes; i++) {
      final x = mr.nextDouble() * w;
      final prog = (drift * 0.6 + mr.nextDouble()) % 1.0;
      final y = h * (0.95 - prog * 0.8);
      canvas.drawCircle(Offset(x + 6 * math.sin((prog + i) * 2 * math.pi), y), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.5 * math.sin(prog * math.pi)));
    }

    // One small light on the nearest hill for every idea finished, up to eight.
    final lights = math.min(scene.tries, 8);
    for (var i = 0; i < lights; i++) {
      final x = w * (0.1 + 0.8 * (i + 0.5) / 8);
      final y = h * 0.9 - 6 + 4 * math.sin((x / w * 1.4 + 0.7 + drift * 0.5) * 2 * math.pi);
      final glow = 0.75 + 0.25 * math.sin((drift * 3 + i * 0.5) * 2 * math.pi);
      canvas.drawCircle(Offset(x, y), 9, Paint()..color = const Color(0xFFFFD98A).withValues(alpha: 0.28 * glow));
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = const Color(0xFFFFE9B0).withValues(alpha: 0.95));
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.t != t || old.scene != scene;
}
