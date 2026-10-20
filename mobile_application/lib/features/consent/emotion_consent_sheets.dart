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
      body: 'Your words (and your voice, for a recording) are sent to the companion '
          'server and read once to guess whether the entry sounds low, tense or '
          'upbeat. Your voice is never kept, and it is only a weak guess, never '
          'a diagnosis. You can turn this off any time in What Sol remembers.',
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
      body: 'While the camera is on, frames are sent live to the companion server '
          'and read in memory to help judge whether you look tense or low. '
          'They are never saved, and it only softens how Sol talks. Your words '
          'still matter most. You can turn this off any time in What Sol remembers.',
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
              height: 50,
              child: ElevatedButton(
                key: allowKey,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB534),
                  foregroundColor: const Color(0xFF3D2E14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
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
