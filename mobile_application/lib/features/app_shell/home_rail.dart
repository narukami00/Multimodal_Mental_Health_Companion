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

/// Journal and conversations: two cards, each saying something about its
/// contents rather than naming a destination.
///
/// The journal card draws its own stack of pages that fills in as you add
/// entries; the conversation card is a preview of where you left off, so
/// tapping it reads as "carry on" rather than "open a list".
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JournalCard(
          key: const ValueKey('rail-journal'),
          count: journalCount,
          onTap: onJournal,
        ),
        const SizedBox(height: 14),
        _ContinueCard(
          key: const ValueKey('rail-conversations'),
          message: lastMessage,
          onTap: onConversations,
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
      0 => 'Your first page is waiting',
      1 => 'page of you, written down',
      _ => 'pages of you, written down',
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 150, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'JOURNAL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8,
                              color: Color(0xFF9A5B14),
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (count > 0)
                            Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 44,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5,
                                color: Color(0xFF4A2F10),
                              ),
                            ),
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: count == 0 ? 18 : 12.5,
                              height: 1.25,
                              fontWeight: count == 0
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              letterSpacing: count == 0 ? -0.3 : 0,
                              color: const Color(0xFF6B4A22),
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

/// Pages scattered across the card, one more for every journal up to six, with
/// a line of handwriting laid down on the topmost and nothing on the rest.
class _PagesPainter extends CustomPainter {
  _PagesPainter({required this.animation, required this.pages})
    : super(repaint: animation);

  final Animation<double> animation;
  final int pages;

  // Where each loose page lies, relative to the art's centre: dx, dy, angle.
  // The last entry is the one in front, which is also the one that is written
  // on, so it is always present and the others fill in behind it.
  static const _slots = [
    (-58.0, 12.0, -0.46),
    (-20.0, -22.0, 0.34),
    (-34.0, 26.0, -0.14),
    (24.0, -14.0, 0.50),
    (26.0, 24.0, -0.30),
    (0.0, 0.0, 0.05),
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
    final base = Offset(size.width - 66, size.height * 0.44);

    // Warm sun behind the pages.
    canvas.drawCircle(
      base,
      78,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x66FFC24F), Color(0x00FFC24F)],
        ).createShader(Rect.fromCircle(center: base, radius: 78)),
    );

    const pageW = 54.0;
    const pageH = 72.0;
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
        const Radius.circular(7),
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
    final left = -w / 2 + 9;
    final right = w / 2 - 9;
    final top = -h / 2 + 14;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8
      ..color = const Color(0xFFC2622F).withValues(alpha: 0.75 * fade);
    Offset? tip;
    for (var i = 0; i < lines; i++) {
      final lineProgress = (progress * lines - i).clamp(0.0, 1.0);
      if (lineProgress <= 0) continue;
      // Last line is shorter, like the end of a paragraph.
      final end = i == lines - 1 ? left + (right - left) * 0.55 : right;
      final y = top + i * 10.0;
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
        3.2,
        Paint()..color = const Color(0xFFE86034).withValues(alpha: 0.9 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PagesPainter old) => old.pages != pages;
}

// ---------------------------------------------------------------------------
// Continue conversation
// ---------------------------------------------------------------------------

class _ContinueCard extends StatefulWidget {
  const _ContinueCard({this.message, this.onTap, super.key});

  final RailLastMessage? message;
  final VoidCallback? onTap;

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard>
    with SingleTickerProviderStateMixin, _LoopMixin<_ContinueCard> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 2400);

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final hasMessage = message != null && message.text.isNotEmpty;
    final fromUser = message?.fromUser ?? false;

    return Semantics(
      button: true,
      label: hasMessage
          ? 'Continue your last conversation. '
                '${fromUser ? 'You' : 'Sol'} said: ${message.text}'
          : 'Start a conversation with Sol.',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6F2FF), Color(0xFFE9E3FA)],
            ),
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
              child: InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // A live dot, so the card feels like an open thread.
                          AnimatedBuilder(
                            animation: loop,
                            builder: (context, _) {
                              final pulse = Curves.easeInOut.transform(
                                (math.sin(loop.value * 2 * math.pi) + 1) / 2,
                              );
                              return Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF6A63A8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF6A63A8,
                                      ).withValues(alpha: 0.35 * pulse),
                                      blurRadius: 3 + 6 * pulse,
                                      spreadRadius: 1 + 2 * pulse,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hasMessage
                                  ? 'Continue your last conversation'
                                  : 'Talk it through with Sol',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: Color(0xFF2F2A55),
                              ),
                            ),
                          ),
                          const Text(
                            '→',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF6A63A8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _Bubble(
                        fromUser: fromUser,
                        child: hasMessage
                            ? Text(
                                message.text,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: fromUser
                                      ? const Color(0xFFFFFFFF)
                                      : const Color(0xFF3A3560),
                                ),
                              )
                            : const Text(
                                'A quiet, private space to speak or write '
                                'whatever is on your mind.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF3A3560),
                                ),
                              ),
                      ),
                      if (hasMessage) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: fromUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '${fromUser ? 'You' : 'Sol'} · ${message.when}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B6690),
                              ),
                            ),
                          ),
                        ),
                      ],
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

/// A chat bubble whose small square corner points at whoever spoke, so a quick
/// glance tells you whether you or Sol had the last word.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.child});

  final bool fromUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const big = Radius.circular(18);
    const small = Radius.circular(5);
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: big,
            topRight: big,
            bottomLeft: fromUser ? big : small,
            bottomRight: fromUser ? small : big,
          ),
          gradient: fromUser
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7D75C2), Color(0xFF5E579D)],
                )
              : null,
          color: fromUser ? null : Colors.white.withValues(alpha: 0.85),
        ),
        child: child,
      ),
    );
  }
}
