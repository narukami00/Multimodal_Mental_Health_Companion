import 'package:flutter/foundation.dart';

import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../data/contracts/provider_contracts.dart';
import '../../data/contracts/repository_contracts.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required SessionRepository repository,
    required EmotionAnalyzer emotionAnalyzer,
  })  : _repository = repository,
        _emotionAnalyzer = emotionAnalyzer;

  final SessionRepository _repository;
  final EmotionAnalyzer _emotionAnalyzer;
  List<SessionRecord> _sessions = const [];

  List<SessionRecord> get sessions => List.unmodifiable(_sessions);

  Future<void> load() async {
    _sessions = await _repository.listSessions();
    notifyListeners();
  }

  Future<SessionRecord> saveSession({
    required CaptureMode mode,
    String? text,
    String? mood,
  }) async {
    final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    final input = SessionInput(
      sessionId: sessionId,
      mode: mode,
      text: text,
    );
    final emotionResults = await _emotionAnalyzer.analyze(input);
    final session = SessionRecord(
      id: sessionId,
      createdAt: DateTime.now(),
      mode: mode,
      text: text,
      mood: mood,
      emotionResults: emotionResults,
    );

    await _repository.save(session);
    _sessions = [
      session,
      ..._sessions.where((item) => item.id != session.id),
    ];
    notifyListeners();
    return session;
  }

  SessionRecord? findById(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }
}
