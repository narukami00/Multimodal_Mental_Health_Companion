import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/contracts/provider_contracts.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';

class _FakeEmotionAnalyzer implements EmotionAnalyzer {
  @override
  Future<List<EmotionResult>> analyze(SessionInput input) async {
    return [
      EmotionResult(
        sessionId: input.sessionId,
        modality: EmotionModality.text,
        timestamp: DateTime(2026, 9, 21),
        labels: const [EmotionLabel(label: 'steady')],
        confidence: 0.7,
        modelVersion: 'test-v1',
      ),
    ];
  }
}

void main() {
  test('session controller saves analyzed text sessions', () async {
    final controller = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: _FakeEmotionAnalyzer(),
    );
    await controller.load();

    final saved = await controller.saveSession(
      mode: CaptureMode.text,
      text: 'A short reflection.',
    );

    expect(controller.sessions, hasLength(1));
    expect(controller.findById(saved.id)?.text, 'A short reflection.');
    expect(saved.emotionResults.single.labels?.single.label, 'steady');
  });
}
