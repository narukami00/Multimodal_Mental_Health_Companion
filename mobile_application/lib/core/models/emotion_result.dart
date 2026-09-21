enum EmotionModality { text, voice, face }

class EmotionLabel {
  const EmotionLabel({
    required this.label,
    this.score,
  });

  final String label;
  final double? score;
}

class EmotionResult {
  const EmotionResult({
    required this.sessionId,
    required this.modality,
    required this.timestamp,
    required this.modelVersion,
    this.valence,
    this.arousal,
    this.labels,
    this.confidence,
  });

  final String sessionId;
  final EmotionModality modality;
  final DateTime timestamp;
  final double? valence;
  final double? arousal;
  final List<EmotionLabel>? labels;
  final double? confidence;
  final String modelVersion;
}
