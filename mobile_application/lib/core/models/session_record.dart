import 'emotion_result.dart';
import 'session_input.dart';

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.createdAt,
    required this.mode,
    this.text,
    this.emotionResults = const [],
  });

  final String id;
  final DateTime createdAt;
  final CaptureMode mode;
  final String? text;
  final List<EmotionResult> emotionResults;
}
