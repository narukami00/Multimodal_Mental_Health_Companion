import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/user_profile.dart';

void main() {
  group('UserProfile identity and settings fields', () {
    test('defaults are gentle and opt-out friendly', () {
      const profile = UserProfile();

      expect(profile.displayName, isNull);
      expect(profile.avatarPath, isNull);
      expect(profile.hapticsEnabled, isTrue);
      expect(profile.ambientAudioEnabled, isFalse);
      expect(profile.paletteId, UserProfile.defaultPaletteId);
      expect(profile.firstRunAt, isNull);
      expect(profile.reminderEnabled, isFalse);
      expect(profile.reminderMinutes, UserProfile.defaultReminderMinutes);
    });

    test('round-trips reminder settings through toMap/fromMap', () {
      const profile = UserProfile(
        reminderEnabled: true,
        reminderMinutes: 7 * 60 + 15,
      );

      final restored = UserProfile.fromMap(profile.toMap());

      expect(restored.reminderEnabled, isTrue);
      expect(restored.reminderMinutes, 7 * 60 + 15);
    });

    test('round-trips identity and settings through toMap/fromMap', () {
      final firstRun = DateTime(2026, 9, 26, 8, 30);
      final profile = UserProfile(
        displayName: 'Rafsan',
        avatarPath: '/data/user/0/app/files/avatar.jpg',
        hapticsEnabled: false,
        ambientAudioEnabled: true,
        paletteId: 'softTwilight',
        firstRunAt: firstRun,
      );

      final restored = UserProfile.fromMap(profile.toMap());

      expect(restored.displayName, 'Rafsan');
      expect(restored.avatarPath, '/data/user/0/app/files/avatar.jpg');
      expect(restored.hapticsEnabled, isFalse);
      expect(restored.ambientAudioEnabled, isTrue);
      expect(restored.paletteId, 'softTwilight');
      expect(restored.firstRunAt, firstRun);
    });

    test('legacy records without the new keys fall back to defaults', () {
      final legacy = UserProfile.fromMap({
        'preferencesCompleted': true,
        'skippedBlocks': ['erqS'],
      });

      expect(legacy.displayName, isNull);
      expect(legacy.hapticsEnabled, isTrue);
      expect(legacy.ambientAudioEnabled, isFalse);
      expect(legacy.paletteId, UserProfile.defaultPaletteId);
      // Pre-existing baseline behaviour must be untouched.
      expect(legacy.preferencesCompleted, isTrue);
      expect(legacy.erqSSkipped, isTrue);
    });

    test('blank strings are treated as unset', () {
      final profile = UserProfile.fromMap({
        'displayName': '   ',
        'avatarPath': '',
        'paletteId': '',
      });

      expect(profile.displayName, isNull);
      expect(profile.avatarPath, isNull);
      expect(profile.paletteId, UserProfile.defaultPaletteId);
    });

    test('copyWith updates one field without disturbing the rest', () {
      const base = UserProfile(displayName: 'Rafsan', paletteId: 'softTwilight');

      final updated = base.copyWith(ambientAudioEnabled: true);

      expect(updated.displayName, 'Rafsan');
      expect(updated.paletteId, 'softTwilight');
      expect(updated.ambientAudioEnabled, isTrue);
      expect(base.ambientAudioEnabled, isFalse);
    });
  });
}
