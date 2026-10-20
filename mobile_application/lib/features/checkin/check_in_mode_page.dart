import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../../core/widgets/page_back_button.dart';
import '../../data/repositories/in_memory_consent_repository.dart';
import '../art/checkin_art.dart';
import '../consent/consent_controller.dart';
import '../journal/journal_capture_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../sessions/session_controller.dart';
import 'text_check_in_page.dart';

class CheckInModePage extends StatelessWidget {
  /// What the person has agreed to; set once at start-up. Without it every recording asks again.
  static ConsentController? consent;

  const CheckInModePage({
    required this.sessionController,
    required this.safetyController,
    this.profileController,
    super.key,
  });

  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController? profileController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRect(
        child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFDF8EC),
              Color(0xFFFBF3E4),
              Color(0xFFFBEFE3),
            ],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: -90,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x56FFB534),
                        Color(0x00FFB534),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -90,
              child: IgnorePointer(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x42FF7F50),
                        Color(0x00FF7F50),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 368),
                child: SafeArea(
                  child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                children: [
                  const Align(alignment: Alignment.centerLeft, child: PageBackButton()),
                  const SizedBox(height: 14),
                  const Text(
                    'How would you like\nto check in?',
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: Color(0xFF3A3125),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Whatever feels easiest right now is the right one.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A7A61),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _Enter(
                    index: 0,
                    child: _ModeTile(
                      kind: CheckInKind.text,
                      title: 'Text',
                      description: "Type how you're feeling",
                      onTap: () => _openText(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Enter(
                    index: 1,
                    child: _ModeTile(
                      kind: CheckInKind.voice,
                      title: 'Voice',
                      description: 'Say it out loud',
                      onTap: () => _openJournal(context, CaptureMode.voice),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Enter(
                    index: 2,
                    child: _ModeTile(
                      kind: CheckInKind.video,
                      title: 'Video',
                      description: 'See yourself as you speak',
                      onTap: () => _openJournal(context, CaptureMode.video),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'You can switch anytime',
                            style: TextStyle(
                              color: Color(0xFFA2947F),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xBFFFB534),
                            ),
                          ),
                          const Text(
                            'nothing is saved until you start',
                            style: TextStyle(
                              color: Color(0xFFA2947F),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  void _openText(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TextCheckInPage(
          sessionController: sessionController,
          safetyController: safetyController,
          profileController: profileController,
        ),
      ),
    );
  }

  /// Voice and video check-ins are JOURNAL entries: you talk to yourself, nobody replies, and the
  /// recording becomes a transcript with its emotion reading. (The live conversation with Sol is
  /// the separate Call, opened from chat.)
  void _openJournal(BuildContext context, CaptureMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JournalCapturePage(
          mode: mode,
          sessionController: sessionController,
          safetyController: safetyController,
          profileController: profileController,
          consentController: consent ?? ConsentController(repository: InMemoryConsentRepository()),
        ),
      ),
    );
  }
}

/// Fades and slides a tile up a beat after the one before it.
class _Enter extends StatelessWidget {
  const _Enter({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      // Quick, so the cards are there as the page settles instead of arriving after it.
      duration: Duration(milliseconds: 240 + index * 50),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: 0.35 + 0.65 * t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: child,
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.kind,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final CheckInKind kind;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white,
        border: Border.all(color: const Color(0x33FFB534), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Color(0x33B28028), blurRadius: 26, offset: Offset(0, 12)),
          BoxShadow(color: Color(0x14B28028), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(width: 128, height: double.infinity, child: CheckInArt(kind: kind, radius: 20)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3A3125),
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF8A7A61), height: 1.3),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFFFFB534), Color(0xFFFF8F5A)]),
                  ),
                  child: const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
