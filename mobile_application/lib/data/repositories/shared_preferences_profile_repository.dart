import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/user_profile.dart';
import '../../services/secure_storage.dart';
import '../contracts/profile_repository.dart';

class SharedPreferencesProfileRepository implements ProfileRepository {
  SharedPreferencesProfileRepository(this._preferences, {SecureKeyValueStore? secureStore})
      : _secureStore = secureStore;

  static const _profileKey = 'profile.baseline';
  final SharedPreferences _preferences;
  final SecureKeyValueStore? _secureStore;

  @override
  Future<UserProfile> load() async {
    final encoded = _secureStore != null
        ? await _secureStore.readString(_profileKey, legacyPreferences: _preferences)
        : _preferences.getString(_profileKey);
    if (encoded == null) return const UserProfile();

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) {
        return UserProfile.fromMap(decoded);
      }
    } on FormatException {
      // A malformed local profile should not prevent the app from opening.
    }
    return const UserProfile();
  }

  @override
  Future<void> save(UserProfile profile) async {
    final encoded = jsonEncode(profile.toMap());
    if (_secureStore != null) {
      await _secureStore.writeString(_profileKey, encoded);
    } else {
      await _preferences.setString(_profileKey, encoded);
    }
  }
}
