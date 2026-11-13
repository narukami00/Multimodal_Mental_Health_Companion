import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/session_record.dart';
import '../../services/secure_storage.dart';
import '../contracts/repository_contracts.dart';

class SharedPreferencesSessionRepository implements SessionRepository {
  SharedPreferencesSessionRepository(this._preferences, {SecureKeyValueStore? secureStore})
      : _secureStore = secureStore;

  static const _sessionsKey = 'sessions.records';

  final SharedPreferences _preferences;
  final SecureKeyValueStore? _secureStore;

  @override
  Future<SessionRecord?> findById(String id) async {
    final sessions = await listSessions();
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<List<SessionRecord>> listSessions() async {
    final encodedSessions = _secureStore != null
        ? await _secureStore.readStringList(_sessionsKey, legacyPreferences: _preferences)
        : (_preferences.getStringList(_sessionsKey) ?? const []);
    final sessions = <SessionRecord>[];

    for (final encoded in encodedSessions) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) {
          sessions.add(SessionRecord.fromMap(decoded));
        }
      } on FormatException {
        // Ignore a malformed local record instead of blocking the journal.
      }
    }

    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sessions);
  }

  @override
  Future<void> delete(String id) async {
    final sessions = (await listSessions()).where((item) => item.id != id);
    final encoded = sessions.map((item) => jsonEncode(item.toMap())).toList();
    if (_secureStore != null) {
      await _secureStore.writeStringList(_sessionsKey, encoded);
    } else {
      await _preferences.setStringList(_sessionsKey, encoded);
    }
  }

  @override
  Future<void> save(SessionRecord session) async {
    final sessions = (await listSessions())
        .where((item) => item.id != session.id)
        .toList()
      ..add(session);
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final encoded = sessions.map((item) => jsonEncode(item.toMap())).toList();
    if (_secureStore != null) {
      await _secureStore.writeStringList(_sessionsKey, encoded);
    } else {
      await _preferences.setStringList(_sessionsKey, encoded);
    }
  }
}
