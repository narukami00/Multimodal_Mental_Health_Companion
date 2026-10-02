import '../../core/day_key.dart';
import '../../core/models/memory_moment.dart';
import 'moment_extractor.dart';

/// Asks the companion to quote one good moment from a message.
typedef MomentRequester = Future<String?> Function(String text);

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
    Future<String?> asked() async => ask(candidate.text);
    final quoted = await asked()
        .timeout(timeout, onTimeout: () => null)
        .catchError((Object _) => null);
    final checked = acceptQuotedMoment(candidate.text, quoted);
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
/// [original], otherwise null. Mirrors the server's own check.
String? acceptQuotedMoment(String original, String? quoted) {
  if (quoted == null) return null;
  final line = quoted
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp('^["\'“”]+|["\'“”]+\$'), '')
      .trim();
  if (line.isEmpty || line.toUpperCase().replaceAll('.', '') == 'NONE') return null;
  if (line.length > MemoryMoment.maxLength) return null;
  if (momentIsSensitive(line) || momentIsSensitive(original)) return null;

  final mine = _words(line);
  if (mine.length < 4) return null;
  final theirs = _words(original).toSet();
  final shared = mine.where(theirs.contains).length;
  if (shared / mine.length < 0.8) return null;
  return line;
}

List<String> _words(String text) => [
  for (final m in RegExp(r"[a-z0-9']+").allMatches(text.toLowerCase())) m.group(0)!,
];
