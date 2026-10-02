import '../../core/models/session_record.dart';
import '../contracts/repository_contracts.dart';

class InMemorySessionRepository implements SessionRepository {
  final List<SessionRecord> _sessions = [];

  @override
  Future<SessionRecord?> findById(String id) async {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<List<SessionRecord>> listSessions() async {
    return List.unmodifiable(_sessions);
  }

  @override
  Future<void> delete(String id) async {
    _sessions.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> save(SessionRecord session) async {
    final existingIndex = _sessions.indexWhere((item) => item.id == session.id);
    if (existingIndex == -1) {
      _sessions.add(session);
    } else {
      _sessions[existingIndex] = session;
    }
  }
}
