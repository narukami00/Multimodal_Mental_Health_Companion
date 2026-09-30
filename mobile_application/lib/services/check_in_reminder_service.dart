import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules the gentle daily check-in reminder.
///
/// Delivery is deliberately inexact. A wellbeing nudge does not need
/// second-accurate timing, and inexact scheduling avoids requesting the exact
/// alarm permission on Android 12+. The system may shift delivery slightly to
/// protect battery, which is an acceptable trade for this kind of reminder.
class CheckInReminderService {
  CheckInReminderService._();

  static final CheckInReminderService instance = CheckInReminderService._();

  /// Identifier for the single daily reminder notification.
  static const reminderNotificationId = 1001;

  /// Dedicated channel so check-in reminders carry their own visual weight.
  static const channelId = 'solace_check_in_reminder';
  static const channelName = 'Check-in reminders';
  static const channelDescription =
      'A gentle daily reminder to check in with yourself.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Prepares timezone data, the plugin and the check-in channel.
  ///
  /// All failures are contained: reminders are a convenience and must never
  /// prevent the app from starting.
  Future<void> initialize() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Keep the default location when the platform timezone is unavailable.
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
      debugPrint('CheckInReminderService init warning: $error');
    }

    _initialized = true;
  }

  /// Requests the Android 13+ notification permission.
  ///
  /// Returns true when notifications are allowed, and true where the platform
  /// has no runtime permission to ask for.
  Future<bool> requestPermission() async {
    await initialize();
    try {
      final granted = await _android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (error) {
      debugPrint('CheckInReminderService permission warning: $error');
      return false;
    }
  }

  /// Schedules, replacing any existing reminder, at [minutesPastMidnight].
  Future<void> scheduleDaily({required int minutesPastMidnight}) async {
    await initialize();
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
        title: 'Solace',
        // One word is a complete check-in, so the nudge asks for one word.
        body: 'How are you, in one word?',
        scheduledDate: next,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (error) {
      debugPrint('CheckInReminderService schedule warning: $error');
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
}
