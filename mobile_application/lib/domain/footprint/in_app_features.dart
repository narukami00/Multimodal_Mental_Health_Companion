import '../../core/constants/moods.dart';
import '../../core/day_key.dart';
import '../../core/models/chat_conversation_record.dart';
import '../../core/models/daily_features.dart';
import '../../core/models/session_record.dart';

/// Longest gap between two chat messages that still counts as one sitting. A
/// longer silence ends the sitting rather than being counted as time spent.
const chatSittingGap = Duration(minutes: 5);

/// What the app itself knows about [day]: check-ins, mood words, words written,
/// and time spent talking to Sol.
///
/// Pure. It reads only what the user already gave the app and invents nothing:
/// a mood median exists only if a mood word was chosen, and a latency only if a
/// reminder and a check-in both exist.
///
/// Returns null for a day before the app was first opened, because nothing was
/// observed then. A day since with no activity is a real day with zero check-ins,
/// not a missing one.
///
/// [reminderMinutes] is the current reminder time, or null if none is set.
/// Past days are measured against today's reminder, which is an approximation
/// if it changed.
DailyFeatures? deriveInAppFeatures({
  required DateTime day,
  required List<SessionRecord> sessions,
  required List<ChatConversationRecord> conversations,
  DateTime? firstRunAt,
  int? reminderMinutes,
}) {
  final date = dateOnly(day);
  if (firstRunAt != null && date.isBefore(dateOnly(firstRunAt))) return null;

  final key = dayKey(date);
  final todays = [
    for (final session in sessions)
      if (dayKey(session.createdAt) == key) session,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final first = todays.isEmpty ? null : todays.first.createdAt;
  final firstMinute = first == null ? null : first.hour * 60 + first.minute;

  return DailyFeatures(
    dayKey: key,
    sources: const {'inApp'},
    checkInCount: todays.length,
    firstCheckInMinute: firstMinute,
    checkInLatencyMinutes: firstMinute == null || reminderMinutes == null
        ? null
        : firstMinute - reminderMinutes,
    selfMoodMedian: _median([
      for (final session in todays)
        if (Moods.score(session.mood) case final score?) score,
    ]),
    journalWordCount: todays.fold<int>(
      0,
      (total, session) => total + _wordCount(session.text),
    ),
    chatMinutes: _chatMinutes(conversations, key),
  );
}

int _wordCount(String? text) {
  if (text == null) return 0;
  return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Minutes spent in conversation on [key], estimated from message times.
///
/// Each gap between consecutive messages counts up to [chatSittingGap], so a
/// walk away mid-chat is not counted as time spent. A conversation the user
/// spoke in that day counts at least one minute. Only same-day pairs are
/// counted, so a chat that crosses midnight splits by the local day.
int _chatMinutes(List<ChatConversationRecord> conversations, String key) {
  var minutes = 0;
  for (final conversation in conversations) {
    final messages = [
      for (final message in conversation.messages)
        if (dayKey(message.timestamp) == key) message,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Sol's opening greeting is not the user spending time.
    if (!messages.any((message) => message.isUser)) continue;

    var seconds = 0;
    for (var i = 1; i < messages.length; i++) {
      final gap = messages[i].timestamp.difference(messages[i - 1].timestamp);
      seconds += (gap > chatSittingGap ? chatSittingGap : gap).inSeconds;
    }
    final spent = (seconds / 60).ceil();
    minutes += spent < 1 ? 1 : spent;
  }
  return minutes;
}
