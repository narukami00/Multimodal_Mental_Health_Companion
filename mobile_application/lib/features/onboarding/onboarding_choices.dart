import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/theme/app_theme.dart';
import '../../services/model_pack_store.dart';
import '../../services/phone_speech.dart';
import '../../services/face_reading_choice.dart';
import '../../services/stt_model_store.dart';
import '../consent/consent_controller.dart';
import '../models/on_device_model_widgets.dart';
import '../profile/profile_controller.dart';

/// The "what may Solace read" choices shown in onboarding. They are the same switches as in Permissions & privacy,
/// so nothing is decided that can't be changed later, and leaving them off just means being asked at the moment it matters.
class ReadingChoices extends StatelessWidget {
  const ReadingChoices({required this.consent, super.key});

  final ConsentController consent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: consent,
      builder: (context, _) => Column(
        children: [
          _ChoiceTile(
            key: const ValueKey('onboarding-consent-voice'),
            icon: Icons.graphic_eq_rounded,
            color: const Color(0xFFD9674A),
            title: 'Notice how I sound',
            detail: 'Your words and voice are read once by your companion server to guess if an entry sounds low, tense or '
                'upbeat. Never kept, and only a weak guess.',
            value: consent.isGranted(ConsentKey.emotionEstimate),
            onChanged: (on) => on ? consent.grant(ConsentKey.emotionEstimate) : consent.decline(ConsentKey.emotionEstimate),
          ),
          const SizedBox(height: 10),
          _ChoiceTile(
            key: const ValueKey('onboarding-consent-face'),
            icon: Icons.face_retouching_natural_rounded,
            color: const Color(0xFF6E73C8),
            title: 'Notice my face in video',
            detail: consent.isGranted(ConsentKey.emotionEstimate)
                ? 'Only while the camera is on. Pictures are never saved, and you can have your face read on this phone '
                    'instead of your server.'
                : 'Needs "Notice how I sound" first. Only while the camera is on, and pictures are never saved.',
            enabled: consent.isGranted(ConsentKey.emotionEstimate),
            value: consent.isGranted(ConsentKey.faceFeatures),
            onChanged: (on) => on ? consent.grant(ConsentKey.faceFeatures) : consent.decline(ConsentKey.faceFeatures),
          ),
          const SizedBox(height: 10),
          const Text(
            'Both are off until you say yes. Voice and video journals still work if you leave them off, and you can change this any '
            'time in Permissions & privacy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.mutedInk, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final bool enabled;

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
              child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: color, size: 21)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(detail, style: const TextStyle(color: AppColors.mutedInk, fontSize: 12, height: 1.35, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null),
          ],
        ),
      ),
    );
  }
}

/// Offers the downloads that let voice and video journals work without the server. Optional: it says plainly that the
/// download needs the companion server to be on right now, and that it can wait.
class OfflineModelChoices extends StatelessWidget {
  const OfflineModelChoices({this.speech, this.face, this.choice, this.offerFace = true, super.key});

  final ModelPackStore? speech;
  final ModelPackStore? face;
  final FaceReadingChoice? choice;

  /// Whether the camera models are offered too (only when the person allows their face to be read).
  final bool offerFace;

  @override
  Widget build(BuildContext context) {
    final faceChoice = choice ?? PhoneFace.choice;
    return Column(
      children: [
        OnDeviceModelsPanel(
          key: ValueKey('models-panel-face-$offerFace'), // its rows are fixed when it starts, so a new set is a new panel
          rows: [
            OnDeviceModelRow(
              store: speech ?? PhoneSpeech.store,
              keyPrefix: 'offline-model',
              icon: Icons.graphic_eq_rounded,
              color: const Color(0xFFD9674A),
              title: 'Offline transcription',
              offer: 'Writes your recordings down on this phone, with no server. About ${SttModelStore.approximateMegabytes} MB.',
              onText: () => 'Ready. Voice and video journals can be written down without the server.',
              removeTitle: 'Remove offline transcription?',
              removeBody: 'Voice and video journals will then wait for the companion server to be written down. '
                  'You can download it again any time.',
            ),
            if (offerFace && PhoneFace.pipelineReady)
              OnDeviceModelRow(
                store: face ?? PhoneFace.store,
                keyPrefix: 'face-model',
                icon: Icons.face_retouching_natural_rounded,
                color: const Color(0xFF6E73C8),
                title: 'Read my face on this phone',
                offer: 'Only numbers about your face leave the phone, never pictures. About ${FaceModelStore.approximateMegabytes} MB.',
                onText: () => faceChoice.place == FaceReadingPlace.phone
                    ? 'Ready. Your face is read on this phone and only numbers leave it.'
                    : 'On this phone, but your server still reads your face: switch in Permissions & privacy.',
                removeTitle: 'Remove the camera models?',
                removeBody: 'Your face will then be read by the companion server, with the video frames sent to it. '
                    'You can download the models again any time.',
                onInstalled: () => faceChoice.set(FaceReadingPlace.phone),
                onRemoved: () => faceChoice.set(FaceReadingPlace.server),
              ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Downloaded once from your own companion server, so it needs to be on right now. Not now? You can get these any time in '
          'Permissions & privacy.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.mutedInk, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// The state of the daily check-in reminder, shown in onboarding: what it will do, or that it is set.
class ReminderChoice extends StatelessWidget {
  const ReminderChoice({required this.controller, super.key});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final profile = controller.profile;
        final time = TimeOfDay(hour: (profile.reminderMinutes ~/ 60) % 24, minute: profile.reminderMinutes % 60).format(context);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(profile.reminderEnabled ? Icons.check_circle_outline_rounded : Icons.notifications_none_rounded, color: AppColors.amber, size: 21),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    profile.reminderEnabled
                        ? 'Reminder set for $time every day. You can change or stop it in Settings.'
                        : 'One gentle nudge a day, at a time you pick. Optional, and easy to stop.',
                    key: const ValueKey('onboarding-reminder-status'),
                    style: const TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
