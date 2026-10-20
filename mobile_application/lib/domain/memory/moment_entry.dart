import '../../core/models/emotion_result.dart';
import '../../core/models/memory_moment.dart';
import 'moment_extractor.dart';

/// Something the person wrote or said that they may choose to keep as a moment: one journal entry or one chat
/// message, with how the model read it when it did.
class MomentEntry {
  const MomentEntry({
    required this.text,
    required this.source,
    required this.sourceRef,
    this.at,
    this.moodWord,
    this.reading,
  });

  /// All of what they wrote or said.
  final String text;
  final MomentSource source;

  /// The entry or message it came from, so deleting that also deletes the moment.
  final String sourceRef;
  final DateTime? at;
  final String? moodWord;
  final EmotionResult? reading;
}

/// What to offer for keeping from [text]: all of it when it is short enough, otherwise the person's own sentence
/// that reads most like a good moment, otherwise the start of it, cut at a word. It is only ever their own words,
/// and they can trim or change it before keeping.
String suggestMomentText(String text) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= MemoryMoment.maxLength) return clean;
  final best = RuleBasedMomentExtractor.bestSentence(clean);
  if (best != null && best.length <= MemoryMoment.maxLength) return best;
  final cut = clean.lastIndexOf(' ', MemoryMoment.maxLength - 1);
  return clean.substring(0, cut > 40 ? cut : MemoryMoment.maxLength - 1);
}
