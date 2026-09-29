import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/support_resource.dart';
import '../../services/dialer_service.dart';
import 'safety_controller.dart';
import 'support_resource_catalog.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class SupportResourcesPage extends StatefulWidget {
  const SupportResourcesPage({
    required this.safetyController,
    this.assessment,
    this.regionCode = 'GLOBAL',
    this.dialer = const DialerService(),
    super.key,
  });

  final SafetyController safetyController;
  final SafetyAssessment? assessment;
  final String regionCode;
  final DialerService dialer;

  @override
  State<SupportResourcesPage> createState() => _SupportResourcesPageState();
}

class _SupportResourcesPageState extends State<SupportResourcesPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (!_isTestEnvironment) {
      _breathController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  /// Opens the dialer pre-filled, with a gentle note if none is available.
  Future<void> _dial(String number) async {
    final opened = await widget.dialer.openDialer(number);
    if (!mounted || opened) return;
    _showUnavailable();
  }

  /// Opens the SMS composer with the given message body.
  Future<void> _text(String number, String body) async {
    final opened = await widget.dialer.openSms(number, body: body);
    if (!mounted || opened) return;
    _showUnavailable();
  }

  void _showUnavailable() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('No dialer available on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final resources = SupportResourceCatalog.forRegion(widget.regionCode);
    final isUrgent = widget.assessment?.level == SafetyLevel.urgentSupport;

    return Scaffold(
      backgroundColor: const Color(0xFFFEFCE8),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                // Top header bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB534), Color(0xFFFF7F50)],
                            ),
                            borderRadius: BorderRadius.circular(7),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66FF7F50),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SOLACE CARE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: Color(0xFFB9A98C),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF8E8272),
                      ),
                      onPressed: () async {
                        await widget.safetyController.markSupportShown();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Warm reassuring hero card
                _SupportHero(isUrgent: isUrgent),
                const SizedBox(height: 18),

                // Grounding breath pause
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF2ECDD)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1078501E),
                        blurRadius: 14,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _breathController,
                        builder: (context, child) {
                          final scale = 0.85 + (_breathController.value * 0.25);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFFFB534),
                                    const Color(0xFFFF7F50).withValues(alpha: 0.7),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0x40FF7F50),
                                    blurRadius: 10 * scale,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.air_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Take one gentle breath',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4A3728),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Inhale slowly... hold... release. You are safe here.',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF93887A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // Fast Direct Hotlines (Always Available)
                const Text(
                  'IMMEDIATE CRISIS HELPLINES · 24/7 FREE',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: Color(0xFFBCAC8E),
                  ),
                ),
                const SizedBox(height: 10),

                // 988 Suicide & Crisis Lifeline
                _HotlineActionCard(
                  title: '988 Suicide & Crisis Lifeline',
                  subtitle: 'Call or text 988 · Free, confidential, anytime',
                  actionLabel: 'Call 988',
                  icon: Icons.phone_in_talk_rounded,
                  accentColor: const Color(0xFFD2603A),
                  bgColor: const Color(0xFFFFF1EA),
                  onTap: () => _dial('988'),
                ),
                const SizedBox(height: 10),

                // Crisis Text Line 741741
                _HotlineActionCard(
                  title: 'Crisis Text Line',
                  subtitle: 'Text HOME to 741741 · Free 24/7 text support',
                  actionLabel: 'Text 741741',
                  icon: Icons.chat_bubble_outline_rounded,
                  accentColor: const Color(0xFFB57A12),
                  bgColor: const Color(0xFFFFF3DC),
                  onTap: () => _text('741741', 'HOME'),
                ),
                const SizedBox(height: 22),

                // Section title
                const Text(
                  'RECOMMENDED NEXT STEPS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: Color(0xFFBCAC8E),
                  ),
                ),
                const SizedBox(height: 10),

                // Resource cards
                for (final resource in resources) ...[
                  _ResourceCard(
                    resource: resource,
                    onDial: resource.phone == null
                        ? null
                        : () => _dial(resource.phone!),
                  ),
                  const SizedBox(height: 10),
                ],

                // Regional unverified disclaimer if needed
                if (SupportResourceCatalog.hasUnverifiedEntries(widget.regionCode)) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8EA),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF4E5CA)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFFB57A12),
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Regional contact details are not verified for external use yet. The project team must review local resources before launch.',
                            style: TextStyle(
                              color: Color(0xFF96620C),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 3 Grounding Anchors Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFF2ECDD)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1078501E),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 18,
                            color: Color(0xFFB57A12),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Small anchors for right now',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4A3728),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _anchorStep('1', 'Sip a glass of cool water slowly.'),
                      _anchorStep('2', 'Wrap yourself in a blanket or feel your feet on the floor.'),
                      _anchorStep('3', 'Tell someone you trust: "I am having a hard moment today."'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Return to reflection button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4A3728),
                      side: const BorderSide(
                        color: Color(0xFFE2D6C0),
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      await widget.safetyController.markSupportShown();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text(
                      'Return to reflection',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Control & privacy reassurance
                const Text(
                  'You remain in control. Solace does not notify anyone automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA2988A),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _anchorStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF3DC),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB57A12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A6E5D),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotlineActionCard extends StatelessWidget {
  const _HotlineActionCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.icon,
    required this.accentColor,
    required this.bgColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData icon;
  final Color accentColor;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF2ECDD)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1078501E),
              blurRadius: 14,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3A3226),
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A7F72),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                actionLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportHero extends StatelessWidget {
  const _SupportHero({required this.isUrgent});

  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    if (isUrgent) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF7F50), Color(0xFFF35D39)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40FF7F50),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'You deserve support\nfrom a person right now.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'If you may act on thoughts of harm or cannot stay safe, move toward immediate human support now. These resources are confidential, free, and open 24/7.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E2), Color(0xFFFFEDE0)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF6E4C8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F785C28),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE2CC),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.wb_sunny_rounded,
              color: Color(0xFFD2603A),
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You do not have to\nhold this alone.',
            style: TextStyle(
              color: Color(0xFF3A3226),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'It sounds like today may be carrying more than usual. These options are here without pressure or judgment.',
            style: TextStyle(
              color: Color(0xFF7A6E5D),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.resource, this.onDial});

  final SupportResource resource;

  /// Opens the dialer for this resource, or null when it has no number.
  final VoidCallback? onDial;

  @override
  Widget build(BuildContext context) {
    final (icon, tileBg, tileColor) = switch (resource.kind) {
      SupportResourceKind.trustedPerson => (
        Icons.people_outline_rounded,
        const Color(0xFFFFF2D9),
        const Color(0xFFB57A12),
      ),
      SupportResourceKind.localEmergency => (
        Icons.emergency_outlined,
        const Color(0xFFFFE5DA),
        const Color(0xFFD2603A),
      ),
      SupportResourceKind.professionalSupport => (
        Icons.medical_services_outlined,
        const Color(0xFFFFF2D9),
        const Color(0xFFB57A12),
      ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF4EEE2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1278501E),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tileColor, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            resource.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF3A3226),
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                        if (resource.isVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEBF7EB),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Verified 24/7',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF3F823B),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      resource.description,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7D7262),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (resource.phone != null) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDial,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFDFC8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone_rounded,
                        size: 16,
                        color: Color(0xFFD2603A),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Direct dial: ${resource.phone}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB4522C),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Tap to call',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFD2603A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
