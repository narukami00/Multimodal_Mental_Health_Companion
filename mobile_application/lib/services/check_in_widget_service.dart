import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/day_key.dart';
import '../core/models/session_record.dart';

/// Keeps the home-screen check-in widget in step with the app.
///
/// The widget itself is a native Android layout; this only pushes the single
/// line it renders. Nothing here counts days, and nothing is rewarded.
class CheckInWidgetService {
  CheckInWidgetService._();

  static final CheckInWidgetService instance = CheckInWidgetService._();

  /// Must match the Kotlin provider's class name.
  static const androidWidgetName = 'CheckInWidgetProvider';

  /// Must match the provider's `KEY_PROMPT`.
  static const promptKey = 'checkin_prompt';

  /// Must match the provider's `LAUNCH_URI`.
  static const launchUri = 'solace://checkin';

  static const notCheckedInPrompt = 'How are you, in one word?';
  static const checkedInPrompt = 'You checked in today.';
  static const restingPrompt = 'Resting today. That counts.';

  /// The line the widget shows for today's state. Pure, so it can be verified.
  static String promptFor({
    required bool checkedInToday,
    required bool restingToday,
  }) {
    if (checkedInToday) return checkedInPrompt;
    if (restingToday) return restingPrompt;
    return notCheckedInPrompt;
  }

  /// Whether any check-in happened today.
  static bool checkedInToday(List<SessionRecord> sessions, {DateTime? now}) {
    final today = dayKey(now ?? DateTime.now());
    return sessions.any((session) => dayKey(session.createdAt) == today);
  }

  /// Whether today has been declared a rest day.
  static bool restingToday(Set<String> restDays, {DateTime? now}) {
    return restDays.contains(dayKey(now ?? DateTime.now()));
  }

  /// Pushes [prompt] to the widget and redraws it.
  ///
  /// Failures are contained: a widget that cannot refresh must never disturb
  /// the app.
  Future<void> push(String prompt) async {
    try {
      await HomeWidget.saveWidgetData<String>(promptKey, prompt);
      await HomeWidget.updateWidget(androidName: androidWidgetName);
    } catch (error) {
      debugPrint('CheckInWidgetService warning: $error');
    }
  }
}
