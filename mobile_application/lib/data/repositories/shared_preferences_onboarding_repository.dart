import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/onboarding_repository.dart';

class SharedPreferencesOnboardingRepository implements OnboardingRepository {
  SharedPreferencesOnboardingRepository(this._preferences);

  static const _completeKey = 'onboarding.complete';
  static const _currentPageKey = 'onboarding.current_page';
  static const _usesMediaKey = 'onboarding.uses_media';

  final SharedPreferences _preferences;

  @override
  bool get isComplete => _preferences.getBool(_completeKey) ?? false;

  @override
  int get currentPage => _preferences.getInt(_currentPageKey) ?? 0;

  @override
  bool? get usesMedia => _preferences.getBool(_usesMediaKey);

  @override
  Future<void> setCurrentPage(int page) async {
    await _preferences.setInt(_currentPageKey, page);
  }

  @override
  Future<void> complete() async {
    await _preferences.setBool(_completeKey, true);
  }

  @override
  Future<void> setMediaPreference({required bool enabled}) async {
    await _preferences.setBool(_usesMediaKey, enabled);
  }
}
