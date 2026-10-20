import '../constants/moods.dart';
import 'emotion_result.dart';
import 'session_input.dart';

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.createdAt,
    required this.mode,
    this.text,
    this.mood,
    this.emotionResults = const [],
  });

  final String id;
  final DateTime createdAt;
  final CaptureMode mode;
  final String? text;
  final String? mood;
  final List<EmotionResult> emotionResults;

  /// The model's full reading of this entry, or null for entries made before there was one (or when the
  /// server or the person's consent was missing).
  EmotionResult? get reading {
    for (final result in emotionResults) {
      if (result.classes != null) return result;
    }
    return null;
  }

  /// The mood the app works with: what the model read from the entry, else (older entries) the word that
  /// was picked at the time. Always one of [Moods.values]; null when neither exists.
  String? get effectiveMood {
    final r = reading;
    if (r != null) return Moods.fromReadingMood(r.mood);
    final picked = mood?.trim().toLowerCase();
    for (final word in Moods.values) {
      if (word.toLowerCase() == picked) return word; // older entries stored it in lower case
    }
    return mood;
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'mode': mode.name,
      'text': text,
      'mood': mood,
      'emotionResults': emotionResults
          .map((result) => result.toMap())
          .toList(),
    };
  }

  factory SessionRecord.fromMap(Map<String, dynamic> map) {
    final modeName = map['mode'] as String?;
    final mode = CaptureMode.values.firstWhere(
      (item) => item.name == modeName,
      orElse: () => CaptureMode.text,
    );
    final rawResults = map['emotionResults'] as List<dynamic>? ?? const [];

    return SessionRecord(
      id: map['id'] as String? ?? '',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      mode: mode,
      text: map['text'] as String?,
      mood: map['mood'] as String?,
      emotionResults: rawResults
          .whereType<Map<String, dynamic>>()
          .map(EmotionResult.fromMap)
          .toList(),
    );
  }
}
