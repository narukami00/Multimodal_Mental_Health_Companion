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

/// The most recent message of the most recent conversation, as Home shows it.
class RailLastMessage {
  const RailLastMessage({
    required this.text,
    required this.fromUser,
    required this.when,
  });

  final String text;
  final bool fromUser;

  /// Already formatted, e.g. "2h ago".
  final String when;
}

/// Journal and the last conversation: two half-width tiles sitting side by
/// side, each small enough to leave the primary card in charge of the page.
///
/// The journal tile keeps the piling-pages art but puts the count in front of
/// it; the last-chat tile is an animated wash of the app's accent colours over
/// which a single quiet label sits, so tapping it reads as "carry on" rather
/// than opening another block of text.
class HomeRail extends StatelessWidget {
  const HomeRail({
    required this.journalCount,
    this.lastMessage,
    this.onJournal,
    this.onConversations,
    super.key,
  });

  final int journalCount;

  /// Null when there is no conversation yet, which shows an invitation instead.
  final RailLastMessage? lastMessage;

  final VoidCallback? onJournal;
  final VoidCallback? onConversations;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _JournalCard(
            key: const ValueKey('rail-journal'),
            count: journalCount,
            onTap: onJournal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ContinueCard(
            key: const ValueKey('rail-conversations'),
            message: lastMessage,
            onTap: onConversations,
          ),
        ),
      ],
    );
  }
}

/// Drives a looping controller that stays still in tests and when the user has
/// asked the system for reduced motion.
mixin _LoopMixin<T extends StatefulWidget> on State<T>, TickerProvider {
  late final AnimationController loop;

  Duration get loopDuration;

  @override
  void initState() {
    super.initState();
    loop = AnimationController(vsync: this, duration: loopDuration);
    if (!_isTestEnvironment) loop.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isTestEnvironment) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      loop.stop();
      loop.value = 0.62;
    } else if (!loop.isAnimating) {
      loop.repeat();
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Journal
// ---------------------------------------------------------------------------

class _JournalCard extends StatefulWidget {
  const _JournalCard({required this.count, this.onTap, super.key});

  final int count;
  final VoidCallback? onTap;

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard>
    with SingleTickerProviderStateMixin, _LoopMixin<_JournalCard> {
  @override
  Duration get loopDuration => const Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    if (_isTestEnvironment) loop.value = 0.62;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count;
    final label = switch (count) {
      0 => 'Start writing',
      1 => 'one page',
      _ => 'pages',
    };
    return Semantics(
      button: true,
      label: count == 0
          ? 'Journal. No entries yet. Tap to write the first.'
          : 'Journal. $count ${count == 1 ? 'entry' : 'entries'}. Tap to open.',
      child: ExcludeSemantics(
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF4DC), Color(0xFFFFE6BE)],
            ),
            border: Border.all(color: const Color(0x33C2822F)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A8A5A16),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: Stack(
                  children: [
                    // The piling-pages art fills the tile as a backdrop now,
                    // owned by it entirely rather than pushed to a corner.
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _PagesPainter(
                            animation: loop,
                            pages: count.clamp(1, 6),
                          ),
                        ),
                      ),
                    ),
                    // The count sits in front; the art dims behind it so the
                    // number stays readable at every moment of the loop.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            count == 0 ? 'Start writing' : '$count',
                            style: const TextStyle(
                              fontSize: 34,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              color: Color(0xFF4A2F10),
                            ),
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B4A22),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pages piling up across the whole tile, one more for every journal up to six,
/// with a line of handwriting laid down on the topmost and nothing on the rest.
class _PagesPainter extends CustomPainter {
  _PagesPainter({required this.animation, required this.pages})
    : super(repaint: animation);

  final Animation<double> animation;
  final int pages;

  // Where each loose page lies, relative to the art's centre: dx, dy, angle.
  // The last entry is the one in front, which is also the one that is written
  // on, so it is always present and the others fill in behind it.
  static const _slots = [
    (-46.0, 18.0, -0.42),
    (-14.0, -24.0, 0.30),
    (-30.0, 30.0, -0.12),
    (22.0, -16.0, 0.46),
    (28.0, 22.0, -0.28),
    (6.0, 0.0, 0.05),
  ];

  static const _shades = [
    Color(0xFFF1D29A),
    Color(0xFFF6DEB0),
    Color(0xFFF9E7C2),
    Color(0xFFF4D9A6),
    Color(0xFFFAEACB),
    Color(0xFFFFFCF2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final sway = math.sin(t * 2 * math.pi) * 0.012;
    final base = Offset(size.width * 0.68, size.height * 0.38);

    // Warm sun behind the pages.
    canvas.drawCircle(
      base,
      64,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x59FFC24F), Color(0x00FFC24F)],
        ).createShader(Rect.fromCircle(center: base, radius: 64)),
    );

    const pageW = 44.0;
    const pageH = 58.0;
    final behind = pages - 1;
    // Background slots, then the front page last.
    final order = [for (var i = 0; i < behind; i++) i, _slots.length - 1];
    for (final i in order) {
      final isTop = i == _slots.length - 1;
      final (dx, dy, angle) = _slots[i];
      canvas.save();
      canvas.translate(base.dx + dx, base.dy + dy);
      canvas.rotate(angle + sway * (i + 1));
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: pageW, height: pageH),
        const Radius.circular(6),
      );
      canvas.drawShadow(
        Path()..addRRect(rect),
        const Color(0xFF6B4A22),
        3,
        false,
      );
      canvas.drawRRect(rect, Paint()..color = _shades[i]);
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x22A0661A),
      );
      if (isTop) _writing(canvas, t, pageW, pageH);
      canvas.restore();
    }
  }

  void _writing(Canvas canvas, double t, double w, double h) {
    // Writing runs for the first 70% of the loop, holds, then fades.
    final progress = (t / 0.7).clamp(0.0, 1.0);
    final fade = t > 0.88 ? ((1 - t) / 0.12).clamp(0.0, 1.0) : 1.0;
    const lines = 5;
    final left = -w / 2 + 8;
    final right = w / 2 - 8;
    final top = -h / 2 + 12;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6
      ..color = const Color(0xFFC2622F).withValues(alpha: 0.75 * fade);
    Offset? tip;
    for (var i = 0; i < lines; i++) {
      final lineProgress = (progress * lines - i).clamp(0.0, 1.0);
      if (lineProgress <= 0) continue;
      // Last line is shorter, like the end of a paragraph.
      final end = i == lines - 1 ? left + (right - left) * 0.55 : right;
      final y = top + i * 9.0;
      final path = Path()..moveTo(left, y);
      const step = 4.0;
      for (var x = left + step; x <= end; x += step) {
        path.lineTo(x, y + math.sin((x - left) * 0.9 + i) * 1.5);
      }
      final metric = path.computeMetrics().first;
      final len = metric.length * lineProgress;
      canvas.drawPath(metric.extractPath(0, len), pen);
      if (lineProgress < 1.0 || i == lines - 1) {
        tip = metric.getTangentForOffset(len)?.position;
      }
    }
    if (tip != null && progress < 1.0) {
      canvas.drawCircle(
        tip,
        3.0,
        Paint()..color = const Color(0xFFE86034).withValues(alpha: 0.9 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PagesPainter old) => old.pages != pages;
}

// ---------------------------------------------------------------------------
// Last chat
// ---------------------------------------------------------------------------

class _ContinueCard extends StatefulWidget {
  const _ContinueCard({this.message, this.onTap, super.key});

  final RailLastMessage? message;
  final VoidCallback? onTap;

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard>
    with TickerProviderStateMixin, _LoopMixin<_ContinueCard> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 6000);

  // The fluid: a chain of points chasing the pointer through real spring
  // physics. The head follows the finger, each later point follows the one in
  // front, so a fast drag makes the blob lag, stretch and swing like liquid,
  // and a flick-and-release throws it with momentum that glides to a stop.
  final List<_FluidPoint> _fluid = List.generate(
    _WashPainter.trailLength,
    (i) => _FluidPoint(),
  );
  late final AnimationController _fluidTicker;

  @override
  void initState() {
    super.initState();
    _fluidTicker = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    );
    _fluidTicker.addListener(_stepFluid);
  }

  @override
  void dispose() {
    _fluidTicker
      ..removeListener(_stepFluid)
      ..dispose();
    super.dispose();
  }

  void _ensureTicker() {
    if (_fluidTicker.isAnimating || _isTestEnvironment) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _fluidTicker.repeat();
  }

  void _onPointerDown(PointerDownEvent e) {
    // The pool appears under the finger: the head snaps there and the rest of
    // the chain gathers, instead of flying in from wherever it last rested.
    for (final p in _fluid) {
      p
        ..visible = true
        ..pos = e.localPosition
        ..vel = Offset.zero;
    }
    _pointer = e.localPosition;
    _ensureTicker();
  }

  void _onPointerMove(PointerMoveEvent e) {
    _pointer = e.localPosition;
    // A hover alone should not keep the sim alive; only a touch steers it,
    // so hovering lights nothing up until the finger lands.
    _ensureTicker();
  }

  void _onPointerUp(PointerEvent e) {
    // Finger gone: nothing pulls any more, so the chain glides on its own
    // momentum until damping brings it to rest, and the sim then sleeps.
    _pointer = null;
  }

  Offset? _pointer;

  /// Steps the chain: each point chases the one in front through a spring,
  /// sub-stepped so the physics run at a rate independent of the display's
  /// refresh rate — the same motion on a 60 or a 120 Hz screen.
  void _stepFluid() {
    const steps = 2;
    const dt = 1 / 120.0;
    const stiffness = 110.0;
    const damping = 13.0;

    var energy = 0.0;
    for (var s = 0; s < steps; s++) {
      Offset leader = _fluid.first.pos;
      final target = _pointer;
      if (target != null) leader = target;
      for (final p in _fluid) {
        final force = (leader - p.pos) * stiffness * dt;
        p
          ..vel = (p.vel + force) * (1 - damping * dt)
          ..pos += p.vel * dt * 60;
        leader = p.pos;
        energy += p.vel.distance;
      }
    }

    // Asleep once the pointer has left and everything has come to rest; the
    // next touch wakes the chain where the finger lands.
    if (_pointer == null && energy < 0.6) {
      for (final p in _fluid) {
        p.visible = false;
      }
      _fluidTicker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final hasThread = message != null;

    return Semantics(
      button: true,
      label: hasThread
          ? 'Continue your last conversation. '
                '${message.fromUser ? 'You' : 'Sol'} said: ${message.text}'
          : 'Start a conversation with Sol.',
      child: ExcludeSemantics(
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x336A63A8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x146A63A8),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Material(
              color: Colors.transparent,
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                child: InkWell(
                  onTap: widget.onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Two accent blobs drifting over a cool surface: the
                      // animation lives in the colours, so the tile stays quiet
                      // about content and never generically icon-like.
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: _WashPainter(
                            animation: loop,
                            fluid: _fluid,
                            repaintNotifier: _fluidTicker,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LAST CHAT',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                                color: Color(0xFF4A4470),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hasThread ? message.when : 'Start one',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2F2A55),
                              ),
                            ),
                            Text(
                              hasThread ? 'Tap to pick it back up' : 'with Sol',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4A4470),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// A slow wash of the app's accent colours that never repeats visibly: each
/// blob wanders its own ellipse on its own phase, so the pair does not meet in
/// the same arrangement twice in any short stretch.
///
/// Over that wash the pointer-driven fluid chain is drawn whenever the finger
/// is on the tile: deeper, more saturated versions of the same accents that
/// pool under the finger and bleed along its path through spring physics.
class _WashPainter extends CustomPainter {
  _WashPainter({
    required this.animation,
    required this.fluid,
    required Listenable repaintNotifier,
  }) : super(repaint: Listenable.merge([animation, repaintNotifier]));

  final Animation<double> animation;
  final List<_FluidPoint> fluid;

  /// How many points chase the finger. More reads softer and more liquid
  /// and costs more per frame; twelve cover a half-width tile generously.
  static const trailLength = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;

    // Cool surface the accents wash over.
    final surface = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0xFFF3F0FA), Color(0xFFE7E1F6)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, surface);

    // Each accent blob wanders its own ellipse on its own speed, so the wash
    // never repeats visibly and never lands on the same arrangement twice.
    final w = size.width;
    final blobs =
        <({double r, Offset anchor, Offset wander, double speed, Color color})>[
          (
            r: 0.62 * w,
            anchor: Offset(0.30 * w, 0.36 * w),
            wander: Offset(0.30 * w, 0.22 * w),
            speed: 1.0,
            color: const Color(0x66FFB534),
          ),
          (
            r: 0.56 * w,
            anchor: Offset(0.74 * w, 0.66 * w),
            wander: Offset(0.24 * w, 0.30 * w),
            speed: 1.3,
            color: const Color(0x59FF7F50),
          ),
          (
            r: 0.50 * w,
            anchor: Offset(0.18 * w, 0.78 * w),
            wander: Offset(0.30 * w, 0.18 * w),
            speed: 2.1,
            color: const Color(0x4D6A63A8),
          ),
        ];
    for (final (:r, :anchor, :wander, :speed, :color) in blobs) {
      final angle = t * 2 * math.pi * speed;
      final center = Offset(
        anchor.dx + math.cos(angle) * wander.dx,
        anchor.dy + math.sin(angle * 2) * wander.dy,
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    _paintFluid(canvas, w);
  }

  /// The pointer trail: deep accent pools that melt into one another. Each
  /// point paints a radial gradient over its neighbour (the head is warmest
  /// and tightest, the tail coolest and widest), so the chain reads as one
  /// continuous liquid streak rather than a row of circles.
  void _paintFluid(Canvas canvas, double w) {
    final living = fluid.where((p) => p.visible || p.vel.distance > 8).toList();
    if (living.isEmpty) return;

    const headColor = Color(0xE6FF7F50);
    const midColor = Color(0xD9FFB534);
    const tailColor = Color(0x8C6A63A8);

    for (final (i, p) in living.indexed) {
      final fade = p.visible ? 1.0 : (1 - (i / living.length)).clamp(0.0, 1.0);
      final t = i / (living.length - 1).clamp(1, 1 << 30);
      final speed = p.vel.distance.clamp(0.0, 1200.0);
      // Velocity stretches the blob along its motion: fast digs a streak,
      // slow pools a round drop.
      final stretch = 1 + speed / 900.0;
      final radius = w * (0.16 + 0.10 * (1 - t)) * stretch;
      final color = Color.lerp(
        headColor,
        midColor,
        t * 0.6,
      )!.withValues(alpha: (1 - t * 0.75) * fade);
      canvas.drawCircle(
        p.pos,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: p.pos, radius: radius)),
      );
    }
    // And a soft indigo under-glow beneath the head, tying the trail into the
    // card's own cool surface.
    final head = living.first;
    final glow = tailColor.withValues(alpha: 0.5);
    canvas.drawCircle(
      head.pos,
      w * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [glow, glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: head.pos, radius: w * 0.34)),
    );
  }

  @override
  bool shouldRepaint(covariant _WashPainter old) => false;
}

/// One point of the pointer-trail: position, velocity, and whether it is
/// currently on screen. `_FluidPoint.new` is used as the generator function
/// when the chain is built.
class _FluidPoint {
  _FluidPoint() : pos = Offset.zero, vel = Offset.zero, visible = false;

  Offset pos;
  Offset vel;
  bool visible;
}
