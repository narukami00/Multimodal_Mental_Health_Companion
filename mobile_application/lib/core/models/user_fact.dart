/// Result returned by `/v1/memory/extract_facts`.
class UserFactExtractionResult {
  const UserFactExtractionResult({
    required this.facts,
    required this.identitySummary,
    this.method = 'fallback',
  });

  final List<String> facts;
  final String identitySummary;
  final String method;
}

/// A durable, non-clinical personal fact learned strictly from what the user
/// has shared in conversations (e.g. studies, pets, routines, preferences).
///
/// Stored encrypted on-device inside [SecureKeyValueStore] and shared with the
/// companion prompt only when `ConsentKey.profileSnippet` is active.
class UserFact {
  const UserFact({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.sourceConversationId,
    this.pinned = false,
  });

  static const int maxLength = 120;

  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourceConversationId;
  final bool pinned;

  /// Smooth recency decay in `[0.15, 1.0]` for companion-side selective ranking.
  double recencyScore(DateTime now) {
    final days = now.difference(updatedAt).inHours / 24.0;
    if (days <= 0) return 1.0;
    final score = 1.0 / (1.0 + days / 30.0);
    return score < 0.15 ? 0.15 : score;
  }

  UserFact copyWith({
    String? text,
    DateTime? updatedAt,
    String? sourceConversationId,
    bool? pinned,
  }) =>
      UserFact(
        id: id,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sourceConversationId: sourceConversationId ?? this.sourceConversationId,
        pinned: pinned ?? this.pinned,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (sourceConversationId != null)
          'sourceConversationId': sourceConversationId,
        if (pinned) 'pinned': true,
      };

  factory UserFact.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    final created =
        DateTime.tryParse(map['createdAt'] as String? ?? '') ?? now;
    final updated =
        DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? created;
    return UserFact(
      id: map['id'] as String? ?? '',
      text: (map['text'] as String? ?? '').trim(),
      createdAt: created,
      updatedAt: updated,
      sourceConversationId: map['sourceConversationId'] as String?,
      pinned: map['pinned'] == true,
    );
  }
}
