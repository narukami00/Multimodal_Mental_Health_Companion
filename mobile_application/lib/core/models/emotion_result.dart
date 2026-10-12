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
    this.classes,
    this.valenceProbs,
    this.arousalProbs,
    this.mood,
    this.tier,
    this.pattern,
    this.inContext = false,
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

  /// A real model's full reading (absent on older or sample entries): the seven class
  /// probabilities, the valence (negative/neutral/positive) and arousal (low/mid/high)
  /// probabilities, a plain mood word such as 'low or tired' (null when the model was unsure),
  /// how sure it was ('clear' or 'hint'), and which signals it used ('A' voice, 'T' words,
  /// 'V' face, e.g. 'ATV').
  final Map<String, double>? classes;
  final Map<String, double>? valenceProbs;
  final Map<String, double>? arousalProbs;
  final String? mood;
  final String? tier;
  final String? pattern;

  /// True when the earlier messages of the conversation were taken into account (a short message such as
  /// "ok" says little alone), or the server's running read of the conversation was used.
  final bool inContext;

  EmotionResult copyWith({EmotionOrigin? origin, bool? inContext}) => EmotionResult(
        sessionId: sessionId,
        modality: modality,
        timestamp: timestamp,
        modelVersion: modelVersion,
        origin: origin ?? this.origin,
        valence: valence,
        arousal: arousal,
        labels: labels,
        confidence: confidence,
        classes: classes,
        valenceProbs: valenceProbs,
        arousalProbs: arousalProbs,
        mood: mood,
        tier: tier,
        pattern: pattern,
        inContext: inContext ?? this.inContext,
      );

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
      if (classes != null) 'classes': classes,
      if (valenceProbs != null) 'valenceProbs': valenceProbs,
      if (arousalProbs != null) 'arousalProbs': arousalProbs,
      if (mood != null) 'mood': mood,
      if (tier != null) 'tier': tier,
      if (pattern != null) 'pattern': pattern,
      if (inContext) 'inContext': true,
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
      classes: _probs(map['classes']),
      valenceProbs: _probs(map['valenceProbs']),
      arousalProbs: _probs(map['arousalProbs']),
      mood: map['mood'] as String?,
      tier: map['tier'] as String?,
      pattern: map['pattern'] as String?,
      inContext: map['inContext'] as bool? ?? false,
    );
  }

  static Map<String, double>? _probs(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, double>{};
    raw.forEach((key, value) {
      if (key is String && value is num) out[key] = value.toDouble();
    });
    return out.isEmpty ? null : out;
  }
}
