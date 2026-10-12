import '../../core/constants/moods.dart';
import '../../core/models/chat_conversation_record.dart';
import '../../core/models/chat_message_record.dart';
import '../../core/models/emotion_result.dart';

/// One of the person's messages that the model has read.
class ReadMessage {
  ReadMessage(this.message, this.reading)
      : score = scoreOf(reading),
        energy = energyOf(reading),
        mood = Moods.fromReadingMood(reading.mood);

  final ChatMessageRecord message;
  final EmotionResult reading;

  /// -1 (heavy) .. 1 (light): how the model split the message between heavy and light.
  final double score;

  /// -1 (low energy) .. 1 (high energy).
  final double energy;

  /// The internal mood word (Bright/Steady/Quiet/Tender/Wobbly); shown through [Moods.display].
  final String mood;

  String get word => Moods.display(mood);

  static double scoreOf(EmotionResult r) {
    final p = r.valenceProbs;
    if (p != null) return ((p['positive'] ?? 0) - (p['negative'] ?? 0)).clamp(-1.0, 1.0);
    return (r.valence ?? 0).clamp(-1.0, 1.0);
  }

  static double energyOf(EmotionResult r) {
    final p = r.arousalProbs;
    if (p != null) return ((p['high'] ?? 0) - (p['low'] ?? 0)).clamp(-1.0, 1.0);
    return (r.arousal ?? 0).clamp(-1.0, 1.0);
  }
}

/// A message that read clearly heavier or lighter than the one before it. It points at what was being
/// said at that moment; it does not claim the words caused the feeling.
class MoodShift {
  const MoodShift({required this.from, required this.to});

  final ReadMessage from;
  final ReadMessage to;

  double get change => to.score - from.score;
  bool get lighter => change > 0;
}

/// Everything the "how this conversation felt" page shows, worked out from the readings stored on the
/// person's messages. Plain words only; nothing here is a verdict.
class ConversationBreakdown {
  ConversationBreakdown._({
    required this.points,
    required this.userMessages,
    required this.unreadMessages,
    required this.moodCounts,
    required this.shifts,
    required this.keywords,
    required this.notes,
  });

  /// Read messages, oldest first.
  final List<ReadMessage> points;
  final int userMessages;

  /// The person's messages with words but no reading (not read yet, or the server was away).
  final int unreadMessages;

  /// Display word -> how many messages, in the order Upbeat, Calm, Even, Low, Tense (zeros included).
  final Map<String, int> moodCounts;
  final List<MoodShift> shifts;
  final List<String> keywords;
  final List<String> notes;

  bool get hasReadings => points.isNotEmpty;

  /// The mood word most messages read as; null with no readings. Ties go to the more recent.
  String? get dominantWord {
    String? best;
    var bestCount = 0;
    for (final p in points) {
      final c = moodCounts[p.word] ?? 0;
      if (c >= bestCount) {
        best = p.word;
        bestCount = c;
      }
    }
    return best;
  }

  double get averageScore => points.isEmpty ? 0 : points.fold<double>(0, (a, p) => a + p.score) / points.length;
  double get averageEnergy => points.isEmpty ? 0 : points.fold<double>(0, (a, p) => a + p.energy) / points.length;

  static const moodOrder = ['Upbeat', 'Calm', 'Even', 'Low', 'Tense'];
  static const shiftThreshold = 0.4;
  static const maxShifts = 3;

  factory ConversationBreakdown.from(ChatConversationRecord conversation) {
    final points = <ReadMessage>[];
    var userMessages = 0;
    var unread = 0;
    for (final m in conversation.messages) {
      if (!m.isUser) continue;
      final words = m.spokenText;
      if (words.isEmpty || words == 'Audio reflection') continue;
      userMessages++;
      final reading = m.reading;
      if (reading == null) {
        unread++;
      } else {
        points.add(ReadMessage(m, reading));
      }
    }

    final counts = {for (final w in moodOrder) w: 0};
    for (final p in points) {
      counts[p.word] = (counts[p.word] ?? 0) + 1;
    }

    final shifts = <MoodShift>[
      for (var i = 1; i < points.length; i++)
        if ((points[i].score - points[i - 1].score).abs() >= shiftThreshold) MoodShift(from: points[i - 1], to: points[i]),
    ]..sort((a, b) => b.change.abs().compareTo(a.change.abs()));

    return ConversationBreakdown._(
      points: List.unmodifiable(points),
      userMessages: userMessages,
      unreadMessages: unread,
      moodCounts: counts,
      shifts: List.unmodifiable(shifts.take(maxShifts).toList()
        ..sort((a, b) => a.to.message.timestamp.compareTo(b.to.message.timestamp))),
      keywords: _keywords([for (final m in conversation.messages) if (m.isUser) m.spokenText]),
      notes: _notes(points),
    );
  }

  static List<String> _notes(List<ReadMessage> points) {
    if (points.length < 3) return const ['Too few messages have been read to see a pattern yet.'];
    final notes = <String>[];
    final half = points.length ~/ 2;
    double avg(Iterable<ReadMessage> it) => it.fold<double>(0, (a, p) => a + p.score) / it.length;
    final first = avg(points.take(half));
    final last = avg(points.skip(points.length - half));
    if (last - first >= 0.2) {
      notes.add('Your messages read lighter toward the end than at the start.');
    } else if (first - last >= 0.2) {
      notes.add('Your messages read heavier toward the end than at the start.');
    }
    final heavy = points.where((p) => p.score < -0.2).length;
    final light = points.where((p) => p.score > 0.2).length;
    if (heavy / points.length >= 0.6) {
      notes.add('Most of your messages here read on the heavier side.');
    } else if (light / points.length >= 0.6) {
      notes.add('Most of your messages here read on the lighter side.');
    }
    final energy = points.fold<double>(0, (a, p) => a + p.energy) / points.length;
    if (energy <= -0.3) {
      notes.add('Your messages mostly read low in energy.');
    } else if (energy >= 0.3) {
      notes.add('Your messages mostly read high in energy.');
    }
    if (notes.isEmpty) notes.add('Nothing stood out: the conversation read fairly even.');
    return notes;
  }

  static List<String> _keywords(List<String> texts) {
    final counts = <String, int>{};
    for (final text in texts) {
      final seen = <String>{};
      for (final raw in text.toLowerCase().split(RegExp(r"[^a-z']+"))) {
        final w = raw.replaceAll(RegExp(r"^'+|'+$"), '');
        if (w.length < 4 || _stop.contains(w) || !seen.add(w)) continue;
        counts[w] = (counts[w] ?? 0) + 1;
      }
    }
    final repeated = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [for (final e in repeated.take(8)) e.key];
  }

  static const _stop = {
    'about', 'above', 'after', 'again', 'against', 'also', 'always', 'because', 'been', 'before', 'being', 'below',
    'between', 'both', 'cannot', 'could', "couldn't", 'does', "doesn't", 'doing', "don't", 'down', 'during', 'each',
    'even', 'ever', 'every', 'feel', 'feeling', 'feels', 'felt', 'from', 'further', 'gets', 'getting', 'give', 'going',
    'gone', 'have', "haven't", 'having', 'here', 'hers', 'herself', 'himself', 'just', 'know', 'like', 'little',
    'lots', 'made', 'make', 'many', 'maybe', 'might', 'more', 'most', 'much', 'must', 'myself', 'need', 'never',
    'okay', 'once', 'only', 'other', 'ours', 'over', 'really', 'same', 'should', 'since', 'some', 'something',
    'still', 'such', 'take', 'than', 'that', "that's", 'their', 'them', 'then', 'there', "there's", 'these', 'they',
    'thing', 'things', 'think', 'this', 'those', 'though', 'through', 'today', 'under', 'until', 'very', 'want',
    'wants', 'well', 'were', 'what', "what's", 'when', 'where', 'which', 'while', 'will', 'with', 'within',
    'without', 'would', "wouldn't", 'yeah', 'your', 'yours', 'yourself', "i'm", "i've", "i'll", "it's", "can't",
    "didn't", "isn't", "wasn't", "won't", 'right', 'kind', 'sort', 'bit', 'lot', 'tell', 'said', 'says',
  };
}
