import '../../core/models/chat_conversation_record.dart';

/// Pure-Dart keyword matching and excerpt extraction for local chat history search.
class ConversationSearchMatch {
  const ConversationSearchMatch({
    required this.conversationId,
    required this.titleMatched,
    required this.summaryMatched,
    required this.matchCount,
    this.matchedMessageId,
    this.matchedExcerpt,
  });

  final String conversationId;
  final bool titleMatched;
  final bool summaryMatched;
  final int matchCount;
  final String? matchedMessageId;
  final String? matchedExcerpt;
}

class TextHighlightSegment {
  const TextHighlightSegment(this.text, {required this.highlighted});

  final String text;
  final bool highlighted;
}

/// Splits [query] into unique non-empty lowercase terms (longest first so overlaps prefer whole phrases).
List<String> searchQueryTerms(String query) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return const [];
  final parts = trimmed
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toSet()
      .toList();
  parts.sort((a, b) => b.length.compareTo(a.length));
  return parts;
}

/// Splits [text] into non-overlapping segments marked [highlighted] wherever any term in [query] matches.
List<TextHighlightSegment> splitHighlightSegments(String text, String query) {
  if (text.isEmpty) return const [];
  final terms = searchQueryTerms(query);
  if (terms.isEmpty) {
    return [TextHighlightSegment(text, highlighted: false)];
  }
  final lower = text.toLowerCase();
  final ranges = <({int start, int end})>[];
  for (final term in terms) {
    var from = 0;
    while (true) {
      final idx = lower.indexOf(term, from);
      if (idx == -1) break;
      ranges.add((start: idx, end: idx + term.length));
      from = idx + term.length;
    }
  }
  if (ranges.isEmpty) {
    return [TextHighlightSegment(text, highlighted: false)];
  }
  ranges.sort((a, b) {
    final cmp = a.start.compareTo(b.start);
    return cmp != 0 ? cmp : b.end.compareTo(a.end);
  });
  final merged = <({int start, int end})>[];
  for (final r in ranges) {
    if (merged.isEmpty || r.start > merged.last.end) {
      merged.add(r);
    } else if (r.end > merged.last.end) {
      merged[merged.length - 1] = (start: merged.last.start, end: r.end);
    }
  }
  final segments = <TextHighlightSegment>[];
  var cursor = 0;
  for (final r in merged) {
    if (r.start > cursor) {
      segments.add(
        TextHighlightSegment(
          text.substring(cursor, r.start),
          highlighted: false,
        ),
      );
    }
    segments.add(
      TextHighlightSegment(text.substring(r.start, r.end), highlighted: true),
    );
    cursor = r.end;
  }
  if (cursor < text.length) {
    segments.add(
      TextHighlightSegment(text.substring(cursor), highlighted: false),
    );
  }
  return segments;
}

int _countMatches(String text, List<String> terms) {
  if (text.isEmpty || terms.isEmpty) return 0;
  final lower = text.toLowerCase();
  var count = 0;
  for (final term in terms) {
    var from = 0;
    while (true) {
      final idx = lower.indexOf(term, from);
      if (idx == -1) break;
      count++;
      from = idx + term.length;
    }
  }
  return count;
}

String _excerptAround(String text, List<String> terms, {int radius = 42}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return clean;
  final lower = clean.toLowerCase();
  int? firstHit;
  for (final term in terms) {
    final idx = lower.indexOf(term);
    if (idx != -1 && (firstHit == null || idx < firstHit)) {
      firstHit = idx;
    }
  }
  if (firstHit == null) {
    return clean.length <= radius * 2
        ? clean
        : '${clean.substring(0, radius * 2)}…';
  }
  final start = (firstHit - radius).clamp(0, clean.length);
  final end = (firstHit + radius + terms.first.length).clamp(0, clean.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < clean.length ? '…' : '';
  return '$prefix${clean.substring(start, end)}$suffix';
}

/// Evaluates whether [record] matches every term in [query] across title, summary, and messages.
ConversationSearchMatch? matchConversationRecord(
  ChatConversationRecord record,
  String query,
) {
  final terms = searchQueryTerms(query);
  if (terms.isEmpty) return null;

  final searchableCorpus = StringBuffer()
    ..write(record.title.toLowerCase())
    ..write(' ')
    ..write((record.summary ?? '').toLowerCase());
  for (final msg in record.messages) {
    searchableCorpus
      ..write(' ')
      ..write(msg.text.toLowerCase());
    if (msg.transcription != null) {
      searchableCorpus
        ..write(' ')
        ..write(msg.transcription!.toLowerCase());
    }
  }
  final corpus = searchableCorpus.toString();
  for (final term in terms) {
    if (!corpus.contains(term)) return null;
  }

  final titleHits = _countMatches(record.title, terms);
  final summaryHits = _countMatches(record.summary ?? '', terms);
  var totalHits = titleHits + summaryHits;
  String? matchedMessageId;
  String? matchedExcerpt;

  // Prefer recent matching messages first so the user sees the freshest matching turn.
  for (final msg in record.messages.reversed) {
    final textHits = _countMatches(msg.text, terms);
    final transHits = _countMatches(msg.transcription ?? '', terms);
    totalHits += textHits + transHits;
    if (matchedMessageId == null && (textHits > 0 || transHits > 0)) {
      matchedMessageId = msg.id;
      final sourceText = transHits > 0 && textHits == 0
          ? msg.transcription!
          : msg.text;
      matchedExcerpt = _excerptAround(sourceText, terms);
    }
  }

  if (matchedExcerpt == null && summaryHits > 0 && record.summary != null) {
    matchedExcerpt = _excerptAround(record.summary!, terms);
  }

  return ConversationSearchMatch(
    conversationId: record.id,
    titleMatched: titleHits > 0,
    summaryMatched: summaryHits > 0,
    matchCount: totalHits,
    matchedMessageId: matchedMessageId,
    matchedExcerpt: matchedExcerpt,
  );
}
