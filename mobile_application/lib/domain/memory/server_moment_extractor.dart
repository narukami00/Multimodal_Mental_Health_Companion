import '../../core/day_key.dart';
import '../../core/models/memory_moment.dart';
import 'moment_extractor.dart';

/// Asks the companion to quote one good moment from a message.
typedef MomentRequester = Future<String?> Function(String text, List<MomentContextLine> context);

/// A reader that asks the companion server's model first, for chat messages
/// only, and otherwise (or when the server has nothing, is slow, or is not
/// reachable) uses [fallback].
///
/// Only chat text is ever sent: it is already on the server, and journals and
/// check-ins never leave the phone. Whatever the server returns is checked here
/// again: it must be short, free of sensitive topics, and made of the person's
/// own words, so a paraphrase or an invention is thrown away rather than shown.
class ServerMomentExtractor implements MomentExtractor {
  ServerMomentExtractor({
    required this.requesterProvider,
    this.fallback = const RuleBasedMomentExtractor(),
    this.timeout = const Duration(seconds: 15),
  });

  final MomentExtractor fallback;
  final Duration timeout;

  /// Gives the requester for the live companion connection, or null when there
  /// is none. Asked each time, so a connection that comes and goes is handled.
  final MomentRequester? Function() requesterProvider;

  @override
  Future<MomentProposal?> extract(MomentCandidate candidate) async {
    final ask = requesterProvider();
    if (candidate.source != MomentSource.chat || ask == null) {
      return fallback.extract(candidate);
    }
    // Re-awaited inside a fresh async function so the future really is a
    // Future<String?>: a requester written as `async => 'text'` is a
    // Future<String> underneath, and a null timeout result would not fit it.
    Future<String?> asked() async => ask(candidate.text, candidate.context);
    final quoted = await asked()
        .timeout(timeout, onTimeout: () => null)
        .catchError((Object _) => null);
    final checked = acceptQuotedMoment(candidate.text, quoted, context: candidate.context);
    if (checked == null) return fallback.extract(candidate);
    return MomentProposal(
      text: checked,
      tone: MomentTone.warm,
      source: candidate.source,
      occurredOn: dayKey(candidate.createdAt),
      sourceRef: candidate.sourceRef,
      moodWord: candidate.moodWord,
      emotionClass: candidate.emotionClass,
      emotionConfidence: candidate.emotionConfidence,
    );
  }
}

/// [quoted] as a clean single line if it is an acceptable moment drawn from
/// [original] and the [context] before it, otherwise null. Mirrors the server's
/// own check.
///
/// Acceptable: short, not sensitive (in the line, the message or the earlier
/// lines), not vague, at least 80% of its words found in the conversation, and
/// at least two of them in the person's own message so the line is always about
/// something they actually said.
String? acceptQuotedMoment(
  String original,
  String? quoted, {
  List<MomentContextLine> context = const [],
}) {
  if (quoted == null) return null;
  final line = quoted
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp('^["\'\u201c\u201d]+|["\'\u201c\u201d]+\$'), '')
      .trim();
  if (line.isEmpty || line.toUpperCase().replaceAll('.', '') == 'NONE') return null;
  if (line.length > MemoryMoment.maxLength) return null;
  if (momentIsSensitive(line) || momentIsSensitive(original)) return null;
  if (context.any((c) => momentIsSensitive(c.text))) return null;

  // "About working: That was a great idea." is put together by the server from
  // a topic and the person's own sentence; its lead word is not theirs.
  final mine = _words(line.replaceFirst(RegExp(r'^about\b', caseSensitive: false), ''));
  if (mine.length < 4) return null;
  // Starting mid-sentence ("which felt really good.") is a fragment that cannot be read back later.
  if (_fragmentStarts.contains(mine.first)) return null;
  // A praise word followed by a complaint is sarcasm, not a good moment.
  if (_sarcasm.hasMatch(line.toLowerCase()) || _sarcasm.hasMatch(original.toLowerCase())) return null;
  if (momentIsVague(line)) return null;
  final theirs = _words(original).toSet();
  final known = {...theirs, for (final c in context) ..._words(c.text)};
  if (RegExp(r'^about\b', caseSensitive: false).hasMatch(line) && line.contains(':')) {
    // The topic is the one part that is not the person's sentence, so every
    // word of it must come from the conversation: no tolerance.
    final topic = _words(line.split(':').first).skip(1).toList();
    if (topic.isEmpty || topic.any((w) => !known.contains(w))) return null;
  }
  final shared = mine.where(known.contains).length;
  if (shared / mine.length < 0.8) return null;
  if (mine.toSet().where(theirs.contains).length < 2) return null;
  return line;
}

const _fragmentStarts = {'which', 'who', 'whose', 'and', 'but', 'because', 'although', 'though', 'whereas'};

// Mirrors the server's own sarcasm check.
final _sarcasm = RegExp(
  r'\b(?:great|wonderful|perfect|fantastic|brilliant|lovely|nice|amazing)\b[,!.]*\s+(?:another|more of|just what)\b'
  r"|\byeah,? right\b|\boh,? (?:great|wonderful|perfect|fabulous)\b|\bcould have been an e-?mail\b|\bjust what i needed\b"
  r'|\bas if\b|\bthanks a lot\b',
);

List<String> _words(String text) => [
  for (final m in RegExp(r"[a-z0-9']+").allMatches(text.toLowerCase())) m.group(0)!,
];
