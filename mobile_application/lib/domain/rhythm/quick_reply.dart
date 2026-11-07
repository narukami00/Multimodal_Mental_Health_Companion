import 'dart:convert';

/// A check-in typed outside the app (in the reminder notification, or in the home-screen pop-up). It is only
/// written down at the moment; the app saves it properly, with the same safety check as any other words,
/// the next time it is open.
class QuickReply {
  const QuickReply({required this.text, required this.at});

  final String text;
  final DateTime at;

  String encode() => jsonEncode({'text': text, 'at': at.toIso8601String()});

  /// Null for anything that is not a usable reply, so one odd entry never blocks the others.
  static QuickReply? decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final text = cleanQuickReply(map['text'] as String?);
      final at = DateTime.tryParse(map['at'] as String? ?? '');
      if (text == null || at == null) return null;
      return QuickReply(text: text, at: at);
    } catch (_) {
      return null;
    }
  }
}

/// The longest a quick reply is kept. A reply is a few words; anything longer belongs in a journal entry.
const quickReplyMaxLength = 1000;

/// Trimmed, tidied, and cut to length; null when nothing is left.
String? cleanQuickReply(String? raw) {
  if (raw == null) return null;
  final tidy = raw.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (tidy.isEmpty) return null;
  return tidy.length > quickReplyMaxLength ? tidy.substring(0, quickReplyMaxLength).trimRight() : tidy;
}
