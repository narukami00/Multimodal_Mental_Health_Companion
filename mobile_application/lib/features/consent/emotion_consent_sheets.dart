import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import 'consent_controller.dart';

/// Asked at the moment a feature needs the consent, never before: the bottom
/// sheets for the voice-and-words emotion reading and for reading the camera.
/// Each returns true only when the person agreed (and records the consent).

/// "Let Sol read how this entry sounds?" Needed once for typed, voice and video check-ins.
Future<bool> askEmotionConsent(BuildContext context, ConsentController consent) async {
  if (consent.isGranted(ConsentKey.emotionEstimate)) return true;
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => ConsentSheet(
      key: const ValueKey('emotion-consent-sheet'),
      title: 'Read how this entry sounds?',
      body: 'Your words and recorded voice are sent to the companion server to '
          'estimate emotion. Recordings can wait privately on your phone while '
          'the server is unavailable, then are deleted after successful processing '
          'or entry deletion. This uncertain estimate may inform suggestions, '
          'summaries and Sol\'s replies. It is not a diagnosis. Turn this off '
          'in What Sol remembers.',
      allowLabel: 'Allow reading',
      onAllow: () => Navigator.of(sheetContext).pop(true),
      onDecline: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  if (agreed != true) return false;
  await consent.grant(ConsentKey.emotionEstimate);
  return true;
}

/// "Let Sol read your face?" A separate yes for the camera (and it also grants the voice-and-words reading).
Future<bool> askFaceConsent(BuildContext context, ConsentController consent) async {
  if (consent.isGranted(ConsentKey.faceFeatures)) return true;
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => ConsentSheet(
      key: const ValueKey('face-consent-sheet'),
      title: 'Let Sol read your face?',
      body: 'Face measurements or live camera frames are sent to the companion '
          'server to estimate emotion. Live frames are processed in memory, '
          'not saved as pictures. Queued measurements can wait on your phone '
          'until processing or entry deletion. The estimate may inform '
          'suggestions, summaries and Sol\'s replies; it can be wrong. '
          'Turn this off in What Sol remembers.',
      allowLabel: 'Allow camera reading',
      allowKey: const ValueKey('face-allow'),
      declineKey: const ValueKey('face-decline'),
      onAllow: () => Navigator.of(sheetContext).pop(true),
      onDecline: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  if (agreed != true) return false;
  if (!consent.isGranted(ConsentKey.emotionEstimate)) {
    await consent.grant(ConsentKey.emotionEstimate);
  }
  await consent.grant(ConsentKey.faceFeatures);
  return true;
}

class ConsentSheet extends StatelessWidget {
  const ConsentSheet({
    required this.title,
    required this.body,
    required this.allowLabel,
    required this.onAllow,
    required this.onDecline,
    this.allowKey = const ValueKey('consent-allow'),
    this.declineKey = const ValueKey('consent-decline'),
    super.key,
  });

  final String title;
  final String body;
  final String allowLabel;
  final VoidCallback onAllow;
  final VoidCallback onDecline;
  final Key allowKey;
  final Key declineKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      // Keeps "Not now" clear of the system navigation bar.
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF3A3125)),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w600, color: Color(0xFF6E5D49)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: allowKey,
                onPressed: onAllow,
                child: Text(allowLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                key: declineKey,
                onPressed: onDecline,
                child: const Text('Not now', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8E7E6A))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
