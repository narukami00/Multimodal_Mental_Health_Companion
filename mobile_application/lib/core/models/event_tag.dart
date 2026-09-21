enum EventTagSource { user, extracted }

class EventTag {
  const EventTag({
    required this.id,
    required this.label,
    required this.canonicalLabel,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String canonicalLabel;
  final EventTagSource source;
  final DateTime createdAt;
}
