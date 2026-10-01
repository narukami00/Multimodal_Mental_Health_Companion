enum EmotionModality { text, voice, face }

/// Where the analysed content came from. Separate from [EmotionModality]: a
/// text result can come from a check-in, a journal entry, a chat turn, or the
/// note on a task review, and downstream code weighs those differently.
enum EmotionOrigin { checkIn, journal, chat, taskReview }

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
    this.origin = EmotionOrigin.checkIn,
    this.valence,
    this.arousal,
    this.labels,
    this.confidence,
  });

  final String sessionId;
  final EmotionModality modality;

  /// Defaults to a check-in, which is what every result written before origins
  /// existed was.
  final EmotionOrigin origin;
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
      'origin': origin.name,
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
    final originName = map['origin'] as String?;
    final origin = EmotionOrigin.values.firstWhere(
      (item) => item.name == originName,
      orElse: () => EmotionOrigin.checkIn,
    );
    final rawLabels = map['labels'] as List<dynamic>?;

    return EmotionResult(
      sessionId: map['sessionId'] as String? ?? '',
      modality: modality,
      origin: origin,
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
