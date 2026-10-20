import 'package:flutter/material.dart';

import '../../core/models/sleep_window.dart';
import '../../core/widgets/visual_kit.dart';
import 'profile_controller.dart';

/// Asks for a sleep window with two time pickers, bedtime then wake time.
///
/// Returns null if either picker is dismissed, so nothing half-chosen is ever
/// saved. The pickers open at [initial] when there is one, and otherwise at a
/// common bedtime and wake time. Those are only where the dial starts, not a
/// stored default: nothing is saved until the user confirms both.
Future<SleepWindow?> pickSleepWindow(
  BuildContext context, {
  SleepWindow? initial,
  String startHelp = 'When do you usually go to sleep?',
  String endHelp = 'When do you usually wake up?',
}) async {
  final start = initial?.startMinutes ?? 23 * 60;
  final end = initial?.endMinutes ?? 7 * 60;

  final bedtime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
    helpText: startHelp,
  );
  if (bedtime == null || !context.mounted) return null;

  final wake = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60),
    helpText: endHelp,
  );
  if (wake == null) return null;

  return SleepWindow(
    startMinutes: bedtime.hour * 60 + bedtime.minute,
    endMinutes: wake.hour * 60 + wake.minute,
  );
}

String _clock(BuildContext context, int minutes) =>
    TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60).format(context);

/// The "Sleep" block of the app settings sheet: usual hours, an optional
/// separate weekend window, and a one-off copy into quiet hours.
///
/// Stateless on purpose: the sheet already rebuilds from the controller, so
/// every value shown here is the stored one.
class SleepHoursSettings extends StatelessWidget {
  const SleepHoursSettings({required this.controller, super.key});

  final ProfileController controller;

  Future<void> _chooseUsual(BuildContext context) async {
    final profile = controller.profile;
    final window = await pickSleepWindow(
      context,
      initial: profile.sleepWindowFor(weekend: false),
    );
    if (window == null) return;
    await controller.setSleepHours(
      startMinutes: window.startMinutes,
      endMinutes: window.endMinutes,
    );
  }

  Future<void> _chooseWeekend(BuildContext context) async {
    final profile = controller.profile;
    final window = await pickSleepWindow(
      context,
      initial:
          profile.weekendSleepStartMinutes == null ||
              profile.weekendSleepEndMinutes == null
          ? profile.sleepWindowFor(weekend: false)
          : SleepWindow(
              startMinutes: profile.weekendSleepStartMinutes!,
              endMinutes: profile.weekendSleepEndMinutes!,
            ),
      startHelp: 'Weekend nights: when do you go to sleep?',
      endHelp: 'Weekend nights: when do you wake up?',
    );
    if (window == null) return;
    await controller.setWeekendSleepHours(
      startMinutes: window.startMinutes,
      endMinutes: window.endMinutes,
    );
  }

  Future<void> _turnWeekendsOn(BuildContext context, bool differ) async {
    await controller.setWeekendsDiffer(differ);
    final profile = controller.profile;
    // Switching on with no weekend hours yet: ask for them right away, since a
    // toggle with nothing behind it would change no behavior.
    if (differ && profile.weekendSleepStartMinutes == null && context.mounted) {
      await _chooseWeekend(context);
      if (controller.profile.weekendSleepStartMinutes == null) {
        // Nothing chosen, so do not leave a switch on that does nothing.
        await controller.setWeekendsDiffer(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    final usual = profile.sleepWindowFor(weekend: false);
    final quietMatches =
        profile.quietHoursEnabled &&
        usual != null &&
        profile.quietStartMinutes == usual.startMinutes &&
        profile.quietEndMinutes == usual.endMinutes;

    return Column(
      key: const ValueKey('setting-sleep-hours'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            IconTile(
              icon: Icons.nightlight_round,
              color: Color(0xFF6E73C8),
              size: 38,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usual sleep hours',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: kitInk,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Helps Solace pitch ideas to how much energy you probably '
                    'have. Only ever kept on this phone.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: kitMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (usual == null)
          _Pill(
            key: const ValueKey('sleep-set'),
            icon: Icons.add_rounded,
            label: profile.sleepHoursSkipped
                ? 'Skipped earlier. Set sleep hours'
                : 'Set sleep hours',
            onTap: () => _chooseUsual(context),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                key: const ValueKey('sleep-edit'),
                icon: Icons.schedule_rounded,
                label:
                    '${_clock(context, usual.startMinutes)}'
                    ' to ${_clock(context, usual.endMinutes)}',
                onTap: () => _chooseUsual(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _WeekendRow(
            differs: profile.weekendSleepDiffers,
            onChanged: (on) => _turnWeekendsOn(context, on),
          ),
          if (profile.weekendSleepDiffers &&
              profile.weekendSleepStartMinutes != null &&
              profile.weekendSleepEndMinutes != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                children: [
                  _Pill(
                    key: const ValueKey('sleep-weekend-edit'),
                    icon: Icons.weekend_outlined,
                    label:
                        'Weekends: '
                        '${_clock(context, profile.weekendSleepStartMinutes!)}'
                        ' to ${_clock(context, profile.weekendSleepEndMinutes!)}',
                    onTap: () => _chooseWeekend(context),
                  ),
                ],
              ),
            ),
          if (!quietMatches)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                children: [
                  _Pill(
                    key: const ValueKey('sleep-use-as-quiet'),
                    icon: Icons.bedtime_outlined,
                    label: 'Use these as quiet hours too',
                    onTap: controller.useSleepHoursAsQuietHours,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// A tappable pill in the same style as the other settings time chips.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF3DC),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: kitAmber),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A6A1C),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekendRow extends StatelessWidget {
  const _WeekendRow({required this.differs, required this.onChanged});

  final bool differs;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Weekends differ',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: kitInk,
            ),
          ),
        ),
        Switch(
          key: const ValueKey('toggle-weekends-differ'),
          value: differs,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
