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
  });
}
