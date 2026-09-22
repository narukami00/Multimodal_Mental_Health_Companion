import 'package:flutter/material.dart';

import '../../domain/home/home_card_priority.dart';
import '../chat/conversation_history.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    this.primaryCard = HomeCardType.checkIn,
    this.currentTime,
    this.onStartCheckIn,
    this.onOpenSupport,
    this.onOpenChat,
    this.onOpenCall,
    super.key,
  });

  final HomeCardType primaryCard;
  final DateTime? currentTime;
  final VoidCallback? onStartCheckIn;
  final VoidCallback? onOpenSupport;
  final VoidCallback? onOpenChat;
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
            _buildSecondaryCard(),
            const SizedBox(height: 12),
            _buildRecentConversationCard(context),
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
              child: CustomPaint(
                painter: _CardPetalPainter(),
              ),
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

  Widget _buildSecondaryCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFEFA),
            Color(0xFFFFFBEF),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0x3DFFB534),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1478501E),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onOpenChat,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0x26FF7F50),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.forum_rounded,
                    color: Color(0xFFFF7F50),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Talk it through',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4A3728),
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'A quiet space with Sol · voice or text',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7B6A55),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0x807B6A55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openHistorySheet(BuildContext context) {
    ConversationHistorySheet.show(
      context,
      onSelectThread: (thread) {
        onOpenChat?.call();
      },
      onNewConversation: () {
        onOpenChat?.call();
      },
    );
  }

  Widget _buildRecentConversationCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0x387A5D3A),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1278501E),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onOpenChat,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Sol Avatar icon, Eyebrow, and History Sheet Button
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFE8B5), Color(0xFFFFB534)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        color: Color(0xFF5A3B10),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'CONVERSATION WITH SOL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Color(0xFF8A6A4E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _openHistorySheet(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x18FFB534),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x40FFB534)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 13,
                              color: Color(0xFF8A601E),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'History (4)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A601E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Conversation excerpt
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x26FFB534)),
                  ),
                  child: const Text(
                    '“Take your time here. You don\'t have to carry it all by yourself. What feels present right now?”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A3728),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Footer row: Status dot, timestamp, and glowing Resume pill
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF48BB78),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Today · 2:15 PM · Active thread',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8C7C69),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB534), Color(0xFFFF7F50)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2ECA6A1A),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Resume',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFFFDF5),
                            ),
                          ),
                          SizedBox(width: 3),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 12,
                            color: Color(0xFFFFFDF5),
                          ),
                        ],
                      ),
                    ),
                  ],
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

class _CardPetalPainter extends CustomPainter {
  const _CardPetalPainter();

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
      final angle = (i * 45) * 3.141592653589793 / 180;
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
