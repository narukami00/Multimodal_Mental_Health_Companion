import 'package:flutter/foundation.dart';

import '../../core/models/suggestion_record.dart';
import '../../core/models/user_profile.dart';
import '../../domain/rhythm/reminder_lapse_policy.dart';
import '../../domain/suggestions/suggestion_push_plan.dart';
import '../../services/check_in_reminder_service.dart';

/// Keeps the scheduled idea pushes in step with what the plan says.
///
/// Home calls [sync] whenever anything it depends on changes, so it only touches
/// the OS when the plan actually moved. Until something has been scheduled and
/// the plan is empty there is nothing to do, which also keeps it out of the way
/// of anyone who never turned pushes on.
class IdeaPushSync {
  IdeaPushSync({
    Future<bool> Function(List<DateTime> times)? sink,
  }) : _sink = sink ?? CheckInReminderService.instance.syncIdeaPushes;

  final Future<bool> Function(List<DateTime> times) _sink;
  List<DateTime>? _last;

  Future<void> sync({
    required UserProfile profile,
    required List<SuggestionRecord> history,
    required DateTime? lastCheckInAt,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final times = SuggestionPushPlan.plan(
      now: current,
      enabled: profile.ideaPushEnabled,
      daysSinceLastCheckIn: ReminderLapsePolicy.daysSince(
        lastCheckInAt,
        now: current,
      ),
      ideaOfferedToday: history.any(
        (record) =>
            record.proactive &&
            record.shownAt.year == current.year &&
            record.shownAt.month == current.month &&
            record.shownAt.day == current.day,
      ),
      reminderEnabled: profile.reminderEnabled,
      reminderMinutes: profile.reminderMinutes,
      quietEnabled: profile.quietHoursEnabled,
      quietStart: profile.quietStartMinutes,
      quietEnd: profile.quietEndMinutes,
    );

    if (_last == null && times.isEmpty) return;
    if (listEquals(_last, times)) return;
    _last = times;
    await _sink(times);
  }
}
