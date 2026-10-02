import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/models/habit_reminder.dart';

/// Manages habit reminders: CRUD, persistence, and notification scheduling.
///
/// Each habit can generate up to 7 notifications (one per day of the week).
/// Notification IDs are allocated from a base offset per habit index to avoid
/// collisions with the check-in reminder (1001/1002) and idea pushes (2001-2003).
class HabitController extends ChangeNotifier {
  HabitController({required SharedPreferences preferences})
    : _preferences = preferences;

  static const _key = 'profile.habit_reminders';

  /// Base notification ID for habit reminders. Each habit uses 7 consecutive
  /// IDs starting from _baseNotificationId + (index * 7).
  static const _baseNotificationId = 3000;

  /// Maximum number of habits to prevent notification ID overflow.
  static const maxHabits = 20;

  static const _channelId = 'solace_habit_reminders';
  static const _channelName = 'Habit reminders';
  static const _channelDescription =
      'Gentle reminders for habits and hobbies you chose to keep.';

  final SharedPreferences _preferences;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  List<HabitReminder> _reminders = [];
  bool _isLoaded = false;
  bool _initialized = false;
  bool _timezoneResolved = false;

  List<HabitReminder> get reminders => List.unmodifiable(_reminders);
  bool get isLoaded => _isLoaded;
  int get count => _reminders.length;
  bool get canAddMore => _reminders.length < maxHabits;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;

    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _timezoneResolved = true;
    } catch (error) {
      _timezoneResolved = false;
      debugPrint('HabitController timezone warning: $error');
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.defaultImportance,
        ),
      );
    } catch (error) {
      debugPrint('HabitController init failed: $error');
      return false;
    }

    _initialized = true;
    return true;
  }

  Future<void> load() async {
    final encoded = _preferences.getString(_key);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is List) {
          _reminders = [
            for (final item in decoded)
              if (item is Map<String, dynamic>)
                HabitReminder.fromMap(item),
          ].where((r) => r.id.isNotEmpty && r.title.isNotEmpty).toList();
        }
      } on FormatException {
        // Malformed data should not prevent the app from opening.
      }
    }
    _isLoaded = true;
    notifyListeners();

    // Reschedule all enabled reminders on load (in case OS dropped them).
    await _ensureInitialized();
    await _rescheduleAll();
  }

  Future<void> add(HabitReminder reminder) async {
    if (!canAddMore) return;
    _reminders = [..._reminders, reminder];
    await _persist();
    await _scheduleReminder(reminder);
  }

  Future<void> update(HabitReminder reminder) async {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index == -1) return;
    await _cancelReminder(_reminders[index]);
    _reminders = [
      for (var i = 0; i < _reminders.length; i++)
        if (i == index) reminder else _reminders[i],
    ];
    await _persist();
    await _scheduleReminder(reminder);
  }

  Future<void> remove(String id) async {
    final existing = _reminders.where((r) => r.id == id).firstOrNull;
    if (existing == null) return;
    await _cancelReminder(existing);
    _reminders = _reminders.where((r) => r.id != id).toList();
    await _persist();
  }

  Future<void> toggleEnabled(String id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final toggled = _reminders[index].copyWith(
      enabled: !_reminders[index].enabled,
    );
    _reminders = [
      for (var i = 0; i < _reminders.length; i++)
        if (i == index) toggled else _reminders[i],
    ];
    await _persist();
    if (toggled.enabled) {
      await _scheduleReminder(toggled);
    } else {
      await _cancelReminder(toggled);
    }
  }

  /// Unique notification ID for a habit on a specific day of the week.
  int _notificationId(HabitReminder reminder, int dayOfWeek) {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index == -1) return _baseNotificationId;
    return _baseNotificationId + (index * 7) + (dayOfWeek - 1);
  }

  Future<void> _scheduleReminder(HabitReminder reminder) async {
    if (!reminder.enabled) return;
    if (!await _ensureInitialized()) return;
    if (!_timezoneResolved) return;

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );

    for (final day in reminder.days) {
      final id = _notificationId(reminder, day);
      final next = _nextOccurrence(reminder.hour, reminder.minute, day);

      try {
        await _plugin.zonedSchedule(
          id: id,
          title: 'Solace',
          body: reminder.title,
          scheduledDate: next,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      } catch (error) {
        debugPrint('HabitController schedule failed for ${reminder.id}: $error');
      }
    }
  }

  Future<void> _cancelReminder(HabitReminder reminder) async {
    if (!_initialized) return;
    for (var day = 1; day <= 7; day++) {
      try {
        await _plugin.cancel(id: _notificationId(reminder, day));
      } catch (error) {
        debugPrint('HabitController cancel warning: $error');
      }
    }
  }

  Future<void> _rescheduleAll() async {
    for (final reminder in _reminders) {
      if (reminder.enabled) {
        await _scheduleReminder(reminder);
      }
    }
  }

  /// Finds the next occurrence of a given day-of-week and time.
  tz.TZDateTime _nextOccurrence(int hour, int minute, int dayOfWeek) {
    final now = tz.TZDateTime.now(tz.local);
    // DateTime.weekday: 1=Monday, 7=Sunday — matches our model.
    var daysUntil = dayOfWeek - now.weekday;
    if (daysUntil < 0) daysUntil += 7;

    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + daysUntil,
      hour,
      minute,
    );

    // If today is the target day but the time has passed, schedule next week.
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 7));
    }

    return next;
  }

  Future<void> _persist() async {
    final encoded = jsonEncode([
      for (final r in _reminders) r.toMap(),
    ]);
    await _preferences.setString(_key, encoded);
    notifyListeners();
  }
}
