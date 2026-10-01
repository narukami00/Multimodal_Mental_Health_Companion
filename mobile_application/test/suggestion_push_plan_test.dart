import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/suggestions/suggestion_push_plan.dart';

List<DateTime> _plan({
  DateTime? now,
  bool enabled = true,
  int? away = 0,
  bool offered = false,
  bool reminder = false,
  int reminderAt = 20 * 60 + 30,
  bool quiet = false,
  int quietStart = 22 * 60,
  int quietEnd = 7 * 60,
}) {
  return SuggestionPushPlan.plan(
    now: now ?? DateTime(2026, 9, 22, 8),
    enabled: enabled,
    daysSinceLastCheckIn: away,
    ideaOfferedToday: offered,
    reminderEnabled: reminder,
    reminderMinutes: reminderAt,
    quietEnabled: quiet,
    quietStart: quietStart,
    quietEnd: quietEnd,
  );
}

void main() {
  group('quiet hours', () {
    test('a window that crosses midnight covers both sides of it', () {
      const start = 22 * 60;
      const end = 7 * 60;

      expect(SuggestionPushPlan.inQuietHours(23 * 60, start, end), isTrue);
      expect(SuggestionPushPlan.inQuietHours(2 * 60, start, end), isTrue);
      expect(SuggestionPushPlan.inQuietHours(7 * 60, start, end), isFalse);
      expect(SuggestionPushPlan.inQuietHours(12 * 60, start, end), isFalse);
    });

    test('a same-day window is a plain range, and an empty one is nothing', () {
      expect(SuggestionPushPlan.inQuietHours(13 * 60, 12 * 60, 14 * 60), isTrue);
      expect(SuggestionPushPlan.inQuietHours(15 * 60, 12 * 60, 14 * 60), isFalse);
      expect(SuggestionPushPlan.inQuietHours(60, 600, 600), isFalse);
    });
  });

  group('the plan', () {
    test('is empty when idea pushes are off', () {
      expect(_plan(enabled: false), isEmpty);
    });

    test('plans one push a day for three days, mid-morning', () {
      final times = _plan();

      expect(times, [
        DateTime(2026, 9, 22, 10),
        DateTime(2026, 9, 23, 10),
        DateTime(2026, 9, 24, 10),
      ]);
    });

    test('skips today once the idea has already been shown, and past times', () {
      expect(_plan(offered: true).first, DateTime(2026, 9, 23, 10));
      expect(_plan(now: DateTime(2026, 9, 22, 11)).first.day, 23);
    });

    test('runs dry as someone stays away, then stops (no backlog)', () {
      expect(_plan(away: 1), hasLength(2));
      expect(_plan(away: 2), hasLength(1));
      expect(_plan(away: 3), isEmpty);
      expect(_plan(away: 20), isEmpty);
    });

    test('defers past the sleep window, at most twice, then drops the day', () {
      // Window 09:00-11:30 swallows the first attempt (10:00) and the second
      // (11:30 is the boundary, so it is free).
      final deferred = _plan(quiet: true, quietStart: 9 * 60, quietEnd: 11 * 60);
      expect(deferred.first, DateTime(2026, 9, 22, 11, 30));

      // A window covering all three attempts drops the day entirely.
      final dropped = _plan(quiet: true, quietStart: 9 * 60, quietEnd: 14 * 60);
      expect(dropped, isEmpty);
    });

    test('gives way to the check-in reminder', () {
      // Reminder at 10:30 collides with 10:00 and 11:30 clears it by 60.
      final times = _plan(reminder: true, reminderAt: 10 * 60 + 30);

      expect(times.first, DateTime(2026, 9, 22, 11, 30));
    });
  });
}
