import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/rhythm/quick_reply.dart';

/// Where check-ins typed outside the app wait until the app is open and can save them properly.
///
/// Two doors lead in: the reply box in the reminder notification (a background Dart handler writes to
/// preferences) and the home-screen pop-up (native code writes to its own file, read through a channel).
/// Nothing here screens, reads or saves words as an entry; it only holds them.
class QuickReplyInbox {
  const QuickReplyInbox._();

  static const preferenceKey = 'quick_replies.pending';
  static const _native = MethodChannel('com.sysmentalhealth.solace_mobile/quick_inbox');

  /// Holds one reply. Safe to call from the background handler.
  static Future<void> add(SharedPreferences prefs, QuickReply reply) async {
    await prefs.reload();
    final waiting = prefs.getStringList(preferenceKey) ?? const <String>[];
    await prefs.setStringList(preferenceKey, [...waiting, reply.encode()]);
  }

  /// Takes everything that is waiting, oldest first, and empties both doors.
  static Future<List<QuickReply>> drain(SharedPreferences prefs) async {
    final replies = <QuickReply>[];

    await prefs.reload();
    final waiting = prefs.getStringList(preferenceKey) ?? const <String>[];
    if (waiting.isNotEmpty) {
      // Cleared before anything is saved: a crash then loses at most the replies being saved, and never
      // saves one twice.
      await prefs.remove(preferenceKey);
      for (final raw in waiting) {
        final reply = QuickReply.decode(raw);
        if (reply != null) replies.add(reply);
      }
    }

    try {
      final fromWidget = await _native.invokeListMethod<Map<Object?, Object?>>('drain') ?? const [];
      for (final item in fromWidget) {
        final text = cleanQuickReply(item['text'] as String?);
        final ms = item['at'];
        if (text == null || ms is! int) continue;
        replies.add(QuickReply(text: text, at: DateTime.fromMillisecondsSinceEpoch(ms)));
      }
    } on MissingPluginException {
      // Tests and non-Android hosts have no widget pop-up.
    } catch (error) {
      debugPrint('[QuickReply] could not read the widget inbox: ${error.runtimeType}');
    }

    replies.sort((a, b) => a.at.compareTo(b.at));
    return replies;
  }
}

/// The id of the reply box action in the reminder notification.
const quickReplyActionId = 'solace_quick_reply';

/// The notification that thanks the person once a reply is held. It goes away by itself.
const quickReplyThanksId = 1003;

/// Runs when someone sends the reply box in the reminder notification, whether or not the app is open. It runs in
/// its own isolate, so it does the least possible: hold the words, say thanks, and leave the rest to the app.
@pragma('vm:entry-point')
Future<void> quickReplyBackground(NotificationResponse response) async {
  if (response.actionId != quickReplyActionId) return;
  final text = cleanQuickReply(response.input);
  if (text == null) return;
  DartPluginRegistrant.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    await QuickReplyInbox.add(prefs, QuickReply(text: text, at: DateTime.now()));

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_solace')),
    );
    await plugin.show(
      id: quickReplyThanksId,
      title: 'Solace',
      body: 'Thank you for checking in.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'solace_check_in_reminder',
          'Check-in reminders',
          channelDescription: 'A gentle daily reminder to check in with yourself.',
          icon: 'ic_stat_solace',
          timeoutAfter: 4000,
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  } catch (error) {
    debugPrint('[QuickReply] could not hold a reply: ${error.runtimeType}');
  }
}
