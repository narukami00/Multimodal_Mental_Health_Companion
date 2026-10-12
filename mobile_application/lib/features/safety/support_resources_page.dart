import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/country_resources.dart';
import '../../core/models/emergency_contact.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/theme/solace_palette.dart';
import '../../services/dialer_service.dart';
import '../profile/profile_controller.dart';
import 'breathing_pattern.dart';
import 'care_contacts_page.dart';
import 'safety_controller.dart';

bool get _isTestEnvironment {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// The oversized page title used on Solace Care screens.
const _masthead = TextStyle(
  fontSize: 34,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.8,
  height: 1.1,
  color: Color(0xFF3A3125),
);

/// The support screen reached when someone needs help right now.
///
/// Deliberately short: every block is something the user can *do*. It carries
/// no helpline directory — the only external number is the national emergency
/// number, and the main action is calling a person the user has saved
/// themselves, so nothing here can go stale on them.
class SupportResourcesPage extends StatefulWidget {
  const SupportResourcesPage({
    required this.safetyController,
    this.profileController,
    this.assessment,
    this.dialer = const DialerService(),
    super.key,
  });

  final SafetyController safetyController;

  /// Supplies the user's own saved contact. When absent, the personal block is
  /// simply omitted rather than showing a placeholder number.
  final ProfileController? profileController;

  final SafetyAssessment? assessment;
  final DialerService dialer;

  /// Bangladesh national emergency service: police, fire and ambulance.
  static const emergencyNumber = '999';

  @override
  State<SupportResourcesPage> createState() => _SupportResourcesPageState();
}

/// Drives the paced breathing guide and the personal-contact block.
class _SupportResourcesPageState extends State<SupportResourcesPage>
    with SingleTickerProviderStateMixin {
  static const _pattern = BreathingPattern();

  late final AnimationController _breath;
  BreathPhase _phase = BreathPhase.inhale;
  int _breaths = 0;

  @override
  void initState() {
    super.initState();
    _breath =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: _pattern.cycleMs),
          )
          ..addListener(_onBreathTick)
          ..addStatusListener(_onBreathStatus);

    // Never auto-run under test: an endless animation would hang pumpAndSettle.
    if (!_isTestEnvironment) {
      _breath.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the platform's reduced-motion setting.
    if (MediaQuery.of(context).disableAnimations && _breath.isAnimating) {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  /// Repaints only when the cue actually changes, not every frame.
  void _onBreathTick() {
    final next = _pattern.phaseAt(_breath.value);
    if (next != _phase && mounted) {
      setState(() => _phase = next);
    }
  }

  void _onBreathStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (mounted) setState(() => _breaths++);
    if (!_isTestEnvironment) {
      _breath.forward(from: 0);
    }
  }

  String get _cueLabel => _pattern.cueFor(_phase);

  /// The contact to surface first: the one marked call-first, else the only
  /// saved contact.
  EmergencyContact? get _primaryContact {
    final contacts = widget.profileController?.profile.emergencyContacts;
    if (contacts == null || contacts.isEmpty) return null;
    for (final contact in contacts) {
      if (contact.isIce) return contact;
    }
    return contacts.first;
  }

  /// The person's own country decides the emergency number and listening lines.
  CountryResources get _country =>
      CountryResources.byCode(widget.profileController?.profile.countryCode);

  bool get _isUrgent => widget.assessment?.level == SafetyLevel.urgentSupport;

  Future<void> _close() async {
    await widget.safetyController.markSupportShown();
    if (mounted) Navigator.of(context).pop();
  }

  /// Pre-fills the dialer. The user still confirms the call.
  Future<void> _dial(String number) async {
    final opened = await widget.dialer.openDialer(number);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('No dialer available on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _dialEmergency() {
    final number = _country.emergencyNumber;
    if (number != null) _dial(number);
  }

  Future<void> _openContacts() async {
    final controller = widget.profileController;
    if (controller == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CareContactsPage(profileController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ListView(
          // Same 22px inset as the main pages, so cards line up app-wide.
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            _buildHeader(colors),
            const SizedBox(height: 2),
            // Page masthead: an oversized title with a warm under-glow, so the
            // page opens with calm rather than a bare line of text.
            Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned(
                  top: -36,
                  left: -30,
                  child: IgnorePointer(
                    child: SizedBox.square(
                      dimension: 190,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color(0x40FFB534), Color(0x00FFB534)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Text('Right now', style: _masthead),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'One of these is enough.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7B6A55),
              ),
            ),
            const SizedBox(height: 18),

            // For an acute flag, the emergency number comes before anything.
            if (_isUrgent) ...[
              _DangerRow(
                number: _country.emergencyNumber,
                emphasised: true,
                onTap: _dialEmergency,
              ),
              const SizedBox(height: 14),
            ],

            _buildPersonBlock(),
            const SizedBox(height: 14),

            for (final line in _country.helplines) ...[
              _HelplineCard(helpline: line, onCall: () => _dial(line.phone)),
              const SizedBox(height: 14),
            ],

            _buildBreathCard(colors),

            if (!_isUrgent) ...[
              const SizedBox(height: 16),
              _DangerRow(
                number: _country.emergencyNumber,
                emphasised: false,
                onTap: _dialEmergency,
              ),
            ],

            const SizedBox(height: 22),
            const Text(
              'Solace is not an emergency service.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFA2988A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SolaceColors colors) {
    return Row(
      children: [
        IconButton(
          onPressed: _close,
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF8E8272),
            minimumSize: const Size(44, 44),
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'SOLACE CARE',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: Color(0xFFB9A98C),
          ),
        ),
      ],
    );
  }

  Widget _buildPersonBlock() {
    final controller = widget.profileController;
    if (controller == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final contact = _primaryContact;
        if (contact == null) {
          return _AddPersonCard(onAdd: _openContacts);
        }
        return _PersonCard(
          contact: contact,
          onCall: () => _dial(contact.phone),
          onManage: _openContacts,
        );
      },
    );
  }

  Widget _buildBreathCard(SolaceColors colors) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF2ECDD)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1278501E),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'BREATHE WITH ME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: Color(0xFFBCAC8E),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            child: Center(
              child: reduceMotion
                  ? _BreathCircle(scale: 0.8, label: 'Breathe in, then out')
                  : AnimatedBuilder(
                      animation: _breath,
                      builder: (context, _) => _BreathCircle(
                        scale: _pattern.scaleAt(_breath.value),
                        label: _cueLabel,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _breaths == 0
                ? 'Follow the circle. In for four, hold, out for six.'
                : '$_breaths ${_breaths == 1 ? 'breath' : 'breaths'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF93887A),
            ),
          ),
        ],
      ),
    );
  }
}

/// Expanding circle with the current breathing cue inside it.
class _BreathCircle extends StatelessWidget {
  const _BreathCircle({required this.scale, required this.label});

  final double scale;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: scale,
            child: Container(
              width: 132,
              height: 132,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x59FFC46B), Color(0x1AFF7F50)],
                ),
              ),
            ),
          ),
          Transform.scale(
            scale: scale,
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFD98A), Color(0xFFFF9A6A)],
                ),
              ),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF5A3B10),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent card for the person the user has saved, with one-tap calling.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.contact,
    required this.onCall,
    required this.onManage,
  });

  final EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
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
          Text(
            contact.isIce ? 'YOUR CALL-FIRST PERSON' : 'YOUR PERSON',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: Color(0xFFB58A4C),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            contact.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: Color(0xFF3A3125),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            contact.phone,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A7A62),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              key: const ValueKey('call-person'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: onCall,
              icon: const Icon(Icons.call_rounded, size: 20),
              label: Text(
                'Call ${contact.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Saved on your device. You control it.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9A8B74),
                  ),
                ),
              ),
              TextButton(
                onPressed: onManage,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF96620C),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Manage',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the user has not saved anyone yet.
class _AddPersonCard extends StatelessWidget {
  const _AddPersonCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF6EFD9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add someone you can call',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3A3125),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick one person you trust and save their number. It stays on this '
            'device, and you can change it whenever you want.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF7B6A55),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const ValueKey('add-person'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text(
                'Add a contact',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tap-to-dial line for the national emergency number. Always present, calm
/// and unmissable without shouting.
class _DangerRow extends StatelessWidget {
  const _DangerRow({
    required this.number,
    required this.onTap,
    required this.emphasised,
  });

  /// Null when no emergency number is verified for the country: the row then only
  /// reminds the person to call their local one.
  final String? number;
  final VoidCallback onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final emphasisedInk = const Color(0xFFB4522C);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: emphasised
                ? const Color(0xFFFFE9DE)
                : const Color(0xFFFFF7F0),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: emphasised
                  ? const Color(0xFFFFC7AC)
                  : const Color(0xFFF6E2D6),
            ),
            boxShadow: emphasised
                ? const [
                    BoxShadow(
                      color: Color(0x2ED2603A),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              // The emergency glyph sits in its own sunken disc, like a call
              // button that happens to say "911".
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: emphasised
                      ? const Color(0xFFFFD9C8)
                      : const Color(0xFFFFF1EA),
                  border: Border.all(color: const Color(0x33D2603A)),
                ),
                child: const Icon(
                  Icons.emergency_outlined,
                  size: 21,
                  color: Color(0xFFD2603A),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      number == null
                          ? 'In immediate danger?'
                          : 'In immediate danger? Call $number',
                      style: TextStyle(
                        fontSize: emphasised ? 14.5 : 13.5,
                        fontWeight: FontWeight.w800,
                        color: emphasisedInk,
                      ),
                    ),
                    if (number == null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Call your local emergency number',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: emphasisedInk.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (number != null)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD2603A),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33D2603A),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.call_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A listening line for the person's country, with one-tap dialling.
class _HelplineCard extends StatelessWidget {
  const _HelplineCard({required this.helpline, required this.onCall});

  final Helpline helpline;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF6EFD9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14785C28),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onCall,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // A quiet dial disc at the left: the whole card is tappable,
                // and the disc says so at a glance.
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFF3DC),
                    border: Border.all(color: const Color(0x33FFB534)),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    size: 21,
                    color: Color(0xFFB57A12),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        helpline.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3A3125),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        helpline.about,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: Color(0xFF7B6A55),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Color(0xFF96620C),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              helpline.hours,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF96620C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  key: const ValueKey('call-helpline'),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFB534),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33B57A12),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.call_rounded,
                    size: 19,
                    color: Color(0xFF3D2E14),
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
