import 'dart:convert';
import 'chat_message_record.dart';

enum ShiftAgreement { agrees, disagrees, unsure, skipped }

/// Optional user review of one inferred emotional shift in a chat conversation,
/// keeping agreement with the shift itself separate from agreement with any
/// proposed contextual hypothesis.
class TrajectoryShiftReview {
  const TrajectoryShiftReview({
    required this.shiftId,
    required this.fromMessageId,
    required this.toMessageId,
    required this.evidenceVersion,
    required this.shiftFit,
    required this.reviewedAt,
    this.reasonFit,
    this.proposedContext,
    this.userCorrection,
  });

  final String shiftId;
  final String fromMessageId;
  final String toMessageId;
  final String evidenceVersion;
  final ShiftAgreement shiftFit;
  final ShiftAgreement? reasonFit;
  final String? proposedContext;
  final String? userCorrection;
  final DateTime reviewedAt;

  TrajectoryShiftReview copyWith({
    ShiftAgreement? shiftFit,
    ShiftAgreement? reasonFit,
    bool clearReasonFit = false,
    String? proposedContext,
    String? userCorrection,
    DateTime? reviewedAt,
  }) =>
      TrajectoryShiftReview(
        shiftId: shiftId,
        fromMessageId: fromMessageId,
        toMessageId: toMessageId,
        evidenceVersion: evidenceVersion,
        shiftFit: shiftFit ?? this.shiftFit,
        reasonFit: clearReasonFit ? null : (reasonFit ?? this.reasonFit),
        proposedContext: proposedContext ?? this.proposedContext,
        userCorrection: userCorrection ?? this.userCorrection,
        reviewedAt: reviewedAt ?? this.reviewedAt,
      );

  Map<String, Object?> toMap() => {
        'shiftId': shiftId,
        'fromMessageId': fromMessageId,
        'toMessageId': toMessageId,
        'evidenceVersion': evidenceVersion,
        'shiftFit': shiftFit.name,
        if (reasonFit != null) 'reasonFit': reasonFit!.name,
        if (proposedContext != null) 'proposedContext': proposedContext,
        if (userCorrection != null) 'userCorrection': userCorrection,
        'reviewedAt': reviewedAt.toIso8601String(),
      };

  static ShiftAgreement _parseAgreement(String? name) =>
      ShiftAgreement.values.firstWhere(
        (v) => v.name == name,
        orElse: () => ShiftAgreement.skipped,
      );

  factory TrajectoryShiftReview.fromMap(Map<String, dynamic> map) =>
      TrajectoryShiftReview(
        shiftId: map['shiftId'] as String? ?? '',
        fromMessageId: map['fromMessageId'] as String? ?? '',
        toMessageId: map['toMessageId'] as String? ?? '',
        evidenceVersion: map['evidenceVersion'] as String? ?? 'unknown',
        shiftFit: _parseAgreement(map['shiftFit'] as String?),
        reasonFit: map['reasonFit'] is String
            ? _parseAgreement(map['reasonFit'] as String)
            : null,
        proposedContext: map['proposedContext'] as String?,
        userCorrection: map['userCorrection'] as String?,
        reviewedAt:
            DateTime.tryParse(map['reviewedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Represents a persistent chat conversation session with Solace.
class ChatConversationRecord {
  const ChatConversationRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.summary,
    this.summarizedThroughId,
    this.summaryUpdatedAt,
    this.shiftReviews = const [],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessageRecord> messages;

  /// A short summary of the older part of this conversation, made so a resumed
  /// chat does not need the whole history. Null until the conversation is long
  /// enough to need one.
  final String? summary;

  /// The last message the summary covers. Messages after it are still verbatim.
  final String? summarizedThroughId;
  final DateTime? summaryUpdatedAt;
  final List<TrajectoryShiftReview> shiftReviews;

  bool get hasSummary => summary != null && summary!.trim().isNotEmpty;

  bool get hasVoice => messages.any((m) => m.isVoice);
  int get messageCount => messages.length;
  bool get hasUserMessage => messages.any((m) => m.isUser);

  /// Returns the most recent user turn or latest message as a short preview snippet.
  String get preview {
    if (messages.isEmpty) return 'No messages yet';
    // Find the latest user message or latest message
    final lastUserMsg = messages.lastWhere(
      (m) => m.isUser,
      orElse: () => messages.last,
    );
    if (lastUserMsg.isVoice) {
      if (lastUserMsg.transcription != null &&
          lastUserMsg.transcription!.trim().isNotEmpty) {
        return '🎤 "${lastUserMsg.transcription!.trim()}"';
      }
      return '🎤 Voice note (${lastUserMsg.voiceDuration})';
    }
    return lastUserMsg.text.trim();
  }

  /// Human-readable relative or formatted timestamp.
  String get dateStr {
    final now = DateTime.now();
    final diff = now.difference(updatedAt);
    if (diff.inMinutes < 2) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';

    if (now.year == updatedAt.year &&
        now.month == updatedAt.month &&
        now.day == updatedAt.day) {
      var h = updatedAt.hour % 12;
      if (h == 0) h = 12;
      final m = updatedAt.minute.toString().padLeft(2, '0');
      final period = updatedAt.hour >= 12 ? 'PM' : 'AM';
      return 'Today · $h:$m $period';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == updatedAt.year &&
        yesterday.month == updatedAt.month &&
        yesterday.day == updatedAt.day) {
      var h = updatedAt.hour % 12;
      if (h == 0) h = 12;
      final m = updatedAt.minute.toString().padLeft(2, '0');
      final period = updatedAt.hour >= 12 ? 'PM' : 'AM';
      return 'Yesterday · $h:$m $period';
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthStr = months[updatedAt.month - 1];
    var h = updatedAt.hour % 12;
    if (h == 0) h = 12;
    final m = updatedAt.minute.toString().padLeft(2, '0');
    final period = updatedAt.hour >= 12 ? 'PM' : 'AM';
    return '$monthStr ${updatedAt.day} · $h:$m $period';
  }

  ChatConversationRecord copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessageRecord>? messages,
    String? summary,
    String? summarizedThroughId,
    DateTime? summaryUpdatedAt,
    List<TrajectoryShiftReview>? shiftReviews,
    bool clearSummary = false,
  }) {
    return ChatConversationRecord(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      summary: clearSummary ? null : (summary ?? this.summary),
      summarizedThroughId: clearSummary
          ? null
          : (summarizedThroughId ?? this.summarizedThroughId),
      summaryUpdatedAt: clearSummary
          ? null
          : (summaryUpdatedAt ?? this.summaryUpdatedAt),
      shiftReviews: shiftReviews ?? this.shiftReviews,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((m) => m.toMap()).toList(),
      if (summary != null) 'summary': summary,
      if (summarizedThroughId != null)
        'summarizedThroughId': summarizedThroughId,
      if (summaryUpdatedAt != null)
        'summaryUpdatedAt': summaryUpdatedAt!.toIso8601String(),
      if (shiftReviews.isNotEmpty)
        'shiftReviews': shiftReviews.map((r) => r.toMap()).toList(),
    };
  }

  factory ChatConversationRecord.fromMap(Map<String, dynamic> map) {
    return ChatConversationRecord(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Conversation with Sol',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: ((map['messages'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessageRecord.fromMap)
          .toList(),
      summary: map['summary'] as String?,
      summarizedThroughId: map['summarizedThroughId'] as String?,
      summaryUpdatedAt:
          DateTime.tryParse(map['summaryUpdatedAt'] as String? ?? ''),
      shiftReviews: ((map['shiftReviews'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TrajectoryShiftReview.fromMap)
          .toList(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ChatConversationRecord.fromJson(String source) =>
      ChatConversationRecord.fromMap(
          jsonDecode(source) as Map<String, dynamic>);
}
