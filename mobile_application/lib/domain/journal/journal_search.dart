import '../../core/constants/moods.dart';
import '../../core/models/session_record.dart';
import '../chat/conversation_search.dart';

/// Returns whether [session] matches all whitespace-separated terms in [query]
/// across its text/transcript, effective mood label, and capture mode.
bool matchesJournalQuery(SessionRecord session, String query) {
  final terms = searchQueryTerms(query);
  if (terms.isEmpty) return true;

  final moodWord = session.effectiveMood == null
      ? ''
      : Moods.display(session.effectiveMood);
  final haystack = [
    session.text?.trim() ?? '',
    moodWord,
    session.mode.name,
  ].join(' ').toLowerCase();

  return terms.every(haystack.contains);
}

/// Centers long journal snippets around the earliest keyword match so the
/// highlight stays visible inside two-line preview cards.
String journalSearchSnippet(String rawSnippet, String query) {
  final terms = searchQueryTerms(query);
  if (terms.isEmpty || rawSnippet.length <= 95) return rawSnippet;

  final lower = rawSnippet.toLowerCase();
  var earliest = -1;
  for (final term in terms) {
    final idx = lower.indexOf(term);
    if (idx != -1 && (earliest == -1 || idx < earliest)) {
      earliest = idx;
    }
  }
  if (earliest <= 55) return rawSnippet;

  final start = (earliest - 24).clamp(0, rawSnippet.length);
  final end = (earliest + 90).clamp(start, rawSnippet.length);
  final prefix = start > 0 ? '...' : '';
  final suffix = end < rawSnippet.length ? '...' : '';
  return '$prefix${rawSnippet.substring(start, end).trim()}$suffix';
}
