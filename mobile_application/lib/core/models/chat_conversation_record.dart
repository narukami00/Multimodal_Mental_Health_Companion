import 'dart:convert';
import 'chat_message_record.dart';

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
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ChatConversationRecord.fromJson(String source) =>
      ChatConversationRecord.fromMap(
          jsonDecode(source) as Map<String, dynamic>);
}
