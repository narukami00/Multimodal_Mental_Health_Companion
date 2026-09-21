import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/shared_preferences_session_repository.dart';

void main() {
  test('session records survive shared preferences round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesSessionRepository(preferences);
    final timestamp = DateTime(2026, 9, 21, 9, 30);
    final session = SessionRecord(
      id: 'session-1',
      createdAt: timestamp,
      mode: CaptureMode.text,
      text: 'A note worth keeping.',
      emotionResults: [
        EmotionResult(
          sessionId: 'session-1',
          modality: EmotionModality.text,
          timestamp: timestamp,
          valence: 0.4,
          confidence: 0.8,
          modelVersion: 'mock-v1',
          labels: const [EmotionLabel(label: 'steady', score: 0.8)],
        ),
      ],
    );

    await repository.save(session);
    final restored = await repository.findById('session-1');

    expect(restored?.text, session.text);
    expect(restored?.createdAt, timestamp);
    expect(restored?.emotionResults.single.labels?.single.label, 'steady');
  });
}
