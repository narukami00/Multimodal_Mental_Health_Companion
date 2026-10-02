import '../../core/models/session_record.dart';

abstract interface class SessionRepository {
  Future<List<SessionRecord>> listSessions();

  Future<SessionRecord?> findById(String id);

  Future<void> save(SessionRecord session);

  /// Removes one entry. Removing one that is not there is not an error.
  Future<void> delete(String id);
}
