import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/consent.dart';
import '../contracts/consent_repository.dart';

class SharedPreferencesConsentRepository implements ConsentRepository {
  SharedPreferencesConsentRepository(this._preferences);

  static const _ledgerKey = 'consent.ledger';
  final SharedPreferences _preferences;

  @override
  Future<ConsentLedger> load() async {
    final encoded = _preferences.getString(_ledgerKey);
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
    await _preferences.setString(_ledgerKey, jsonEncode(ledger.toMap()));
  }
}
