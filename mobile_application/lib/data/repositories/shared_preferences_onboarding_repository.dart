import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/onboarding_repository.dart';

class SharedPreferencesOnboardingRepository implements OnboardingRepository {
  SharedPreferencesOnboardingRepository(this._preferences);

  static const _completeKey = 'onboarding.complete';
  static const _usesMediaKey = 'onboarding.uses_media';

  final SharedPreferences _preferences;

  @override
  bool get isComplete => _preferences.getBool(_completeKey) ?? false;

  @override
  bool? get usesMedia => _preferences.getBool(_usesMediaKey);

  @override
  Future<void> complete() async {
    await _preferences.setBool(_completeKey, true);
  }

  @override
  Future<void> setMediaPreference({required bool enabled}) async {
    await _preferences.setBool(_usesMediaKey, enabled);
  }
}
