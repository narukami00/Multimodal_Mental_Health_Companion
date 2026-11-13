import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/consent.dart';
import '../../services/secure_storage.dart';
import '../contracts/consent_repository.dart';

class SharedPreferencesConsentRepository implements ConsentRepository {
  SharedPreferencesConsentRepository(this._preferences, {SecureKeyValueStore? secureStore})
      : _secureStore = secureStore;

  static const _ledgerKey = 'consent.ledger';
  final SharedPreferences _preferences;
  final SecureKeyValueStore? _secureStore;

  @override
  Future<ConsentLedger> load() async {
    final encoded = _secureStore != null
        ? await _secureStore.readString(_ledgerKey, legacyPreferences: _preferences)
        : _preferences.getString(_ledgerKey);
    if (encoded == null) return const ConsentLedger();

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) {
        return ConsentLedger.fromMap(decoded);
      }
    } on FormatException {
      // An unreadable ledger reads as nothing granted: consent fails closed.
    }
    return const ConsentLedger();
  }

  @override
  Future<void> save(ConsentLedger ledger) async {
    final encoded = jsonEncode(ledger.toMap());
    if (_secureStore != null) {
      await _secureStore.writeString(_ledgerKey, encoded);
    } else {
      await _preferences.setString(_ledgerKey, encoded);
    }
  }
}
