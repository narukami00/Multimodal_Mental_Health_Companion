import '../../core/day_key.dart';

/// What the daily check-in reminder says.
///
/// Pure, like the rest of `domain/rhythm`: given the reminder's time, the person's name (if they gave one) and the day, it
/// returns a line. The line changes from day to day and fits the time of day, so it does not become wallpaper.
///
/// Rules, because a notification sits on a lock screen and is read in any mood:
///  * it never says anything about how the person has been, what they wrote, or how long they have been away;
///  * it never creates urgency or counts anything (no streaks, no "you missed");
///  * it always keeps the "one word is enough" promise, so replying never feels like a task.
abstract final class ReminderWording {
  static const _morning = [
    'A new day. How are you, in one word?',
    'Morning. One word for how you are?',
    'Before the day gets going: how are you?',
    'A quiet minute for you this morning?',
  ];

  static const _afternoon = [
    'A small pause. How are you, in one word?',
    'How is the day treating you? One word is plenty.',
    'Take a minute for yourself?',
    'Midday check-in: one word is enough.',
  ];

  static const _evening = [
    'How was today, in one word?',
    'Winding down. One word for how you are?',
    'A quiet minute before the day ends?',
    'Evening. How are you, in one word?',
  ];

  static const _night = [
    'Still up? One word for how you are is plenty.',
    'A gentle minute for you tonight?',
    'How are you, in one word?',
  ];

  /// The line for a reminder at [minutesPastMidnight] on [day]. [name] is added to some lines, not all, so it does not feel
  /// like a template; a blank name is the same as none.
  static String body({required int minutesPastMidnight, required DateTime day, String? name}) {
    final hour = (minutesPastMidnight ~/ 60) % 24;
    final pool = hour >= 5 && hour < 12
        ? _morning
        : hour >= 12 && hour < 17
        ? _afternoon
        : hour >= 17 && hour < 22
        ? _evening
        : _night;
    final ordinal = dateOnly(day).difference(DateTime(2024)).inDays;
    final line = pool[ordinal % pool.length];
    final first = _firstName(name);
    // Every other day the line is addressed to them by name.
    if (first == null || ordinal.isEven) return line;
    return '$first, ${line[0].toLowerCase()}${line.substring(1)}';
  }

  static String? _firstName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed.split(RegExp(r'\s+')).first;
  }
}
