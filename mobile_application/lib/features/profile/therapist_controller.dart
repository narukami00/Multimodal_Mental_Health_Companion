import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/therapist_contact.dart';

/// Manages a single therapist contact, persisted via SharedPreferences.
///
/// The user may store zero or one therapist. Adding replaces any existing
/// contact; removing clears it. The controller notifies listeners on every
/// change so the UI stays in step.
class TherapistController extends ChangeNotifier {
  TherapistController({required SharedPreferences preferences})
    : _preferences = preferences;

  static const _key = 'profile.therapist_contact';
  final SharedPreferences _preferences;

  TherapistContact? _contact;
  bool _isLoaded = false;

  TherapistContact? get contact => _contact;
  bool get isLoaded => _isLoaded;
  bool get hasContact => _contact != null;

  Future<void> load() async {
    final encoded = _preferences.getString(_key);
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
    await _preferences.setString(_key, jsonEncode(contact.toMap()));
    notifyListeners();
  }

  Future<void> remove() async {
    _contact = null;
    await _preferences.remove(_key);
    notifyListeners();
  }
}
