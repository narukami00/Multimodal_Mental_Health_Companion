import '../../core/constants/moods.dart';
import '../../core/day_key.dart';
import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../chat/conversation_breakdown.dart' show ReadMessage;

/// The journal side of the person's emotional picture over a stretch of days: how many entries of each
/// kind, how they read, and what each kind of entry tends to read as. Built only from what is stored on
/// the entries (the model's readings, or on older ones the word picked at the time). Descriptive: it
/// counts and never says why.
class JournalBreakdown {
  JournalBreakdown._({
    required this.days,
    required this.total,
    required this.read,
    required this.byMode,
    required this.moodCounts,
    required this.leanByMode,
    required this.averageScore,
    required this.averageEnergy,
  });

  final int days;

  /// All entries in the window, and how many of them carry a mood (a model reading or an older picked word).
  final int total;
  final int read;

  final Map<CaptureMode, int> byMode;

  /// Display word (Upbeat, Calm, Even, Low, Tense) -> number of entries, zeros included.
  final Map<String, int> moodCounts;

  /// What each kind of entry most often read as; null for a kind with fewer than two read entries or a tie.
  final Map<CaptureMode, String?> leanByMode;

  /// Averages over the entries the model actually read (-1 heavy .. 1 light, -1 low .. 1 high energy).
  final double? averageScore;
  final double? averageEnergy;

  static const wordOrder = ['Upbeat', 'Calm', 'Even', 'Low', 'Tense'];

  bool get isEmpty => total == 0;

  /// The word most entries read as; ties go to the first in [wordOrder]. Null with nothing read.
  String? get dominantWord {
    String? best;
    var bestCount = 0;
    for (final w in wordOrder) {
      final c = moodCounts[w] ?? 0;
      if (c > bestCount) {
        best = w;
        bestCount = c;
      }
    }
    return best;
  }

  /// "lighter", "heavier" or "about even", from the average split between heavy and light.
  String? get leaning {
    final s = averageScore;
    if (s == null) return null;
    if (s >= 0.15) return 'lighter';
    if (s <= -0.15) return 'heavier';
    return 'about even';
  }

  /// "low", "high" or "medium" energy on average.
  String? get energyWord {
    final e = averageEnergy;
    if (e == null) return null;
    if (e >= 0.2) return 'high';
    if (e <= -0.2) return 'low';
    return 'medium';
  }

  factory JournalBreakdown.from(List<SessionRecord> sessions, DateTime now, {int days = 30}) {
    final today = dateOnly(now);
    final first = DateTime(today.year, today.month, today.day - (days - 1));
    final inWindow = [for (final s in sessions) if (!dateOnly(s.createdAt).isBefore(first)) s];

    final byMode = {for (final m in CaptureMode.values) m: 0};
    final moodCounts = {for (final w in wordOrder) w: 0};
    final modeWords = {for (final m in CaptureMode.values) m: <String, int>{}};
    var read = 0;
    var scoreSum = 0.0, energySum = 0.0, modelRead = 0;
    for (final s in inWindow) {
      byMode[s.mode] = (byMode[s.mode] ?? 0) + 1;
      final mood = s.effectiveMood;
      if (mood != null && Moods.score(mood) != null) {
        final word = Moods.display(mood);
        moodCounts[word] = (moodCounts[word] ?? 0) + 1;
        modeWords[s.mode]![word] = (modeWords[s.mode]![word] ?? 0) + 1;
        read++;
      }
      final r = s.reading;
      if (r != null) {
        scoreSum += ReadMessage.scoreOf(r);
        energySum += ReadMessage.energyOf(r);
        modelRead++;
      }
    }

    String? lean(CaptureMode m) {
      final words = modeWords[m]!;
      final n = words.values.fold<int>(0, (a, b) => a + b);
      if (n < 2) return null;
      final ranked = words.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      if (ranked.length > 1 && ranked[0].value == ranked[1].value) return null;
      return ranked.first.key;
    }

    return JournalBreakdown._(
      days: days,
      total: inWindow.length,
      read: read,
      byMode: byMode,
      moodCounts: moodCounts,
      leanByMode: {for (final m in CaptureMode.values) m: lean(m)},
      averageScore: modelRead == 0 ? null : scoreSum / modelRead,
      averageEnergy: modelRead == 0 ? null : energySum / modelRead,
    );
  }
}
