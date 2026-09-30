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
}
