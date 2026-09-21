enum EmotionModality { text, voice, face }

class EmotionLabel {
  const EmotionLabel({
    required this.label,
    this.score,
  });

  final String label;
  final double? score;

  Map<String, Object?> toMap() {
    return {
      'label': label,
      'score': score,
    };
  }

  factory EmotionLabel.fromMap(Map<String, dynamic> map) {
    return EmotionLabel(
      label: map['label'] as String? ?? 'unknown',
      score: (map['score'] as num?)?.toDouble(),
    );
  }
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

  Map<String, Object?> toMap() {
    return {
      'sessionId': sessionId,
      'modality': modality.name,
      'timestamp': timestamp.toIso8601String(),
      'valence': valence,
      'arousal': arousal,
      'labels': labels?.map((label) => label.toMap()).toList(),
      'confidence': confidence,
      'modelVersion': modelVersion,
    };
  }

  factory EmotionResult.fromMap(Map<String, dynamic> map) {
    final modalityName = map['modality'] as String?;
    final modality = EmotionModality.values.firstWhere(
      (item) => item.name == modalityName,
      orElse: () => EmotionModality.text,
    );
    final rawLabels = map['labels'] as List<dynamic>?;

    return EmotionResult(
      sessionId: map['sessionId'] as String? ?? '',
      modality: modality,
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      valence: (map['valence'] as num?)?.toDouble(),
      arousal: (map['arousal'] as num?)?.toDouble(),
      labels: rawLabels
          ?.whereType<Map<String, dynamic>>()
          .map(EmotionLabel.fromMap)
          .toList(),
      confidence: (map['confidence'] as num?)?.toDouble(),
      modelVersion: map['modelVersion'] as String? ?? 'unknown',
    );
  }
}
