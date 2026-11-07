import 'package:flutter/material.dart';

import '../../domain/rhythm/reminder_lapse_policy.dart';
import '../../domain/rhythm/welcome_back_ladder.dart';
import '../profile/profile_controller.dart';
import '../sessions/session_controller.dart';

/// The single line shown when someone returns after a long gap.
///
/// Shown at most once per lapse, and it names the paused reminder rather than
/// changing that setting silently. Renders nothing the rest of the time, so it
/// cannot become permanent furniture on the home screen.
class WelcomeBackNotice extends StatefulWidget {
  const WelcomeBackNotice({
    required this.sessionController,
    required this.profileController,
    this.onOneWord,
    super.key,
  });

  final SessionController sessionController;
  final ProfileController profileController;

  /// Opens the smallest possible check-in. Offered under the welcome when given.
  final VoidCallback? onOneWord;

  @override
  State<WelcomeBackNotice> createState() => _WelcomeBackNoticeState();
}

class _WelcomeBackNoticeState extends State<WelcomeBackNotice> {
  /// Decided once on mount: the line belongs to the moment the user returns,
  /// so it must not appear again on the next launch.
  String? _message;

  @override
  void initState() {
    super.initState();

    final lastCheckIn = widget.sessionController.lastCheckInAt;
    final daysSince = ReminderLapsePolicy.daysSince(lastCheckIn);

    final shouldShow = WelcomeBackLadder.shouldShow(
      daysSinceLastCheckIn: daysSince,
      lastCheckIn: lastCheckIn,
      lastShownAt: widget.profileController.profile.welcomeBackShownAt,
    );
    if (!shouldShow) return;

    _message = WelcomeBackLadder.message(
      WelcomeBackLadder.tierFor(daysSince),
      name: widget.profileController.profile.displayName,
      reminderPaused: ReminderLapsePolicy.shouldPauseReminder(daysSince),
    );
    if (_message == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await widget.profileController.markWelcomeBackShown();
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9EE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF6E9CE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.wb_sunny_outlined,
            size: 18,
            color: Color(0xFFB57A12),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                    color: Color(0xFF7A5B1E),
                  ),
                ),
                if (widget.onOneWord != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      key: const ValueKey('welcome-back-one-word'),
                      onPressed: widget.onOneWord,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        foregroundColor: const Color(0xFFB57A12),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                      child: const Text(WelcomeBackLadder.oneWordLabel),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
