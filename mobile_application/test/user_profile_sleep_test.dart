import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/sleep_window.dart';
import 'package:solace_mobile/core/models/user_profile.dart';

void main() {
  group('SleepWindow', () {
    test('a window that crosses midnight contains both sides of it', () {
      const window = SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60);

      expect(window.contains(23 * 60), isTrue);
      expect(window.contains(0), isTrue);
      expect(window.contains(6 * 60 + 59), isTrue);
      expect(window.contains(7 * 60), isFalse);
      expect(window.contains(12 * 60), isFalse);
      expect(window.contains(22 * 60 + 59), isFalse);
    });

    test('a same-day window works without wrapping', () {
      const window = SleepWindow(startMinutes: 13 * 60, endMinutes: 15 * 60);

      expect(window.contains(14 * 60), isTrue);
      expect(window.contains(15 * 60), isFalse);
      expect(window.durationMinutes, 120);
    });

    test('duration wraps past midnight', () {
      const window = SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60);

      expect(window.durationMinutes, 8 * 60);
    });

    test('equal ends are empty, never a full day', () {
      const window = SleepWindow(startMinutes: 8 * 60, endMinutes: 8 * 60);

      expect(window.isEmpty, isTrue);
      expect(window.durationMinutes, 0);
      expect(window.contains(8 * 60), isFalse);
      expect(window.contains(0), isFalse);
    });
  });

  group('UserProfile sleep hours', () {
    test('start unset, not skipped, and with no guessed window', () {
      const profile = UserProfile();

      expect(profile.sleepHoursSet, isFalse);
      expect(profile.sleepHoursSkipped, isFalse);
      expect(profile.sleepHoursAnswered, isFalse);
      expect(profile.sleepWindowFor(weekend: false), isNull);
      expect(profile.sleepWindowFor(weekend: true), isNull);
      expect(profile.weekendSleepDiffers, isFalse);
      expect(
        profile.featureRetentionDays,
        UserProfile.defaultFeatureRetentionDays,
      );
    });

    test('skipping counts as answering without setting hours', () {
      const profile = UserProfile(sleepHoursSkipped: true);

      expect(profile.sleepHoursSet, isFalse);
      expect(profile.sleepHoursAnswered, isTrue);
      expect(profile.sleepWindowFor(weekend: false), isNull);
    });

    test('one end alone is not a set window', () {
      const profile = UserProfile(sleepStartMinutes: 23 * 60);

      expect(profile.sleepHoursSet, isFalse);
      expect(profile.sleepWindowFor(weekend: false), isNull);
    });

    test('weekdays and weekends share the usual hours by default', () {
      const profile = UserProfile(
        sleepStartMinutes: 23 * 60,
        sleepEndMinutes: 7 * 60,
        weekendSleepStartMinutes: 1 * 60,
        weekendSleepEndMinutes: 9 * 60,
      );

      const usual = SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60);
      expect(profile.sleepWindowFor(weekend: false), usual);
      // The stored weekend pair is ignored while the toggle is off.
      expect(profile.sleepWindowFor(weekend: true), usual);
    });

    test('weekend nights use their own hours when weekends differ', () {
      const profile = UserProfile(
        sleepStartMinutes: 23 * 60,
        sleepEndMinutes: 7 * 60,
        weekendSleepDiffers: true,
        weekendSleepStartMinutes: 1 * 60,
        weekendSleepEndMinutes: 9 * 60,
      );

      expect(
        profile.sleepWindowFor(weekend: true),
        const SleepWindow(startMinutes: 1 * 60, endMinutes: 9 * 60),
      );
      expect(
        profile.sleepWindowFor(weekend: false),
        const SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60),
      );
    });

    test('an incomplete weekend pair falls back to the usual hours', () {
      const profile = UserProfile(
        sleepStartMinutes: 23 * 60,
        sleepEndMinutes: 7 * 60,
        weekendSleepDiffers: true,
        weekendSleepStartMinutes: 1 * 60,
      );

      expect(
        profile.sleepWindowFor(weekend: true),
        const SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60),
      );
    });

    test('round-trips through toMap/fromMap', () {
      const profile = UserProfile(
        sleepStartMinutes: 23 * 60 + 30,
        sleepEndMinutes: 6 * 60 + 45,
        sleepHoursSkipped: false,
        weekendSleepDiffers: true,
        weekendSleepStartMinutes: 60,
        weekendSleepEndMinutes: 9 * 60,
        featureRetentionDays: 90,
      );

      final restored = UserProfile.fromMap(profile.toMap());

      expect(restored.sleepStartMinutes, 23 * 60 + 30);
      expect(restored.sleepEndMinutes, 6 * 60 + 45);
      expect(restored.weekendSleepDiffers, isTrue);
      expect(restored.weekendSleepStartMinutes, 60);
      expect(restored.weekendSleepEndMinutes, 9 * 60);
      expect(restored.featureRetentionDays, 90);
    });

    test('records written before sleep hours existed read as unanswered', () {
      final legacy = UserProfile.fromMap({
        'preferencesCompleted': true,
        'quietHoursEnabled': true,
        'quietStartMinutes': 22 * 60,
        'quietEndMinutes': 7 * 60,
      });

      expect(legacy.sleepHoursSet, isFalse);
      expect(legacy.sleepHoursAnswered, isFalse);
      expect(legacy.weekendSleepDiffers, isFalse);
      expect(
        legacy.featureRetentionDays,
        UserProfile.defaultFeatureRetentionDays,
      );
      // Quiet hours are a separate setting and stay exactly as stored.
      expect(legacy.quietHoursEnabled, isTrue);
      expect(legacy.quietStartMinutes, 22 * 60);
    });

    test('out-of-range or malformed stored values are ignored', () {
      final profile = UserProfile.fromMap({
        'sleepStartMinutes': 2000,
        'sleepEndMinutes': -5,
        'weekendSleepStartMinutes': 'late',
        'featureRetentionDays': 0,
      });

      expect(profile.sleepStartMinutes, isNull);
      expect(profile.sleepEndMinutes, isNull);
      expect(profile.weekendSleepStartMinutes, isNull);
      expect(
        profile.featureRetentionDays,
        UserProfile.defaultFeatureRetentionDays,
      );
    });

    test('copyWith changes sleep fields without disturbing the rest', () {
      const base = UserProfile(displayName: 'Rafsan', quietHoursEnabled: true);

      final updated = base.copyWith(
        sleepStartMinutes: 23 * 60,
        sleepEndMinutes: 7 * 60,
      );

      expect(updated.sleepHoursSet, isTrue);
      expect(updated.displayName, 'Rafsan');
      expect(updated.quietHoursEnabled, isTrue);
    });
  });
}
