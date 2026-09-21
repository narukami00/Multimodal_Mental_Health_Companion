enum ActivityType {
  movement,
  social,
  creative,
  nature,
  mindfulness,
  learning,
  productivity,
}

enum ActivityEffort { low, medium, high }

enum ActivityEvidenceTier { lifestyle, therapeutic }

enum ActivityReviewStatus { approved, pending, rejected }

class ActivityReviewMetadata {
  const ActivityReviewMetadata({
    required this.status,
    required this.evidenceTier,
    required this.reviewerRole,
    required this.reviewedAt,
    this.clinicianSignoff = false,
    this.notes,
  });

  final ActivityReviewStatus status;
  final ActivityEvidenceTier evidenceTier;
  final String reviewerRole;
  final DateTime reviewedAt;
  final bool clinicianSignoff;
  final String? notes;

  bool get isApprovedForPrototype =>
      status == ActivityReviewStatus.approved &&
      (evidenceTier == ActivityEvidenceTier.lifestyle || clinicianSignoff);

  factory ActivityReviewMetadata.fromMap(Map<String, dynamic> map) {
    return ActivityReviewMetadata(
      status: _enumValue(
        ActivityReviewStatus.values,
        map['status'] as String?,
        ActivityReviewStatus.pending,
      ),
      evidenceTier: _enumValue(
        ActivityEvidenceTier.values,
        map['evidenceTier'] as String?,
        ActivityEvidenceTier.lifestyle,
      ),
      reviewerRole: map['reviewerRole'] as String? ?? '',
      reviewedAt:
          DateTime.tryParse(map['reviewedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      clinicianSignoff: map['clinicianSignoff'] as bool? ?? false,
      notes: map['notes'] as String?,
    );
  }
}

class Activity {
  const Activity({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.effort,
    required this.durationMinutes,
    required this.contexts,
    required this.targetStates,
    required this.review,
  });

  final String id;
  final String title;
  final String description;
  final ActivityType type;
  final ActivityEffort effort;
  final int durationMinutes;
  final List<String> contexts;
  final List<String> targetStates;
  final ActivityReviewMetadata review;

  factory Activity.fromMap(Map<String, dynamic> map) {
    return Activity(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      type: _enumValue(
        ActivityType.values,
        map['type'] as String?,
        ActivityType.productivity,
      ),
      effort: _enumValue(
        ActivityEffort.values,
        map['effort'] as String?,
        ActivityEffort.low,
      ),
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 0,
      contexts: _strings(map['contexts']),
      targetStates: _strings(map['targetStates']),
      review: ActivityReviewMetadata.fromMap(
        map['review'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  static List<String> _strings(Object? value) {
    return (value as List<dynamic>? ?? const []).whereType<String>().toList();
  }
}

T _enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
  return values.firstWhere(
    (value) => value.name == name,
    orElse: () => fallback,
  );
}
