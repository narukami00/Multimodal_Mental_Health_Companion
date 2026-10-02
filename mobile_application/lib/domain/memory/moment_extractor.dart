import '../../core/day_key.dart';
import '../../core/models/memory_moment.dart';

/// What an extractor is given: one entry the person wrote or said.
class MomentCandidate {
  const MomentCandidate({
    required this.text,
    required this.source,
    required this.createdAt,
    this.sourceRef,
    this.moodWord,
    this.emotionClass,
    this.emotionConfidence,
  });

  final String text;
  final MomentSource source;
  final DateTime createdAt;
  final String? sourceRef;

  /// The mood word they chose with it, if any (self-reported).
  final String? moodWord;

  /// What a model read from the text, if one has (model-inferred).
  final String? emotionClass;
  final double? emotionConfidence;
}

/// A moment worth asking about. Nothing is kept until the person agrees.
class MomentProposal {
  const MomentProposal({
    required this.text,
    required this.tone,
    required this.source,
    required this.occurredOn,
    this.sourceRef,
    this.moodWord,
    this.emotionClass,
    this.emotionConfidence,
  });

  final String text;
  final MomentTone tone;
  final MomentSource source;
  final String occurredOn;
  final String? sourceRef;
  final String? moodWord;
  final String? emotionClass;
  final double? emotionConfidence;
}

/// Finds a moment in an entry. The seam where a smarter reader (a model on the
/// companion server) replaces the rule-based one without touching anything else.
///
/// Contract: only ever returns something the person *said*, shortened but not
/// reworded or added to; returns null rather than guess; and never returns
/// anything [momentIsSensitive] flags.
abstract interface class MomentExtractor {
  Future<MomentProposal?> extract(MomentCandidate candidate);
}

/// Topics Sol never offers to remember on its own: crisis and self-harm, loss,
/// health, money trouble, and harm done to them. Matched on whole words so
/// "therapist" is not caught by "rape". A person can still choose to add a
/// moment themselves.
bool momentIsSensitive(String text) {
  final lower = text.toLowerCase();
  return _sensitive.any((pattern) => pattern.hasMatch(lower));
}

final _sensitive = [
  for (final word in const [
    r'suicid\w*',
    r'kill (?:myself|me)',
    r'end it all',
    r'want to die',
    r'self[- ]?harm\w*',
    r'hurt(?:ing)? myself',
    r'overdos\w*',
    r'died',
    r'dead',
    r'death',
    r'funeral',
    r'passed away',
    r'grie[fv]\w*',
    r'miscarriage',
    r'diagnos\w*',
    r'cancer',
    r'hospital\w*',
    r'medication',
    r'panic attack\w*',
    r'abus\w*',
    r'assault\w*',
    r'rape\w*',
    r'debt',
    r'evict\w*',
    r'bankrupt\w*',
    r'laid off',
    r'fired',
  ])
    RegExp('\\b$word\\b'),
];

/// A deterministic, offline reader: finds one sentence where the person says
/// something good happened, in their own words.
///
/// It is cautious on purpose. It wants a first-person, past-tense account and a
/// warm word, skips questions and anything negated, and when unsure returns
/// nothing, because a missed moment costs little and a wrong one costs trust.
class RuleBasedMomentExtractor implements MomentExtractor {
  const RuleBasedMomentExtractor();

  @override
  Future<MomentProposal?> extract(MomentCandidate candidate) async {
    if (momentIsSensitive(candidate.text)) return null;

    String? best;
    var bestScore = 0;
    for (final sentence in _sentences(candidate.text)) {
      final score = _score(sentence);
      if (score > bestScore) {
        best = sentence;
        bestScore = score;
      }
    }
    if (best == null || bestScore < 2) return null;

    return MomentProposal(
      text: _tidy(best),
      tone: MomentTone.warm,
      source: candidate.source,
      occurredOn: dayKey(candidate.createdAt),
      sourceRef: candidate.sourceRef,
      moodWord: candidate.moodWord,
      emotionClass: candidate.emotionClass,
      emotionConfidence: candidate.emotionConfidence,
    );
  }

  static List<String> _sentences(String text) => [
    for (final part in text.split(RegExp(r'(?<=[.!])\s+|\n+')))
      if (part.trim().length >= 18 && part.trim().length <= 220) part.trim(),
  ];

  static int _score(String sentence) {
    final lower = sentence.toLowerCase();
    if (lower.endsWith('?')) return 0;
    if (_negated.hasMatch(lower)) return 0;
    if (!_firstPerson.hasMatch(lower)) return 0;
    var score = 0;
    if (_event.hasMatch(lower)) score += 1;
    if (_warm.hasMatch(lower)) score += 1;
    // Needs both an event and a warm word, so "I felt good" alone, with nothing
    // that happened, does not become a moment.
    return score == 2 ? 2 : 0;
  }

  static String _tidy(String sentence) {
    var text = sentence.trim();
    if (text.length > MemoryMoment.maxLength) {
      final cut = text.lastIndexOf(' ', MemoryMoment.maxLength - 1);
      text = '${text.substring(0, cut > 40 ? cut : MemoryMoment.maxLength - 1)}…';
    }
    return text;
  }

  static final _firstPerson = RegExp(r"\b(i|we|my|i'm|i've|me)\b");
  static final _event = RegExp(
    r'\b(went|had|got|met|saw|called|walked|cooked|made|visited|finished|'
    r'managed|started|played|read|wrote|painted|cleaned|baked|talked|spoke|'
    r'laughed|hung out|caught up|stepped outside|sat outside|took|did|tried|'
    r'ran|danced|sang|helped|shared|celebrated|passed)\b',
  );
  static final _warm = RegExp(
    r'\b(happy|glad|good|great|nice|lovely|enjoyed|enjoy|proud|fun|relieved|'
    r'relief|grateful|thankful|laughed|smiled|smile|calm|peaceful|better|'
    r'lighter|warm|wonderful|amazing|loved|cheerful|content|hopeful|calmer|'
    r'happier|relaxed|brighter)\b',
  );
  static final _negated = RegExp(
    r"\b(not|n't|never|no|nothing|without|didn't|wasn't|couldn't|wouldn't)\b"
    r"[^.!?]{0,20}\b(happy|glad|good|great|nice|enjoy\w*|proud|fun|relieved|"
    r"better|calm|lighter|wonderful|amazing)\b",
  );
}
