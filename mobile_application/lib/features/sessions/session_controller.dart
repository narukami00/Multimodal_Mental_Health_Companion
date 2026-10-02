import 'package:flutter/foundation.dart';

import '../../core/models/emotion_result.dart';
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
  /// Called after an entry is saved, so other features can look at it. The
  /// callback must not throw into the save: failures there are theirs to catch.
  void Function(SessionRecord session)? onSaved;

  List<SessionRecord> _sessions = const [];

  List<SessionRecord> get sessions => List.unmodifiable(_sessions);

  /// The most recent check-in time, or null when there are none.
  DateTime? get lastCheckInAt {
    DateTime? latest;
    for (final session in _sessions) {
      if (latest == null || session.createdAt.isAfter(latest)) {
        latest = session.createdAt;
      }
    }
    return latest;
  }

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
    // Only analyse content the user actually gave us. A one-word mood, or a
    // check-in with no text, carries nothing to analyse — inferring emotion
    // from an empty input would be inventing data.
    final hasText = text != null && text.trim().isNotEmpty;
    final emotionResults = hasText
        ? await _emotionAnalyzer.analyze(input)
        : const <EmotionResult>[];
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
    onSaved?.call(session);
    return session;
  }

  Future<void> seedInitialSessions() async {
    if (_sessions.isNotEmpty) return;
    final now = DateTime.now();
    final seeds = <SessionRecord>[
      _seedSession(
        createdAt: now.subtract(const Duration(hours: 2)),
        mode: CaptureMode.text,
        mood: 'steady',
        text:
            'Quiet morning, feeling steady after a cup of tea. A bit of work tension before the team sync, but took three slow breaths and settled in.',
        labels: const [
          EmotionLabel(label: 'steady', score: 0.88),
          EmotionLabel(label: 'calm', score: 0.75),
          EmotionLabel(label: 'reflective', score: 0.64),
        ],
      ),
      _seedSession(
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        mode: CaptureMode.voice,
        mood: 'tender',
        text: 'Took a short walk outside by the trees. The wind felt cool and grounding.',
        labels: const [
          EmotionLabel(label: 'tender', score: 0.82),
          EmotionLabel(label: 'calm', score: 0.78),
        ],
      ),
      _seedSession(
        createdAt: now.subtract(const Duration(days: 3, hours: 5)),
        mode: CaptureMode.video,
        mood: 'wobbly',
        text:
            'Felt a little overwhelmed with notifications today. Trying to remember to move at my own pace.',
        labels: const [
          EmotionLabel(label: 'tense', score: 0.72),
          EmotionLabel(label: 'hesitant', score: 0.55),
          EmotionLabel(label: 'steady', score: 0.42),
        ],
      ),
    ];

    for (final session in seeds) {
      await _repository.save(session);
    }
    _sessions = seeds;
    notifyListeners();
  }

  SessionRecord _seedSession({
    required DateTime createdAt,
    required CaptureMode mode,
    required String text,
    required String mood,
    required List<EmotionLabel> labels,
  }) {
    final id = 'seed-${createdAt.microsecondsSinceEpoch}';
    final modality = switch (mode) {
      CaptureMode.text => EmotionModality.text,
      CaptureMode.voice => EmotionModality.voice,
      CaptureMode.video => EmotionModality.face,
    };
    return SessionRecord(
      id: id,
      createdAt: createdAt,
      mode: mode,
      text: text,
      mood: mood,
      emotionResults: [
        EmotionResult(
          sessionId: id,
          modality: modality,
          timestamp: createdAt,
          labels: labels,
          confidence: labels.first.score,
          modelVersion: 'seed-v1',
        ),
      ],
    );
  }

  SessionRecord? findById(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  /// Whether a check-in was recorded on this calendar day.
  ///
  /// Home needs this to stop asking someone to check in after they already
  /// have, and the suggestion slot keys off it too.
  bool hasCheckedInOn(DateTime day) {
    return _sessions.any(
      (session) =>
          session.createdAt.year == day.year &&
          session.createdAt.month == day.month &&
          session.createdAt.day == day.day,
    );
  }
}
