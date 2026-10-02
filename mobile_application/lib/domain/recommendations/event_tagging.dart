import '../../core/models/event_tag.dart';

class EventTaggingService {
  const EventTaggingService();

  static const _canonicalAliases = {
    'work': {'work', 'job', 'office', 'school'},
    'relationships': {'relationship', 'family', 'friend', 'friends', 'partner'},
    'sleep': {'sleep', 'rest', 'tired'},
    'health': {'health', 'appointment', 'body'},
    'home': {'home', 'house', 'chores'},
    'money': {'money', 'finance', 'bill', 'bills'},
  };

  /// The themes the app recognises, in a fixed order, for offering as choices.
  static List<String> get knownThemes => _canonicalAliases.keys.toList();

  String canonicalize(String label) {
    final normalized = _normalize(label);
    for (final entry in _canonicalAliases.entries) {
      if (entry.value.contains(normalized)) return entry.key;
    }
    return normalized;
  }

  EventTag fromUserLabel(String label, {DateTime? now}) {
    return EventTag(
      id: _id(),
      label: label.trim(),
      canonicalLabel: canonicalize(label),
      source: EventTagSource.user,
      createdAt: now ?? DateTime.now(),
    );
  }

  List<EventTag> extractKnownTags(String text, {DateTime? now}) {
    final normalized = text.toLowerCase();
    return [
      for (final canonical in _canonicalAliases.keys)
        if (_canonicalAliases[canonical]!.any(normalized.contains))
          EventTag(
            id: _id(),
            label: canonical,
            canonicalLabel: canonical,
            source: EventTagSource.extracted,
            createdAt: now ?? DateTime.now(),
          ),
    ];
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();

  String _normalize(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
