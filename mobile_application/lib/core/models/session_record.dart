import '../constants/moods.dart';
import 'emotion_result.dart';
import 'session_input.dart';

enum MoodReviewStatus { accepted, corrected, noneFits, skipped }

enum MoodProvenance {
  userCorrected,
  userReported,
  userConfirmedModel,
  modelEstimate,
  noneFits,
  unknown,
}

/// Timestamped user review or correction of a specific model reading.
/// Kept separate from the original [SessionRecord.mood] and immutable [EmotionResult].
class MoodReview {
  const MoodReview({
    required this.status,
    required this.reviewedAt,
    required this.readingId,
    required this.readingTimestamp,
    required this.modelVersion,
    required this.modality,
    required this.origin,
    this.mood,
    this.confidence,
    this.readingMood,
  });

  final MoodReviewStatus status;

  /// Chosen UI mood word (`Steady`, `Bright`, `Tender`, `Wobbly`, `Quiet`) when
  /// [status] is [MoodReviewStatus.corrected], or the confirmed reading's mood
  /// when [status] is [MoodReviewStatus.accepted]; null for [noneFits]/[skipped].
  final String? mood;
  final DateTime reviewedAt;
  final String readingId;
  final DateTime readingTimestamp;
  final String modelVersion;
  final double? confidence;
  final EmotionModality modality;
  final EmotionOrigin origin;
  final String? readingMood;

  bool matchesReading(EmotionResult? r) =>
      r != null &&
      r.sessionId == readingId &&
      r.timestamp == readingTimestamp &&
      r.modelVersion == modelVersion;

  factory MoodReview.fromReading(
    EmotionResult reading, {
    required MoodReviewStatus status,
    String? correctedMood,
    DateTime? reviewedAt,
  }) {
    final chosen = switch (status) {
      MoodReviewStatus.corrected => Moods.normalize(correctedMood),
      MoodReviewStatus.accepted => Moods.fromReadingMood(reading.mood),
      MoodReviewStatus.noneFits || MoodReviewStatus.skipped => null,
    };
    return MoodReview(
      status: status,
      mood: chosen,
      reviewedAt: reviewedAt ?? DateTime.now(),
      readingId: reading.sessionId,
      readingTimestamp: reading.timestamp,
      modelVersion: reading.modelVersion,
      confidence: reading.confidence,
      modality: reading.modality,
      origin: reading.origin,
      readingMood: reading.mood,
    );
  }

  Map<String, Object?> toMap() => {
        'status': status.name,
        if (mood != null) 'mood': mood,
        'reviewedAt': reviewedAt.toIso8601String(),
        'readingId': readingId,
        'readingTimestamp': readingTimestamp.toIso8601String(),
        'modelVersion': modelVersion,
        if (confidence != null) 'confidence': confidence,
        'modality': modality.name,
        'origin': origin.name,
        if (readingMood != null) 'readingMood': readingMood,
      };

  factory MoodReview.fromMap(Map<String, dynamic> map) {
    final statusName = map['status'] as String?;
    final status = MoodReviewStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => MoodReviewStatus.skipped,
    );
    final modalityName = map['modality'] as String?;
    final modality = EmotionModality.values.firstWhere(
      (item) => item.name == modalityName,
      orElse: () => EmotionModality.text,
    );
    final originName = map['origin'] as String?;
    final origin = EmotionOrigin.values.firstWhere(
      (item) => item.name == originName,
      orElse: () => EmotionOrigin.journal,
    );
    return MoodReview(
      status: status,
      mood: map['mood'] as String?,
      reviewedAt: DateTime.tryParse(map['reviewedAt'] as String? ?? '') ?? DateTime.now(),
      readingId: map['readingId'] as String? ?? '',
      readingTimestamp:
          DateTime.tryParse(map['readingTimestamp'] as String? ?? '') ?? DateTime.now(),
      modelVersion: map['modelVersion'] as String? ?? 'unknown',
      confidence: (map['confidence'] as num?)?.toDouble(),
      modality: modality,
      origin: origin,
      readingMood: map['readingMood'] as String?,
    );
  }
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.createdAt,
    required this.mode,
    this.text,
    this.mood,
    this.emotionResults = const [],
    this.moodReview,
    this.awaitingRecording = false,
    this.awaitingFace = false,
  });

  /// True while a voice or video recording of this entry is kept on the phone, waiting for the companion
  /// server to write it down and read it. The entry has no words yet; they arrive when the server does.
  final bool awaitingRecording;

  /// Whether the person also agreed to the camera being read when this recording was made.
  final bool awaitingFace;

  final String id;
  final DateTime createdAt;
  final CaptureMode mode;
  final String? text;
  final String? mood;
  final List<EmotionResult> emotionResults;
  final MoodReview? moodReview;

  /// The model's full reading of this entry, or null for entries made before there was one (or when the
  /// server or the person's consent was missing).
  EmotionResult? get reading {
    for (final result in emotionResults) {
      if (result.classes != null) return result;
    }
    return null;
  }

  /// Whether the current [reading] has been reviewed by the user (exact result ID,
  /// timestamp, and model version match).
  bool get isCurrentReadingReviewed =>
      moodReview != null && moodReview!.matchesReading(reading);

  /// Source of [effectiveMood], keeping user report/correction distinct from model guesses.
  MoodProvenance get moodProvenance {
    final review = moodReview;
    if (review != null &&
        review.status == MoodReviewStatus.corrected &&
        Moods.normalize(review.mood) != null) {
      return MoodProvenance.userCorrected;
    }
    if (review != null && review.status == MoodReviewStatus.noneFits) {
      return MoodProvenance.noneFits;
    }
    if (Moods.normalize(mood) != null) {
      return MoodProvenance.userReported;
    }
    final r = reading;
    final modelMood = r == null ? null : Moods.fromReadingMood(r.mood);
    if (review != null &&
        review.status == MoodReviewStatus.accepted &&
        review.matchesReading(r) &&
        modelMood != null) {
      return MoodProvenance.userConfirmedModel;
    }
    if (modelMood != null) {
      return MoodProvenance.modelEstimate;
    }
    return MoodProvenance.unknown;
  }

  /// The mood the app works with: explicit user correction or self-report takes
  /// precedence; otherwise eligible consented model fallback, preserving null
  /// when the model abstained or the user marked "None fits".
  String? get effectiveMood {
    final review = moodReview;
    if (review != null && review.status == MoodReviewStatus.corrected) {
      final corrected = Moods.normalize(review.mood);
      if (corrected != null) return corrected;
    }
    if (review != null && review.status == MoodReviewStatus.noneFits) {
      return null;
    }
    final picked = Moods.normalize(mood);
    if (picked != null) return picked;
    final trimmed = mood?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return mood;
    final r = reading;
    if (r != null) return Moods.fromReadingMood(r.mood);
    return null;
  }

  SessionRecord copyWith({
    String? text,
    String? mood,
    List<EmotionResult>? emotionResults,
    MoodReview? moodReview,
    bool clearMoodReview = false,
    bool? awaitingRecording,
    bool? awaitingFace,
  }) =>
      SessionRecord(
        id: id,
        createdAt: createdAt,
        mode: mode,
        text: text ?? this.text,
        mood: mood ?? this.mood,
        emotionResults: emotionResults ?? this.emotionResults,
        moodReview: clearMoodReview ? null : (moodReview ?? this.moodReview),
        awaitingRecording: awaitingRecording ?? this.awaitingRecording,
        awaitingFace: awaitingFace ?? this.awaitingFace,
      );

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
      if (moodReview != null) 'moodReview': moodReview!.toMap(),
      if (awaitingRecording) 'awaiting': {'audio': true, 'face': awaitingFace},
    };
  }

  factory SessionRecord.fromMap(Map<String, dynamic> map) {
    final modeName = map['mode'] as String?;
    final mode = CaptureMode.values.firstWhere(
      (item) => item.name == modeName,
      orElse: () => CaptureMode.text,
    );
    final rawResults = map['emotionResults'] as List<dynamic>? ?? const [];
    final rawReview = map['moodReview'];
    final awaiting = map['awaiting'];

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
      moodReview: rawReview is Map<String, dynamic>
          ? MoodReview.fromMap(rawReview)
          : null,
      awaitingRecording: awaiting is Map && awaiting['audio'] == true,
      awaitingFace: awaiting is Map && awaiting['face'] == true,
    );
  }
}
