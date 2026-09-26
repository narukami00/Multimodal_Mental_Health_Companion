import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/home/home_card_priority.dart';
import '../chat/chat_controller.dart';
import '../chat/conversation_history.dart';
import 'living_atmosphere_card.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({
    this.primaryCard = HomeCardType.checkIn,
    this.currentTime,
    this.chatController,
    this.onStartCheckIn,
    this.onOpenSupport,
    this.onOpenChat,
    this.onStartNewChat,
    this.onOpenCall,
    super.key,
  });

  final HomeCardType primaryCard;
  final DateTime? currentTime;
  final ChatController? chatController;
  final VoidCallback? onStartCheckIn;
  final VoidCallback? onOpenSupport;
  final VoidCallback? onOpenChat;
  final VoidCallback? onStartNewChat;
  final VoidCallback? onOpenCall;

  static String greetingForHour(int hour) {
    if (hour < 5) return 'Still awake';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final now = currentTime ?? DateTime.now();
    final greeting = greetingForHour(now.hour);
    final date = MaterialLocalizations.of(context).formatMediumDate(now);
    final card = _PrimaryCardContent.fromType(primaryCard);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFEFCE8),
        gradient: RadialGradient(
          center: Alignment(0.88, -0.6),
          radius: 1.3,
          colors: [
            Color(0x4DFFD07A),
            Color(0x1AFF7F50),
            Color(0xFFFEFCE8),
          ],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          children: [
            Text(
              greeting,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF4A3728),
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              date,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF7B6A55),
                  ),
            ),
            const SizedBox(height: 18),
            _buildPrimaryCard(card),
            const SizedBox(height: 14),
            _buildSolCompanionHub(context),
            const SizedBox(height: 18),
            const LivingAtmosphereCard(),
            const SizedBox(height: 24),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryCard(_PrimaryCardContent card) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: const Alignment(-0.6, -1.0),
          end: const Alignment(0.8, 1.0),
          colors: card.gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: card.shadowColor,
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            const Positioned.fill(
              child: _AnimatedSpinningSun(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: card.foregroundColor.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        card.eyebrow,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                          color: card.foregroundColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    card.title,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: card.foregroundColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    card.subtitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: card.foregroundColor.withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: onStartCheckIn,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 9, 10, 9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFFFFEF7),
                            Color(0xFFFFF6DE),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3B78460A),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            card.action,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: card.ctaTextColor,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFFC24F),
                                  Color(0xFFFF9F45),
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x40A05A0A),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              card.icon,
                              size: 16,
                              color: const Color(0xFFFFFDF3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openChatFromPrompt() {
    final active = chatController?.activeConversation;
    if (active != null && active.messages.any((m) => m.isUser)) {
      onStartNewChat?.call();
    } else {
      onOpenChat?.call();
    }
  }

  void _openHistorySheet(BuildContext context) {
    ConversationHistorySheet.show(
      context,
      chatController: chatController,
      activeThreadId: null,
      onSelectThread: (thread) {
        chatController?.switchConversation(thread.id);
        onOpenChat?.call();
      },
      onNewConversation: () {
        chatController?.startNewConversation();
        onOpenChat?.call();
      },
      onDeleteThread: (id) {
        chatController?.deleteConversation(id);
      },
    );
  }

  Widget _buildSolCompanionHub(BuildContext context) {
    if (chatController != null) {
      return AnimatedBuilder(
        animation: chatController!,
        builder: (context, _) => _buildCompanionCard(context),
      );
    }
    return _buildCompanionCard(context);
  }

  Widget _buildCompanionCard(BuildContext context) {
    final now = currentTime ?? DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final convs = chatController?.conversations ?? const [];
    final hasHistory = convs.isNotEmpty;
    final activeConv = chatController?.activeConversation != null &&
            chatController!.activeConversation!.hasUserMessage
        ? chatController!.activeConversation!
        : (hasHistory ? convs.first : null);
    final excerpt = activeConv?.preview;
    final meta = activeConv != null ? '${activeConv.dateStr} · Recent' : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF5FFFDF8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0x38FFB534),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C784614),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              if (activeConv != null) {
                chatController?.switchConversation(activeConv.id);
                onOpenChat?.call();
              } else {
                _openChatFromPrompt();
              }
            },
            child: Stack(
              children: [
                const Positioned(
                  left: -30,
                  top: -40,
                  width: 140,
                  height: 140,
                  child: _BreathingGlow(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Row: Eyebrow + dynamic trailing info
                      Row(
                        children: [
                          const _Eyebrow('SOL · COMPANION'),
                          const Spacer(),
                          if (hasHistory)
                            InkWell(
                              onTap: () => _openHistorySheet(context),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.history_rounded,
                                      size: 13,
                                      color: Color(0xFFB08A5E),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${convs.length} ${convs.length == 1 ? 'reflection' : 'reflections'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                        color: Color(0xFFB08A5E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _LivingAudioWaveform(),
                                const SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFA5937C),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Core Interactive Row: Living Orb + Content + Primary Action
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const _LivingCompanionOrb(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: hasHistory && excerpt != null
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Talk it through',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                          color: Color(0xFF3E2818),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '“$excerpt”',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          fontStyle: FontStyle.italic,
                                          color: Color(0xFF6B533E),
                                        ),
                                      ),
                                      if (meta != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          meta,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFA5937C),
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                : const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Talk it through',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                          color: Color(0xFF3E2818),
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'A quiet, private space to speak or write whatever is on your mind right now.',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.3,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF7B6A55),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(width: 10),
                          // Tactical Action Button
                          if (hasHistory)
                            _SolPillButton(
                              label: 'Resume',
                              icon: Icons.arrow_forward_rounded,
                              isPrimary: true,
                              onTap: () {
                                if (activeConv != null) {
                                  chatController
                                      ?.switchConversation(activeConv.id);
                                }
                                onOpenChat?.call();
                              },
                            )
                          else
                            _SolPillButton(
                              label: 'Open chat',
                              icon: Icons.arrow_forward_rounded,
                              isPrimary: true,
                              onTap: _openChatFromPrompt,
                            ),
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

  Widget _buildFooter(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x14FFB534),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wb_sunny_rounded,
                  size: 14,
                  color: Color(0xFFE8961A),
                ),
                SizedBox(width: 6),
                Text(
                  '4 days present · no pressure',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7B6A55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your pace is enough for today.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA5937C),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onOpenSupport,
            icon: const Icon(
              Icons.shield_outlined,
              size: 16,
              color: Color(0xB87B6A55),
            ),
            label: const Text(
              'Support resources',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xB87B6A55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSpinningSun extends StatefulWidget {
  const _AnimatedSpinningSun();

  @override
  State<_AnimatedSpinningSun> createState() => _AnimatedSpinningSunState();
}

class _AnimatedSpinningSunState extends State<_AnimatedSpinningSun>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );
    if (!_isTestEnvironment) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _CardPetalPainter(
            rotationAngle: _controller.value * 2 * math.pi,
          ),
        );
      },
    );
  }
}

class _CardPetalPainter extends CustomPainter {
  const _CardPetalPainter({this.rotationAngle = 0.0});

  final double rotationAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 24, 24);
    final paintFill = Paint()
      ..color = const Color(0x40FFFDF0)
      ..style = PaintingStyle.fill;
    final paintStroke = Paint()
      ..color = const Color(0x55FFFDF0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    canvas.drawCircle(center, 78, paintStroke);
    canvas.drawCircle(center, 58, paintStroke);
    canvas.drawCircle(center, 40, paintFill);
    canvas.drawCircle(center, 26, paintFill);

    for (var i = 0; i < 8; i++) {
      final angle = (i * 45) * 3.141592653589793 / 180 + rotationAngle;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final petalRect = Rect.fromCenter(
        center: const Offset(0, -66),
        width: 22,
        height: 48,
      );
      canvas.drawOval(petalRect, paintFill);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CardPetalPainter oldDelegate) =>
      oldDelegate.rotationAngle != rotationAngle;
}

class _BreathingGlow extends StatefulWidget {
  const _BreathingGlow();

  @override
  State<_BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<_BreathingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (!_isTestEnvironment) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ponytail: reduced-motion check needs an inherited lookup, so it lives here
    if (!_isTestEnvironment && MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.isAnimating) {
      return _glow(0.75, 1.0);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _glow(
        0.55 + 0.40 * Curves.easeInOutSine.transform(_c.value),
        0.96 + 0.10 * _c.value,
      ),
    );
  }

  Widget _glow(double opacity, double scale) => Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: const [
                  Color(0x57FFB534),
                  Color(0x00FFB534),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

class _LivingAudioWaveform extends StatefulWidget {
  const _LivingAudioWaveform();

  @override
  State<_LivingAudioWaveform> createState() => _LivingAudioWaveformState();
}

class _LivingAudioWaveformState extends State<_LivingAudioWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (!_isTestEnvironment) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isTestEnvironment && MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAnimating) {
      return _buildStaticWave();
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _bar(5.0 + 4.0 * math.sin(t)),
            const SizedBox(width: 2.5),
            _bar(7.0 + 7.0 * math.sin(t + 1.2)),
            const SizedBox(width: 2.5),
            _bar(6.0 + 6.0 * math.sin(t + 2.4)),
            const SizedBox(width: 2.5),
            _bar(4.0 + 4.0 * math.sin(t + 3.6)),
          ],
        );
      },
    );
  }

  Widget _buildStaticWave() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _bar(7.0),
        const SizedBox(width: 2.5),
        _bar(13.0),
        const SizedBox(width: 2.5),
        _bar(10.0),
        const SizedBox(width: 2.5),
        _bar(6.0),
      ],
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 2.5,
      height: height.clamp(3.5, 16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xFFE86034),
            Color(0xFFFFB534),
          ],
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Color(0xFFC2622F),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: Color(0xFFC2622F),
          ),
        ),
      ],
    );
  }
}

class _TextCta extends StatefulWidget {
  const _TextCta(this.label, {required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_TextCta> createState() => _TextCtaState();
}

class _TextCtaState extends State<_TextCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
      color: Color(0xFFE86034),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.label, style: style),
            const SizedBox(width: 6),
            // typographic arrow, NOT Icon; nudges 4px right while pressed
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_pressed ? 4 : 0, 0, 0),
              child: const Text('→', style: style),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryCardContent {
  const _PrimaryCardContent({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.icon,
    this.gradientColors = const [
      Color(0xFFFFD07A),
      Color(0xFFFFB534),
      Color(0xFFFFA446),
    ],
    this.shadowColor = const Color(0x55E28C1E),
    this.foregroundColor = const Color(0xFF55350F),
    this.ctaTextColor = const Color(0xFFB0680C),
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String action;
  final IconData icon;
  final List<Color> gradientColors;
  final Color shadowColor;
  final Color foregroundColor;
  final Color ctaTextColor;

  factory _PrimaryCardContent.fromType(HomeCardType type) {
    return switch (type) {
      HomeCardType.support => const _PrimaryCardContent(
          eyebrow: 'SUPPORT AVAILABLE',
          title: 'Support is\nhere when needed',
          subtitle: 'You do not have to figure out the next moment alone.',
          action: 'View support',
          icon: Icons.favorite_rounded,
          gradientColors: [
            Color(0xFFFF9E7A),
            Color(0xFFFF7F50),
            Color(0xFFE86034),
          ],
          shadowColor: Color(0x55E86034),
          foregroundColor: Colors.white,
          ctaTextColor: Color(0xFFD64D20),
        ),
      HomeCardType.checkIn => const _PrimaryCardContent(
          eyebrow: 'DAILY CHECK-IN',
          title: 'How does your mind\nfeel right now?',
          subtitle: 'A calm 2-minute space to notice where you are.',
          action: 'Check in now',
          icon: Icons.arrow_forward_rounded,
        ),
      HomeCardType.onboarding => const _PrimaryCardContent(
          eyebrow: 'GETTING STARTED',
          title: 'Make Solace\nfeel more like you',
          subtitle: 'A few gentle choices help shape what you see here.',
          action: 'Continue setup',
          icon: Icons.arrow_forward_rounded,
        ),
      HomeCardType.suggestion => const _PrimaryCardContent(
          eyebrow: 'GENTLE SUGGESTION',
          title: 'A gentle idea\nfor today',
          subtitle: 'Something small, offered without pressure.',
          action: 'See the idea',
          icon: Icons.arrow_forward_rounded,
        ),
      HomeCardType.defaultAction => const _PrimaryCardContent(
          eyebrow: 'SPACE TO REFLECT',
          title: 'What feels present\nright now?',
          subtitle: 'Open a journal or conversation whenever you are ready.',
          action: 'Open journal',
          icon: Icons.arrow_forward_rounded,
        ),
    };
  }
}

class _LivingCompanionOrb extends StatefulWidget {
  const _LivingCompanionOrb();

  @override
  State<_LivingCompanionOrb> createState() => _LivingCompanionOrbState();
}

class _LivingCompanionOrbState extends State<_LivingCompanionOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );
  late final Animation<double> _pulse = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    if (!_isTestEnvironment) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final t = _pulse.value;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Ambient warm breathing glow
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB534)
                        .withValues(alpha: 0.25 + 0.20 * t),
                    blurRadius: 10 + 6 * t,
                    spreadRadius: 1 + 1.5 * t,
                  ),
                ],
              ),
            ),
            // Luminous golden sun-drop orb with gentle breathing scale
            Transform.scale(
              scale: 1.0 + 0.05 * t,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.35, -0.4),
                    radius: 0.95,
                    colors: [
                      Color(0xFFFFE8B5),
                      Color(0xFFFFB534),
                      Color(0xFFFF7F50),
                    ],
                    stops: [0.0, 0.52, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.bubble_chart_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SolPillButton extends StatefulWidget {
  const _SolPillButton({
    required this.label,
    required this.icon,
    this.isPrimary = true,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback? onTap;

  @override
  State<_SolPillButton> createState() => _SolPillButtonState();
}

class _SolPillButtonState extends State<_SolPillButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) => setState(() => _hovered = false),
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFB534),
                Color(0xFFFF954E),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x38FF8A3D),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                widget.icon,
                size: 13,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
