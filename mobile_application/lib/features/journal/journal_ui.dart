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

/// Whether the journaling pages should hold still: the person asked their phone for less motion, or this is
/// a test (a loop never settles).
bool journalMotionOff(BuildContext context) => _isTestEnvironment || (MediaQuery.maybeOf(context)?.disableAnimations ?? false);

const journalInk = Color(0xFF3A3125);
const journalSoft = Color(0xFF8A7A61);

/// The warm colours behind a journaling page. Each way of journaling has its own mood, but they belong together.
enum JournalTint {
  text(Color(0xFFFFB534), Color(0xFFFF7F50), [Color(0xFFFDF8EC), Color(0xFFFBF3E4), Color(0xFFFBEFE3)]),
  voice(Color(0xFFFF9A6A), Color(0xFFF08FA0), [Color(0xFFFFF6EE), Color(0xFFFFEDE2), Color(0xFFFCE5E3)]),
  video(Color(0xFFFFB86B), Color(0xFFB79AD6), [Color(0xFFFFF7EA), Color(0xFFFDF0E6), Color(0xFFF4EAF2)]);

  const JournalTint(this.glowA, this.glowB, this.base);

  final Color glowA;
  final Color glowB;
  final List<Color> base;
}

/// A soft gradient with two slow, drifting glows and a few specks of light. It only moves when motion is on.
class JournalBackdrop extends StatefulWidget {
  const JournalBackdrop({required this.tint, required this.child, super.key});

  final JournalTint tint;
  final Widget child;

  @override
  State<JournalBackdrop> createState() => _JournalBackdropState();
}

class _JournalBackdropState extends State<JournalBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 28));
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final off = journalMotionOff(context);
    if (!off && !_running) {
      _loop.repeat();
      _running = true;
    } else if (off && _running) {
      _loop.stop();
      _running = false;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: tint.base),
          ),
        ),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => CustomPaint(painter: _BackdropPainter(tint, _loop.value)),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.tint, this.t);

  final JournalTint tint;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    double s(double x) => math.sin(x * 2 * math.pi);
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(w * (0.95 + 0.05 * s(t)), h * (0.02 + 0.03 * s(t + 0.25))), 190, tint.glowA.withValues(alpha: 0.32));
    glow(Offset(w * (0.04 + 0.05 * s(t + 0.5)), h * (0.98 + 0.03 * s(t + 0.75))), 210, tint.glowB.withValues(alpha: 0.26));
    glow(Offset(w * (0.55 + 0.08 * s(t + 0.1)), h * (0.42 + 0.05 * s(t + 0.6))), 150, tint.glowA.withValues(alpha: 0.10));

    // A few specks of light, rising very slowly.
    final r = math.Random(5);
    for (var i = 0; i < 14; i++) {
      final x = r.nextDouble() * w;
      final p = (t * 0.8 + r.nextDouble()) % 1.0;
      final y = h * (1.02 - p * 1.04);
      canvas.drawCircle(Offset(x + 8 * s(p + i * 0.13), y), 1.4 + r.nextDouble() * 1.2, Paint()..color = Colors.white.withValues(alpha: 0.6 * math.sin(p * math.pi)));
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => old.t != t || old.tint != tint;
}

/// Sentence starters for the text page: tapping one begins the entry, which is often the hardest part.
List<String> sentenceStarters(int hour) {
  final lead = hour < 12
      ? 'Today I hope…'
      : hour < 18
      ? 'So far today…'
      : 'Today, I…';
  return [lead, 'Right now I feel…', 'Something that stayed with me…', "I'm grateful for…", 'What I need most is…', 'One small win…'];
}

/// What the voice and video pages gently suggest talking about before the person begins.
const talkPrompts = [
  "What's one thing that stayed with you today?",
  'What are you carrying right now?',
  'What made you smile, even a little?',
  'What would make tomorrow feel lighter?',
  'What do you want to let go of?',
  'Who or what are you glad you have?',
];

/// A short encouraging line for a recording that is going on. Never urgent: it never hurries the person up
/// and never says how long is long enough.
String encouragement({required int seconds, required bool faceTrouble}) {
  if (faceTrouble) return "Can't see your face clearly. Move a little closer to the light.";
  if (seconds < 12) return "I'm listening. Take your time.";
  if (seconds < 45) return "You're doing really well.";
  if (seconds < 100) return 'Say as much or as little as you like.';
  if (seconds < 150) return 'Whenever you feel done, tap stop.';
  return "That's a lot to hold. Wrap up whenever you're ready.";
}

/// A single line that fades from one prompt to the next, slowly.
class TalkPromptLine extends StatefulWidget {
  const TalkPromptLine({super.key});

  @override
  State<TalkPromptLine> createState() => _TalkPromptLineState();
}

class _TalkPromptLineState extends State<TalkPromptLine> {
  int _index = DateTime.now().minute % talkPrompts.length;
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!journalMotionOff(context) && !_running) {
      _running = true;
      _tick();
    }
  }

  Future<void> _tick() async {
    while (mounted && _running) {
      await Future<void>.delayed(const Duration(seconds: 7));
      if (!mounted) return;
      setState(() => _index = (_index + 1) % talkPrompts.length);
    }
  }

  @override
  void dispose() {
    _running = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'YOU COULD START WITH',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: journalSoft),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          child: Text(
            talkPrompts[_index],
            key: ValueKey(_index),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w700, color: journalInk),
          ),
        ),
      ],
    );
  }
}

/// The voice stage: a warm orb that breathes while idle and swells and ripples with the voice while recording.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({required this.recording, required this.level, super.key});

  final bool recording;

  /// 0 to 1, how loud the voice is right now.
  final double level;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final off = journalMotionOff(context);
    if (!off && !_running) {
      _loop.repeat();
      _running = true;
    } else if (off && _running) {
      _loop.stop();
      _running = false;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: widget.level),
              duration: const Duration(milliseconds: 140),
              builder: (context, level, _) => AnimatedBuilder(
                animation: _loop,
                builder: (context, _) => CustomPaint(
                  size: const Size(300, 300),
                  painter: _OrbPainter(recording: widget.recording, level: level, t: _loop.value),
                ),
              ),
            ),
          ),
          Icon(widget.recording ? Icons.graphic_eq_rounded : Icons.mic_rounded, size: 46, color: Colors.white),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.recording, required this.level, required this.t});

  final bool recording;
  final double level;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    double s(double x) => math.sin(x * 2 * math.pi);
    final core = 62 + (recording ? 34 * level : 4 * s(t));
    final hot = recording ? const Color(0xFFFF8A5C) : const Color(0xFFFFC16B);
    const warm = Color(0xFFFFB534);

    // Ripples going outwards, faster and stronger when recording.
    final rings = recording ? 4 : 3;
    for (var i = 0; i < rings; i++) {
      final p = (t * (recording ? 1.0 : 0.5) + i / rings) % 1.0;
      final r = core + 14 + p * (recording ? 70 + 40 * level : 54);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = hot.withValues(alpha: (recording ? 0.34 : 0.22) * (1 - p)),
      );
    }

    // The glow.
    canvas.drawCircle(
      c,
      core * 1.9,
      Paint()..shader = RadialGradient(colors: [hot.withValues(alpha: 0.42), hot.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: core * 1.9)),
    );

    // The orb.
    canvas.drawCircle(
      c,
      core,
      Paint()..shader = RadialGradient(center: const Alignment(-0.3, -0.35), colors: [const Color(0xFFFFE7B8), hot, warm]).createShader(Rect.fromCircle(center: c, radius: core)),
    );
    canvas.drawCircle(c + Offset(-core * 0.3, -core * 0.38), core * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.28));

    // Sparks orbiting slowly.
    for (var i = 0; i < 6; i++) {
      final a = (i / 6 + t * (recording ? 0.6 : 0.25)) * 2 * math.pi;
      final r = core + 34 + 6 * s(t * 2 + i * 0.3);
      canvas.drawCircle(c + Offset(math.cos(a) * r, math.sin(a) * r), 2.2, Paint()..color = Colors.white.withValues(alpha: 0.7));
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.t != t || old.level != level || old.recording != recording;
}

/// Three dots that rise and fall in turn, for a short wait.
class SoftDots extends StatefulWidget {
  const SoftDots({super.key});

  @override
  State<SoftDots> createState() => _SoftDotsState();
}

class _SoftDotsState extends State<SoftDots> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!journalMotionOff(context) && !_running) {
      _loop.repeat();
      _running = true;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.translate(
                offset: Offset(0, -7 * math.max(0, math.sin((_loop.value - i * 0.16) * 2 * math.pi))),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFB534)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A check that settles into place, for when an entry has been kept.
class SettleCheck extends StatelessWidget {
  const SettleCheck({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: journalMotionOff(context) ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v.clamp(0.0, 1.2), child: child),
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFFFFB534), Color(0xFFFF8F5A)]),
          boxShadow: [BoxShadow(color: Color(0x55FF8F5A), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: const Icon(Icons.check_rounded, size: 34, color: Colors.white),
      ),
    );
  }
}
