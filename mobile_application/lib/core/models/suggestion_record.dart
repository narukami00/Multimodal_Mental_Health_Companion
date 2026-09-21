enum SuggestionStatus { shown, completed, skipped }

enum SuggestionSkipReason { notNow, notForMe, tooHard }

class SuggestionRecord {
  const SuggestionRecord({
    required this.id,
    required this.activityId,
    required this.shownAt,
    required this.contextTags,
    this.status = SuggestionStatus.shown,
    this.rating,
    this.skipReason,
    this.comment,
  });

  final String id;
  final String activityId;
  final DateTime shownAt;
  final List<String> contextTags;
  final SuggestionStatus status;
  final int? rating;
  final SuggestionSkipReason? skipReason;
  final String? comment;

  SuggestionRecord copyWith({
    SuggestionStatus? status,
    int? rating,
    SuggestionSkipReason? skipReason,
    String? comment,
  }) {
    return SuggestionRecord(
      id: id,
      activityId: activityId,
      shownAt: shownAt,
      contextTags: contextTags,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      skipReason: skipReason ?? this.skipReason,
      comment: comment ?? this.comment,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'activityId': activityId,
      'shownAt': shownAt.toIso8601String(),
      'contextTags': contextTags,
      'status': status.name,
      'rating': rating,
      'skipReason': skipReason?.name,
      'comment': comment,
    };
  }

  factory SuggestionRecord.fromMap(Map<String, dynamic> map) {
    final rawSkipReason = map['skipReason'] as String?;
    return SuggestionRecord(
      id: map['id'] as String? ?? '',
      activityId: map['activityId'] as String? ?? '',
      shownAt:
          DateTime.tryParse(map['shownAt'] as String? ?? '') ?? DateTime.now(),
      contextTags: (map['contextTags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      status: SuggestionStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => SuggestionStatus.shown,
      ),
      rating: (map['rating'] as num?)?.toInt(),
      skipReason: rawSkipReason == null
          ? null
          : SuggestionSkipReason.values.firstWhere(
              (value) => value.name == rawSkipReason,
              orElse: () => SuggestionSkipReason.notNow,
            ),
      comment: map['comment'] as String?,
    );
  }
}
