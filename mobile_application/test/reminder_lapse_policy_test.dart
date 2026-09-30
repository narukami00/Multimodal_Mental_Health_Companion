import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/rhythm/reminder_lapse_policy.dart';

void main() {
  group('shouldPauseReminder', () {
    test('stays quiet while the user is still around', () {
      expect(ReminderLapsePolicy.shouldPauseReminder(0), isFalse);
      expect(ReminderLapsePolicy.shouldPauseReminder(1), isFalse);
      expect(ReminderLapsePolicy.shouldPauseReminder(3), isFalse);
      expect(ReminderLapsePolicy.shouldPauseReminder(13), isFalse);
    });

    test('pauses at the lapse boundary and beyond', () {
      expect(ReminderLapsePolicy.shouldPauseReminder(14), isTrue);
      expect(ReminderLapsePolicy.shouldPauseReminder(30), isTrue);
    });

    test('someone who never checked in is not lapsing', () {
      expect(ReminderLapsePolicy.shouldPauseReminder(null), isFalse);
    });
  });

  group('lapseMessage', () {
    test('says nothing before the boundary', () {
      expect(ReminderLapsePolicy.lapseMessage(3), isNull);
      expect(ReminderLapsePolicy.lapseMessage(13), isNull);
      expect(ReminderLapsePolicy.lapseMessage(null), isNull);
    });

    test('is one line with no guilt and no streak wording', () {
      final message = ReminderLapsePolicy.lapseMessage(20);

      expect(message, isNotNull);
      expect(message, contains('No catch-up needed'));
      expect(message, contains('One word is enough'));
      // The paused reminder is named rather than changed silently.
      expect(message, contains('paused'));
    });

    test('never mentions streaks, days in a row, or losing progress', () {
      final message = ReminderLapsePolicy.lapseMessage(60)!.toLowerCase();

      expect(message, isNot(contains('streak')));
      expect(message, isNot(contains('days in a row')));
      expect(message, isNot(contains('lose')));
      expect(message, isNot(contains('missed')));
      expect(message, isNot(contains('we miss')));
    });
  });

  group('shouldShowWelcomeBack', () {
    final lastCheckIn = DateTime(2026, 9, 1);

    test('is false before the lapse boundary', () {
      expect(
        ReminderLapsePolicy.shouldShowWelcomeBack(
          daysSinceLastCheckIn: 5,
          lastCheckIn: lastCheckIn,
          lastShownAt: null,
        ),
        isFalse,
      );
    });

    test('shows once when it has never been shown', () {
      expect(
        ReminderLapsePolicy.shouldShowWelcomeBack(
          daysSinceLastCheckIn: 20,
          lastCheckIn: lastCheckIn,
          lastShownAt: null,
        ),
        isTrue,
      );
    });

    test('does not repeat during the same lapse', () {
      expect(
        ReminderLapsePolicy.shouldShowWelcomeBack(
          daysSinceLastCheckIn: 25,
          lastCheckIn: lastCheckIn,
          // Shown after the last check-in, so this lapse already has its line.
          lastShownAt: lastCheckIn.add(const Duration(days: 18)),
        ),
        isFalse,
      );
    });

    test('a new lapse earns a new line', () {
      expect(
        ReminderLapsePolicy.shouldShowWelcomeBack(
          daysSinceLastCheckIn: 20,
          // The user came back, then drifted again.
          lastCheckIn: DateTime(2026, 10, 1),
          lastShownAt: lastCheckIn,
        ),
        isTrue,
      );
    });
  });
}
