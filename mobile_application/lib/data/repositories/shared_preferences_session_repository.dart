import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/session_record.dart';
import '../contracts/repository_contracts.dart';

class SharedPreferencesSessionRepository implements SessionRepository {
  SharedPreferencesSessionRepository(this._preferences);

  static const _sessionsKey = 'sessions.records';

  final SharedPreferences _preferences;

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
    final encodedSessions = _preferences.getStringList(_sessionsKey) ?? const [];
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
    await _preferences.setStringList(
      _sessionsKey,
      sessions.map((item) => jsonEncode(item.toMap())).toList(),
    );
  }

  @override
  Future<void> save(SessionRecord session) async {
    final sessions = (await listSessions())
        .where((item) => item.id != session.id)
        .toList()
      ..add(session);
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    await _preferences.setStringList(
      _sessionsKey,
      sessions.map((item) => jsonEncode(item.toMap())).toList(),
    );
  }
}
