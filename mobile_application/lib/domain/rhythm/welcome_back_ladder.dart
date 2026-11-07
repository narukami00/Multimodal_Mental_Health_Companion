import 'reminder_lapse_policy.dart';

/// How long someone has been away, in the steps the welcome changes at.
enum ReturnTier {
  /// Still around: nothing is said.
  none,

  /// A few days. A light hello.
  brief,

  /// About a week or more.
  week,

  /// Two weeks or more: the daily reminder has been paused.
  longAway,

  /// A month or more. Offers a fresh start rather than a catch-up.
  freshStart,
}

/// What the app says when someone comes back, scaled to how long they were away.
///
/// Pure, like [ReminderLapsePolicy]. The longer the gap, the gentler and shorter the welcome gets: it never counts the
/// days, never says anything was missed or lost, never asks for a catch-up, and always offers the smallest possible
/// way back in.
abstract final class WelcomeBackLadder {
  static const briefDays = 3;
  static const weekDays = 7;
  static const longAwayDays = ReminderLapsePolicy.lapseDays;
  static const freshStartDays = 30;

  static ReturnTier tierFor(int? daysSinceLastCheckIn) {
    final days = daysSinceLastCheckIn;
    if (days == null || days < briefDays) return ReturnTier.none;
    if (days < weekDays) return ReturnTier.brief;
    if (days < longAwayDays) return ReturnTier.week;
    if (days < freshStartDays) return ReturnTier.longAway;
    return ReturnTier.freshStart;
  }

  /// Whether to say anything now: someone is away enough, and the welcome has not already been given for this lapse
  /// (it is "given" once it was shown after their last check-in).
  static bool shouldShow({
    required int? daysSinceLastCheckIn,
    required DateTime? lastCheckIn,
    required DateTime? lastShownAt,
  }) {
    if (tierFor(daysSinceLastCheckIn) == ReturnTier.none) return false;
    if (lastShownAt == null) return true;
    if (lastCheckIn == null) return false;
    return lastShownAt.isBefore(lastCheckIn);
  }

  /// The welcome line, or null when nothing should be said. [name] is used if there is one; [reminderPaused] adds the
  /// honest note that the daily reminder was switched off while they were away.
  static String? message(ReturnTier tier, {String? name, bool reminderPaused = false}) {
    final first = name?.trim().split(RegExp(r'\s+')).first ?? '';
    final who = first.isEmpty ? '' : ', $first';
    switch (tier) {
      case ReturnTier.none:
        return null;
      case ReturnTier.brief:
        return 'Welcome back$who. No catch-up needed. Whenever you are ready, one word is enough.';
      case ReturnTier.week:
        return 'Good to see you$who. It has been a little while, and that is okay. Start as small as you like.';
      case ReturnTier.longAway:
        return 'Welcome back$who. Life gets full. No catch-up needed, and everything you wrote is still here.'
            '${reminderPaused ? ' Your reminder is paused until you turn it back on.' : ''}';
      case ReturnTier.freshStart:
        return 'A fresh start$who, whenever you want one. No catch-up needed: your journal is just as you left it.'
            '${reminderPaused ? ' Your reminder is paused until you turn it back on.' : ''}';
    }
  }

  /// The smallest way back in, offered under the welcome.
  static const oneWordLabel = 'Check in with one word';
}
