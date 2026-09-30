import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Result of trying to schedule the daily reminder.
enum ReminderScheduleOutcome {
  /// Registered with the OS. Android may deliver it a little late.
  scheduled,

  /// The user has notifications switched off for Solace.
  notificationsDisabled,

  /// Scheduling genuinely failed; the reason is in [ReminderScheduleResult.error].
  failed,
}

/// What actually happened, so the UI can be honest rather than optimistic.
class ReminderScheduleResult {
  const ReminderScheduleResult(this.outcome, {this.error});

  final ReminderScheduleOutcome outcome;
  final String? error;

  bool get isScheduled => outcome == ReminderScheduleOutcome.scheduled;
}

/// Schedules the gentle daily check-in reminder.
///
/// Scheduling is deliberately inexact. A wellbeing nudge does not need to be
/// punctual, and asking for exact alarms would make Android treat it as one.
/// The system may therefore deliver it a few minutes late, which is fine.
///
/// Two things this deliberately does *not* do:
/// - it never schedules against a timezone it could not resolve, because doing
///   so silently fires the reminder hours away from the chosen time;
/// - it never reports success when nothing was scheduled, because a reminder
///   that quietly does not arrive is worse than one that admits it failed.
class CheckInReminderService {
  CheckInReminderService._();

  static final CheckInReminderService instance = CheckInReminderService._();

  /// Identifier for the single daily reminder notification.
  static const reminderNotificationId = 1001;

  /// Identifier used for the on-demand test notification.
  static const testNotificationId = 1002;

  /// Dedicated channel so check-in reminders carry their own visual weight.
  static const channelId = 'solace_check_in_reminder';
  static const channelName = 'Check-in reminders';
  static const channelDescription =
      'A gentle daily reminder to check in with yourself.';

  static const _title = 'Solace';

  /// One word is a complete check-in, so the nudge asks for one word.
  static const _body = 'How are you, in one word?';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Whether the platform timezone was resolved. Scheduling is refused when it
  /// was not, rather than falling back to UTC and firing at the wrong hour.
  bool _timezoneResolved = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Properties of the reminder notification, shared by every path.
  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  /// Prepares timezone data, the plugin and the check-in channel.
  ///
  /// Failures are reported rather than hidden: [_initialized] stays false so a
  /// later call retries instead of pretending everything is fine.
  Future<bool> initialize() async {
    if (_initialized) return true;

    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _timezoneResolved = true;
    } catch (error) {
      _timezoneResolved = false;
      debugPrint('CheckInReminderService timezone warning: $error');
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
        ),
      );
    } catch (error) {
      debugPrint('CheckInReminderService init failed: $error');
      return false;
    }

    _initialized = true;
    return true;
  }

  /// Whether the OS is currently allowing Solace to post notifications.
  ///
  /// A null answer is treated as "no": on Android 13+ that means the runtime
  /// permission has not been granted.
  Future<bool> notificationsEnabled() async {
    if (!await initialize()) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks for the Android 13+ notification permission.
  Future<bool> requestPermission() async {
    if (!await initialize()) return false;
    try {
      await _android?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('CheckInReminderService permission warning: $error');
    }
    // Ask the OS what it actually decided rather than trusting the dialog.
    return notificationsEnabled();
  }

  /// Schedules, replacing any existing reminder, at [minutesPastMidnight].
  Future<ReminderScheduleResult> scheduleDaily({
    required int minutesPastMidnight,
  }) async {
    if (!await initialize()) {
      return const ReminderScheduleResult(
        ReminderScheduleOutcome.failed,
        error: 'Notifications could not be initialised.',
      );
    }

    if (!_timezoneResolved) {
      // Refuse rather than schedule against the wrong zone.
      return const ReminderScheduleResult(
        ReminderScheduleOutcome.failed,
        error: 'The device time zone could not be read.',
      );
    }

    if (!await notificationsEnabled()) {
      return const ReminderScheduleResult(
        ReminderScheduleOutcome.notificationsDisabled,
      );
    }

    await cancel();

    final hour = (minutesPastMidnight ~/ 60) % 24;
    final minute = minutesPastMidnight % 60;

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        id: reminderNotificationId,
        title: _title,
        body: _body,
        scheduledDate: next,
        notificationDetails: _notificationDetails,
        // Inexact on purpose: a nudge, not an alarm. Android may shift this by
        // a few minutes, which is an acceptable trade for not asking for the
        // exact-alarm permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (error) {
      debugPrint('CheckInReminderService schedule failed: $error');
      return ReminderScheduleResult(
        ReminderScheduleOutcome.failed,
        error: '$error',
      );
    }

    // Confirm something is genuinely registered before claiming success.
    if (!await isRegistered()) {
      return const ReminderScheduleResult(
        ReminderScheduleOutcome.failed,
        error: 'The reminder was not registered by Android.',
      );
    }

    return const ReminderScheduleResult(ReminderScheduleOutcome.scheduled);
  }

  /// Whether the reminder is actually registered with the OS.
  Future<bool> isRegistered() async {
    if (!_initialized) return false;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.any((request) => request.id == reminderNotificationId);
    } catch (_) {
      return false;
    }
  }

  /// Cancels the daily reminder if one is scheduled.
  Future<void> cancel() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: reminderNotificationId);
    } catch (error) {
      debugPrint('CheckInReminderService cancel warning: $error');
    }
  }

  /// Shows the reminder immediately, so delivery can be confirmed on the spot.
  ///
  /// Returns false when notifications are switched off or posting failed.
  Future<bool> showTestNotification() async {
    if (!await initialize()) return false;
    if (!await notificationsEnabled()) return false;

    try {
      await _plugin.show(
        id: testNotificationId,
        title: _title,
        body: _body,
        notificationDetails: _notificationDetails,
      );
      return true;
    } catch (error) {
      debugPrint('CheckInReminderService test notification failed: $error');
      return false;
    }
  }
}
