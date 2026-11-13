import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/therapist_contact.dart';
import '../../services/secure_storage.dart';

/// Manages a single therapist contact, persisted via encrypted storage when provided.
///
/// The user may store zero or one therapist. Adding replaces any existing
/// contact; removing clears it. The controller notifies listeners on every
/// change so the UI stays in step.
class TherapistController extends ChangeNotifier {
  TherapistController({
    required SharedPreferences preferences,
    SecureKeyValueStore? secureStore,
  })  : _preferences = preferences,
        _secureStore = secureStore;

  static const _key = 'profile.therapist_contact';
  final SharedPreferences _preferences;
  final SecureKeyValueStore? _secureStore;

  TherapistContact? _contact;
  bool _isLoaded = false;

  TherapistContact? get contact => _contact;
  bool get isLoaded => _isLoaded;
  bool get hasContact => _contact != null;

  Future<void> load() async {
    final encoded = _secureStore != null
        ? await _secureStore.readString(_key, legacyPreferences: _preferences)
        : _preferences.getString(_key);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) {
          final parsed = TherapistContact.fromMap(decoded);
          if (parsed.name.trim().isNotEmpty) {
            _contact = parsed;
          }
        }
      } on FormatException {
        // A malformed entry should not prevent the app from opening.
      }
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> save(TherapistContact contact) async {
    _contact = contact;
    final encoded = jsonEncode(contact.toMap());
    if (_secureStore != null) {
      await _secureStore.writeString(_key, encoded);
    } else {
      await _preferences.setString(_key, encoded);
    }
    notifyListeners();
  }

  Future<void> remove() async {
    _contact = null;
    if (_secureStore != null) {
      await _secureStore.remove(_key, legacyPreferences: _preferences);
    } else {
      await _preferences.remove(_key);
    }
    notifyListeners();
  }
}
