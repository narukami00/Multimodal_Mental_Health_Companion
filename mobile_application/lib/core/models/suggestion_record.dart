enum SuggestionStatus { shown, completed, skipped }

enum SuggestionSkipReason { notNow, notForMe, tooHard }

/// Why a suggestion was chosen.
///
/// Only [learned] means "we think this fits you". [starter] and [explore] are
/// picks offered because the app does not know yet, and the card says so rather
/// than implying a personalisation it has not earned.
enum SuggestionSource { starter, explore, learned }

/// What the user said about a suggestion they did.
enum SuggestionUsefulness { up, down }

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
    this.source,
    this.done,
    this.useful,
    this.proactive = false,
  });

  final String id;
  final String activityId;
  final DateTime shownAt;
  final List<String> contextTags;
  final SuggestionStatus status;

  /// Star rating, kept for the long-press path. Optional and never assumed.
  final int? rating;

  final SuggestionSkipReason? skipReason;
  final String? comment;

  /// Null on records written before sources existed.
  final SuggestionSource? source;

  /// Whether the user said they did it. Null means they have not said either
  /// way — completion is never inferred from anything else.
  final bool? done;

  /// Whether it helped, independent of whether they did it.
  final SuggestionUsefulness? useful;

  /// Whether the app offered this unasked, as opposed to the user asking.
  ///
  /// Only proactive suggestions count against the daily budget. A suggestion
  /// someone went and requested themselves is not a nudge and must never
  /// consume the slot for one.
  final bool proactive;

  SuggestionRecord copyWith({
    SuggestionStatus? status,
    int? rating,
    SuggestionSkipReason? skipReason,
    String? comment,
    SuggestionSource? source,
    bool? done,
    SuggestionUsefulness? useful,
    bool? proactive,
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
      source: source ?? this.source,
      done: done ?? this.done,
      useful: useful ?? this.useful,
      proactive: proactive ?? this.proactive,
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
      'source': source?.name,
      'done': done,
      'useful': useful?.name,
      'proactive': proactive,
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
      // Absent on records written before these existed, which is honest:
      // they genuinely have no source, and no claim of one is invented.
      source: _sourceFrom(map['source'] as String?),
      done: map['done'] as bool?,
      useful: _usefulnessFrom(map['useful'] as String?),
      // Absent on records written before this existed. Reading them as
      // user-initiated is the safer default: it means an old record can never
      // silently consume today's nudge budget.
      proactive: map['proactive'] as bool? ?? false,
    );
  }

  static SuggestionSource? _sourceFrom(String? raw) {
    if (raw == null) return null;
    for (final value in SuggestionSource.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static SuggestionUsefulness? _usefulnessFrom(String? raw) {
    if (raw == null) return null;
    for (final value in SuggestionUsefulness.values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}
