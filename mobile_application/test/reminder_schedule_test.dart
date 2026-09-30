import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/rhythm/reminder_schedule.dart';

void main() {
  group('ReminderSchedule.nextOccurrence', () {
    // 7:35 AM, the time from the bug report.
    const morning = 7 * 60 + 35;

    test('fires later today when the time is still ahead', () {
      final now = DateTime(2026, 9, 26, 6, 0);
      final next = ReminderSchedule.nextOccurrence(morning, now: now);

      expect(next, DateTime(2026, 9, 26, 7, 35));
      expect(ReminderSchedule.isToday(morning, now: now), isTrue);
    });

    test('rolls to tomorrow once the time has passed', () {
      final now = DateTime(2026, 9, 26, 9, 0);
      final next = ReminderSchedule.nextOccurrence(morning, now: now);

      // The whole point of the fix: 7:35 means 7:35, not "whenever".
      expect(next, DateTime(2026, 9, 27, 7, 35));
      expect(ReminderSchedule.isToday(morning, now: now), isFalse);
    });

    test('rolls over at the exact moment rather than repeating', () {
      final now = DateTime(2026, 9, 26, 7, 35);
      final next = ReminderSchedule.nextOccurrence(morning, now: now);

      expect(next, DateTime(2026, 9, 27, 7, 35));
    });

    test('handles an evening time across the day boundary', () {
      const evening = 20 * 60 + 30;
      final now = DateTime(2026, 9, 26, 23, 0);
      final next = ReminderSchedule.nextOccurrence(evening, now: now);

      expect(next, DateTime(2026, 9, 27, 20, 30));
    });

    test('handles midnight without wrapping to the wrong day', () {
      final now = DateTime(2026, 9, 26, 12, 0);
      final next = ReminderSchedule.nextOccurrence(0, now: now);

      expect(next, DateTime(2026, 9, 27, 0, 0));
    });

    test('next occurrence is always in the future', () {
      const times = [0, 1, 7 * 60 + 35, 12 * 60, 20 * 60 + 30, 23 * 60 + 59];
      final now = DateTime(2026, 9, 26, 13, 17);

      for (final minutes in times) {
        expect(
          ReminderSchedule.nextOccurrence(minutes, now: now).isAfter(now),
          isTrue,
          reason: 'minutes=$minutes must schedule ahead of now',
        );
      }
    });
  });
}
