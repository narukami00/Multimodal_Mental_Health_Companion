import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';

void main() {
  group('ProfileController settings', () {
    test('ensureFirstRun records the first launch only once', () async {
      final controller = ProfileController(
        repository: InMemoryProfileRepository(),
      );
      await controller.load();

      expect(controller.profile.firstRunAt, isNull);

      await controller.ensureFirstRun();
      final first = controller.profile.firstRunAt;
      expect(first, isNotNull);

      await controller.ensureFirstRun();
      expect(controller.profile.firstRunAt, first);
    });

    test('identity and settings persist through the repository', () async {
      final repository = InMemoryProfileRepository();
      final controller = ProfileController(repository: repository);
      await controller.load();

      await controller.saveIdentity(
        displayName: 'Rafsan',
        avatarPath: '/files/avatar.jpg',
      );
      await controller.setHapticsEnabled(false);
      await controller.setAmbientAudioEnabled(true);
      await controller.setPaletteId('softTwilight');

      final stored = await repository.load();
      expect(stored.displayName, 'Rafsan');
      expect(stored.avatarPath, '/files/avatar.jpg');
      expect(stored.hapticsEnabled, isFalse);
      expect(stored.ambientAudioEnabled, isTrue);
      expect(stored.paletteId, 'softTwilight');
    });

    test('settings changes notify listeners', () async {
      final controller = ProfileController(
        repository: InMemoryProfileRepository(),
      );
      await controller.load();

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setHapticsEnabled(false);
      await controller.setAmbientAudioEnabled(true);

      expect(notifications, 2);
    });

    test('reminder settings persist and clamp to a valid day range', () async {
      final repository = InMemoryProfileRepository();
      final controller = ProfileController(repository: repository);
      await controller.load();

      await controller.setReminderMinutes(7 * 60 + 45);
      await controller.setReminderEnabled(true);

      final stored = await repository.load();
      expect(stored.reminderEnabled, isTrue);
      expect(stored.reminderMinutes, 7 * 60 + 45);

      // Values outside a single day are clamped rather than stored as-is.
      await controller.setReminderMinutes(24 * 60 + 10);
      expect(controller.profile.reminderMinutes, 24 * 60 - 1);
    });
  });

  group('ProfileController rest days', () {
    late ProfileController controller;

    setUp(() async {
      controller = ProfileController(repository: InMemoryProfileRepository());
      await controller.load();
    });

    test('declaring rest twice records the day once', () async {
      final day = DateTime(2026, 9, 26, 22, 30);

      await controller.declareRestDay(day);
      await controller.declareRestDay(day);

      expect(controller.restDays, {'2026-09-26'});
    });

    test('a mis-tap can be undone', () async {
      final day = DateTime(2026, 9, 26);

      await controller.declareRestDay(day);
      await controller.removeRestDay(day);

      expect(controller.restDays, isEmpty);
    });

    test('removing a day that was not rest changes nothing', () async {
      await controller.declareRestDay(DateTime(2026, 9, 26));

      await controller.removeRestDay(DateTime(2026, 9, 1));

      expect(controller.restDays, {'2026-09-26'});
    });

    test('rest days survive a reload', () async {
      final repository = InMemoryProfileRepository();
      final first = ProfileController(repository: repository);
      await first.load();
      await first.declareRestDay(DateTime(2026, 9, 26, 23, 59));
      await first.markWelcomeBackShown();

      final reloaded = ProfileController(repository: repository);
      await reloaded.load();

      expect(reloaded.restDays, {'2026-09-26'});
      expect(reloaded.profile.welcomeBackShownAt, isNotNull);
    });

    test('a rest declaration does not create a check-in', () async {
      await controller.declareRestDay(DateTime(2026, 9, 26));

      // Rest is its own mark; nothing pretends it was a reflection.
      expect(controller.profile.restDays.length, 1);
      expect(controller.profile.welcomeBackShownAt, isNull);
    });
  });

  sleepHoursControllerTests();
}

void sleepHoursControllerTests() {
  group('ProfileController sleep hours', () {
    late InMemoryProfileRepository repository;
    late ProfileController controller;

    setUp(() async {
      repository = InMemoryProfileRepository();
      controller = ProfileController(repository: repository);
      await controller.load();
    });

    test('setting hours persists them and clamps to a valid day', () async {
      await controller.setSleepHours(startMinutes: 23 * 60, endMinutes: 9999);

      final stored = await repository.load();
      expect(stored.sleepStartMinutes, 23 * 60);
      expect(stored.sleepEndMinutes, 24 * 60 - 1);
      expect(stored.sleepHoursSet, isTrue);
    });

    test('skipping is an answer and giving hours supersedes it', () async {
      await controller.skipSleepHours();
      expect(controller.profile.sleepHoursSkipped, isTrue);
      expect(controller.profile.sleepHoursAnswered, isTrue);
      expect(controller.profile.sleepHoursSet, isFalse);

      await controller.setSleepHours(startMinutes: 22 * 60, endMinutes: 6 * 60);
      expect(controller.profile.sleepHoursSkipped, isFalse);
      expect(controller.profile.sleepHoursSet, isTrue);
    });

    test('weekend hours are kept while the toggle is off', () async {
      await controller.setSleepHours(startMinutes: 23 * 60, endMinutes: 7 * 60);
      await controller.setWeekendsDiffer(true);
      await controller.setWeekendSleepHours(
        startMinutes: 60,
        endMinutes: 9 * 60,
      );
      await controller.setWeekendsDiffer(false);

      expect(controller.profile.weekendSleepStartMinutes, 60);
      expect(controller.profile.weekendSleepEndMinutes, 9 * 60);
      expect(controller.profile.weekendSleepDiffers, isFalse);
    });

    test('using sleep hours as quiet hours copies and enables them', () async {
      await controller.setSleepHours(startMinutes: 23 * 60, endMinutes: 7 * 60);

      final copied = await controller.useSleepHoursAsQuietHours();

      expect(copied, isTrue);
      expect(controller.profile.quietHoursEnabled, isTrue);
      expect(controller.profile.quietStartMinutes, 23 * 60);
      expect(controller.profile.quietEndMinutes, 7 * 60);

      // Independent afterwards: changing sleep hours leaves quiet hours alone.
      await controller.setSleepHours(startMinutes: 1 * 60, endMinutes: 9 * 60);
      expect(controller.profile.quietStartMinutes, 23 * 60);
    });

    test('there is nothing to copy without sleep hours', () async {
      final copied = await controller.useSleepHoursAsQuietHours();

      expect(copied, isFalse);
      expect(controller.profile.quietHoursEnabled, isFalse);
    });

    test('retention is adjustable within sensible bounds', () async {
      await controller.setFeatureRetentionDays(90);
      expect(controller.profile.featureRetentionDays, 90);

      await controller.setFeatureRetentionDays(1);
      expect(
        controller.profile.featureRetentionDays,
        ProfileController.minRetentionDays,
      );

      await controller.setFeatureRetentionDays(100000);
      expect(
        controller.profile.featureRetentionDays,
        ProfileController.maxRetentionDays,
      );
    });

    test('changes notify listeners', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setSleepHours(startMinutes: 23 * 60, endMinutes: 7 * 60);
      await controller.setWeekendsDiffer(true);

      expect(notifications, 2);
    });
  });
}
