import '../../core/models/chat_conversation_record.dart';
import '../../core/models/chat_message_record.dart';

/// Older turns that are due to be folded into the conversation's summary.
class SummaryPlan {
  const SummaryPlan({required this.toSummarize, required this.throughId});

  /// The messages to summarize, oldest first.
  final List<ChatMessageRecord> toSummarize;

  /// The last of them. Everything after it stays verbatim.
  final String throughId;
}

/// How many messages may pile up since the last summary before another is due
/// (CHAT_FEATURES s19: more than 12 since the last summary).
const summaryTriggerAfter = 12;

/// How many of the newest messages always stay word for word.
const summaryKeepRecent = 8;

/// How many recent turns are handed back when a conversation is resumed.
const resumeRecentTurns = 10;

/// What a message says, for the model: the typed text, or a voice message's
/// transcription. Empty when there is nothing to say.
String messageContent(ChatMessageRecord message) {
  final spoken = message.transcription?.trim();
  if (message.isVoice && spoken != null && spoken.isNotEmpty) return spoken;
  return message.text.trim();
}

/// The messages not yet covered by the summary and with something to say.
List<ChatMessageRecord> unsummarized(ChatConversationRecord conversation) {
  final through = conversation.summarizedThroughId;
  var start = 0;
  if (through != null) {
    final index = conversation.messages.indexWhere((m) => m.id == through);
    if (index >= 0) start = index + 1;
  }
  return [
    for (final m in conversation.messages.skip(start))
      if (messageContent(m).isNotEmpty) m,
  ];
}

/// Decides whether the conversation needs a fresh summary, and of what.
///
/// Pure. Null while the conversation is short. When more than
/// [summaryTriggerAfter] messages are not yet summarized, everything but the
/// newest [summaryKeepRecent] is due.
SummaryPlan? planSummary(
  ChatConversationRecord conversation, {
  int triggerAfter = summaryTriggerAfter,
  int keepRecent = summaryKeepRecent,
}) {
  final pending = unsummarized(conversation);
  if (pending.length <= triggerAfter) return null;
  final due = pending.sublist(0, pending.length - keepRecent);
  if (due.isEmpty) return null;
  return SummaryPlan(toSummarize: due, throughId: due.last.id);
}

/// Messages as the server expects them: a role and what was said.
List<Map<String, String>> turnsOf(List<ChatMessageRecord> messages) => [
  for (final m in messages)
    if (messageContent(m).isNotEmpty)
      {'role': m.isUser ? 'user' : 'assistant', 'content': messageContent(m)},
];

/// What to send when a conversation is resumed: its summary, and the last few
/// turns word for word. Null for a conversation with nothing to carry.
Map<String, Object?>? resumeBlock(
  ChatConversationRecord? conversation, {
  int recentTurns = resumeRecentTurns,
}) {
  if (conversation == null) return null;
  final turns = turnsOf(conversation.messages);
  final recent = turns.length > recentTurns
      ? turns.sublist(turns.length - recentTurns)
      : turns;
  final summary = conversation.hasSummary ? conversation.summary!.trim() : null;
  // A greeting with no reply from the person is not worth resuming.
  final hasUser = conversation.messages.any((m) => m.isUser);
  if (!hasUser && summary == null) return null;
  return {
    if (summary != null) 'summary': summary,
    if (recent.isNotEmpty) 'recent': recent,
  };
}
