import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
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
    this.showSuggestion = false,
    this.suggestionCard,
    this.setupCard,
    this.onContinueSetup,
    this.currentTime,
    this.chatController,
    this.ambientAudioEnabled = true,
    this.rhythmCard,
    this.welcomeBackNotice,
    this.onStartCheckIn,
    this.onOpenSupport,
    this.onOpenChat,
    this.onStartNewChat,
    this.onOpenCall,
    super.key,
  });

  final HomeCardType primaryCard;

  /// Whether the standing suggestion card should appear below the primary one.
  final bool showSuggestion;

  /// The suggestion card itself, built by the shell so it can peek at the
  /// engine without the page needing to know about suggestions at all.
  final Widget? suggestionCard;

  /// The standing setup-progress card, or null once setup is done.
  final Widget? setupCard;

  /// Opens the baseline reflection quiz.
  final VoidCallback? onContinueSetup;

  final DateTime? currentTime;
  final ChatController? chatController;

  /// Whether the user has allowed ambient audio in Settings.
  final bool ambientAudioEnabled;

  /// Optional rhythm summary, shown under the primary card so it stays
  /// subordinate to the one primary action.
  final Widget? rhythmCard;

  /// Optional one-off line for someone returning after a long gap.
  final Widget? welcomeBackNotice;

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

    final colors = SolaceColors.from(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        gradient: RadialGradient(
          center: const Alignment(0.88, -0.6),
          radius: 1.3,
          colors: [
            const Color(0x4DFFD07A),
            const Color(0x1AFF7F50),
            colors.background,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: SafeArea(
        // No horizontal padding here: several sections below are deliberately
        // full-bleed, and a single padded column is what made the page read as
        // one stack of identical slabs.
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              child: _buildMasthead(context, greeting, date),
            ),
            // A full-bleed hairline: the one separator on the page, used once.
            Container(
              height: 1,
              margin: const EdgeInsets.only(top: 18),
              color: const Color(0xFF4A3728).withValues(alpha: 0.08),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  if (welcomeBackNotice != null) welcomeBackNotice!,
                  _buildPrimaryCard(card),
                ],
              ),
            ),
            // Gaps vary deliberately (18 / 30 / 26 / 22) so the page has
            // accents instead of one even tempo.
            const SizedBox(height: 30),
            if (rhythmCard != null) rhythmCard!,
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  // The companion is the reason someone opens this app, so it
                  // is the largest thing on the page rather than the smallest.
                  _buildSolCompanionHub(context),
                  if (showSuggestion && suggestionCard != null) ...[
                    const SizedBox(height: 26),
                    suggestionCard!,
                  ],
                  if (setupCard != null) ...[
                    const SizedBox(height: 22),
                    setupCard!,
                  ],
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  LivingAtmosphereCard(ambientAudioEnabled: ambientAudioEnabled),
                  const SizedBox(height: 24),
                  _buildFooter(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The greeting and the date, with no container around them.
  ///
  /// The greeting used to be the largest type on the screen at roughly 33px,
  /// which told the user that the most important fact available was that it was
  /// evening. It is orientation, so it is now set at a size that says so, with
  /// the date as a chip on the same baseline.
  Widget _buildMasthead(BuildContext context, String greeting, String date) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            greeting,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: Color(0xFF4A3728),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF4A3728).withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            date,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7B6A55),
            ),
          ),
        ),
      ],
    );
  }

  /// What the top card's button does.
  ///
  /// Every card used to run the check-in flow regardless of what it said, so
  /// "Continue setup" opened a check-in and the support card did too. Each card
  /// now does what its own label promises.
  VoidCallback? _primaryAction(HomeCardType type) {
    return switch (type) {
      HomeCardType.support => onOpenSupport,
      HomeCardType.checkIn => onStartCheckIn,
      HomeCardType.onboarding => onContinueSetup,
      // "Open a journal or conversation whenever you are ready."
      HomeCardType.defaultAction => onOpenChat,
    };
  }

  Widget _buildPrimaryCard(_PrimaryCardContent card) {
    return Container(
      decoration: BoxDecoration(
        // 24 rather than 32: the corner geometry now says something, since the
        // companion card and the idea card use different radii.
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: const Alignment(-0.6, -1.0),
          end: const Alignment(0.8, 1.0),
          colors: card.gradientColors,
        ),
        // A soft lift, not the hard offset band that used to sit under every
        // card and read as a second slab peeking out from behind.
        boxShadow: [
          BoxShadow(
            color: card.shadowColor.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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
                          // Full strength, not 0.7: the eyebrow was sitting at
                          // roughly 1.8:1 against this card's own fill.
                          color: card.foregroundColor,
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
                      color: card.foregroundColor.withValues(alpha: 0.90),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _primaryAction(primaryCard),
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
      // Setup is a utility, so it is the least saturated card on the page
      // rather than the loudest. It used to be a saturated orange slab whose
      // white button out-shouted the companion, for the least valuable action
      // on the screen.
      HomeCardType.onboarding => const _PrimaryCardContent(
          eyebrow: 'GETTING STARTED',
          title: 'Make Solace\nfeel more like you',
          subtitle: 'A few gentle choices help shape what you see here.',
          action: 'Continue setup',
          icon: Icons.arrow_forward_rounded,
          gradientColors: [
            Color(0xFFFFF3DE),
            Color(0xFFFBE4C0),
            Color(0xFFF6D5A5),
          ],
          shadowColor: Color(0x33B0793A),
          foregroundColor: Color(0xFF4A3213),
          ctaTextColor: Color(0xFF8A5A16),
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
    duration: const Duration(milliseconds: 6200),
  );

  @override
  void initState() {
    super.initState();
    if (!_isTestEnvironment) {
      _ctrl.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isTestEnvironment && MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _WaterBubblePainter(animation: _ctrl),
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final tau = _ctrl.value * 2 * math.pi;
                return Transform.translate(
                  offset: Offset(0, math.sin(tau) * 0.8),
                  child: Icon(
                    Icons.bubble_chart_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.94),
                    shadows: [
                      Shadow(
                        color: const Color(0xFF9E3D0A).withValues(alpha: 0.40),
                        blurRadius: 3.5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterBubblePainter extends CustomPainter {
  _WaterBubblePainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  static Path _buildClosedFluidSpline(List<Offset> points) {
    final path = Path();
    final count = points.length;
    if (count < 3) return path;

    final midPoints = List<Offset>.generate(count, (i) {
      final p0 = points[i];
      final p1 = points[(i + 1) % count];
      return Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    });

    path.moveTo(midPoints[count - 1].dx, midPoints[count - 1].dy);
    for (var i = 0; i < count; i++) {
      path.quadraticBezierTo(
        points[i].dx,
        points[i].dy,
        midPoints[i].dx,
        midPoints[i].dy,
      );
    }
    path.close();
    return path;
  }

  static Path _generateFluidBlob({
    required Offset center,
    required double radius,
    required double tau,
    required double rotation,
    required double amp1,
    required double amp2,
    required double amp3,
    double phase1 = 0.0,
    double phase2 = 1.1,
    double phase3 = 2.3,
    int freq1 = 1,
    int freq2 = -1,
    int freq3 = 2,
  }) {
    const numPoints = 36;
    final points = <Offset>[];

    for (var i = 0; i < numPoints; i++) {
      final theta = (i / numPoints) * 2 * math.pi;

      final harmR = 1.0 +
          amp1 * math.sin(2 * theta + freq1 * tau + phase1) +
          amp2 * math.cos(3 * theta + freq2 * tau + phase2) +
          amp3 * math.sin(5 * theta + freq3 * tau + phase3);

      final r = radius * harmR;
      final rotTheta = theta + rotation;
      final x = center.dx + r * math.cos(rotTheta);
      final y = center.dy + r * math.sin(rotTheta);
      points.add(Offset(x, y));
    }

    return _buildClosedFluidSpline(points);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.39; // ~16.4dp on 42x42
    final tau = animation.value * 2 * math.pi;

    // 1. Radiant Living Atmosphere Glow (breathing warm aura)
    final glowPulse = 0.28 + 0.12 * math.sin(tau);
    final glowRadius = baseRadius * 1.38;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFB534).withValues(alpha: glowPulse),
          const Color(0xFFFF7F50).withValues(alpha: glowPulse * 0.5),
          const Color(0xFFFF7F50).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // 2. Primary Fluid Water Bubble Body
    final outerPath = _generateFluidBlob(
      center: center,
      radius: baseRadius * (1.0 + 0.032 * math.sin(tau)),
      tau: tau,
      rotation: tau, // 1 complete slow clockwise rotation per 6.2s period
      amp1: 0.052,
      amp2: 0.036,
      amp3: 0.016,
    );

    // Orbiting gradient center creates rich fluid refraction
    final orbitX = 0.32 * math.cos(tau) - 0.12;
    final orbitY = 0.32 * math.sin(tau) - 0.18;
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(orbitX, orbitY),
        radius: 0.98,
        colors: const [
          Color(0xFFFFF1D6), // Sunlight reflection core
          Color(0xFFFFC248), // Golden honey body
          Color(0xFFFF8B3D), // Warm amber refraction
          Color(0xFFFF6238), // Soft coral water depth
        ],
        stops: [0.0, 0.36, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.15));
    canvas.drawPath(outerPath, bodyPaint);

    // 3. Inner Counter-Swirling Liquid Depth
    final innerCenter = Offset(
      center.dx - baseRadius * 0.08 * math.cos(tau),
      center.dy - baseRadius * 0.08 * math.sin(tau),
    );
    final innerPath = _generateFluidBlob(
      center: innerCenter,
      radius: baseRadius * 0.66 * (1.0 + 0.04 * math.cos(tau)),
      tau: tau,
      rotation: -tau, // Counter-rotating for 3D liquid shear
      amp1: 0.060,
      amp2: 0.042,
      amp3: 0.018,
      freq1: -2,
      freq2: 1,
      freq3: -2,
      phase1: 0.8,
      phase2: 2.1,
      phase3: 1.4,
    );

    final innerPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        radius: 0.88,
        colors: [
          Colors.white.withValues(alpha: 0.45),
          const Color(0xFFFFE6A8).withValues(alpha: 0.28),
          const Color(0xFFFF953E).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(
        Rect.fromCircle(center: innerCenter, radius: baseRadius * 0.72),
      );
    canvas.drawPath(innerPath, innerPaint);

    // 4. Floating Micro-Bubbles (effervescent liquid droplets inside)
    final mb1Center = Offset(
      center.dx + math.sin(tau) * (baseRadius * 0.28),
      center.dy + math.cos(tau) * (baseRadius * 0.20) - 1.8,
    );
    canvas.drawCircle(
      mb1Center,
      1.7,
      Paint()..color = Colors.white.withValues(alpha: 0.40),
    );
    canvas.drawCircle(
      Offset(mb1Center.dx - 0.4, mb1Center.dy - 0.4),
      0.6,
      Paint()..color = Colors.white.withValues(alpha: 0.90),
    );

    final mb2Center = Offset(
      center.dx - math.cos(tau) * (baseRadius * 0.24),
      center.dy + math.sin(tau) * (baseRadius * 0.22) + 2.2,
    );
    canvas.drawCircle(
      mb2Center,
      1.2,
      Paint()..color = Colors.white.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      Offset(mb2Center.dx - 0.3, mb2Center.dy - 0.3),
      0.4,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // 5. Specular Water Bubble Caustics & Sheen
    // Top-Left Primary Specular Arc Highlight
    final sheenCenter = Offset(
      center.dx - baseRadius * (0.32 + 0.025 * math.sin(tau)),
      center.dy - baseRadius * (0.36 + 0.025 * math.cos(tau)),
    );
    final sheenRadius = baseRadius * 0.40;
    final sheenPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.88),
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: sheenCenter, radius: sheenRadius));
    canvas.drawCircle(sheenCenter, sheenRadius, sheenPaint);

    // Secondary Pinpoint Glint (water shine)
    final glintCenter = Offset(
      center.dx - baseRadius * (0.50 + 0.015 * math.cos(tau)),
      center.dy - baseRadius * (0.12 + 0.015 * math.sin(tau)),
    );
    canvas.drawCircle(
      glintCenter,
      1.3,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // Bottom-Right Subsurface Caustic Bounce
    final bounceCenter = Offset(
      center.dx + baseRadius * (0.28 + 0.02 * math.cos(tau)),
      center.dy + baseRadius * (0.30 + 0.02 * math.sin(tau)),
    );
    final bounceRadius = baseRadius * 0.42;
    final bouncePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE8C2).withValues(alpha: 0.35),
          const Color(0xFFFFB534).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCircle(center: bounceCenter, radius: bounceRadius),
      );
    canvas.drawCircle(bounceCenter, bounceRadius, bouncePaint);

    // 6. Surface-Tension Shimmer Rim Stroke
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(tau - math.pi * 0.75),
        colors: [
          Colors.white.withValues(alpha: 0.88),
          Colors.white.withValues(alpha: 0.35),
          const Color(0xFFFFCA7A).withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.88),
        ],
        stops: const [0.0, 0.38, 0.70, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.15));
    canvas.drawPath(outerPath, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _WaterBubblePainter oldDelegate) {
    return oldDelegate.animation.value != animation.value;
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
