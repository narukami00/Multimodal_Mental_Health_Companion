import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';

void main() {
  test('in-memory session repository saves and replaces sessions', () async {
    final repository = InMemorySessionRepository();
    final createdAt = DateTime(2026, 9, 21);
    const mode = CaptureMode.text;

    await repository.save(
      SessionRecord(
        id: 'session-1',
        createdAt: createdAt,
        mode: mode,
        text: 'First note',
      ),
    );
    await repository.save(
      SessionRecord(
        id: 'session-1',
        createdAt: createdAt,
        mode: mode,
        text: 'Updated note',
      ),
    );

    final sessions = await repository.listSessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.text, 'Updated note');
    expect(await repository.findById('missing'), isNull);
  });
}
