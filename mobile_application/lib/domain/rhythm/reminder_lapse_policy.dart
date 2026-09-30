/// Decides what happens to the daily reminder once someone has drifted away.
///
/// The only direction this can move is *quieter*. Reminders are never made more
/// frequent, never re-worded to create urgency, and a lapse is never described
/// as a loss. Pure, so the boundaries can be verified directly.
abstract final class ReminderLapsePolicy {
  /// Days away before the app stops nudging.
  static const lapseDays = 14;

  /// Whether the reminder should be paused.
  ///
  /// A user who has never checked in is not "lapsing", so null means no.
  static bool shouldPauseReminder(int? daysSinceLastCheckIn) {
    return daysSinceLastCheckIn != null && daysSinceLastCheckIn >= lapseDays;
  }

  /// The single line shown when someone comes back after a long gap.
  ///
  /// It names the paused reminder, because silently changing a setting the user
  /// chose would be dishonest.
  static String? lapseMessage(int? daysSinceLastCheckIn) {
    if (!shouldPauseReminder(daysSinceLastCheckIn)) return null;
    return 'No catch-up needed. One word is enough. '
        'Your reminder is paused until you turn it back on.';
  }

  /// Whether to show that line now.
  ///
  /// Shown at most once per lapse: it must not have been shown since the last
  /// check-in.
  static bool shouldShowWelcomeBack({
    required int? daysSinceLastCheckIn,
    required DateTime? lastCheckIn,
    required DateTime? lastShownAt,
  }) {
    if (!shouldPauseReminder(daysSinceLastCheckIn)) return false;
    if (lastShownAt == null) return true;
    if (lastCheckIn == null) return false;
    return lastShownAt.isBefore(lastCheckIn);
  }
}
