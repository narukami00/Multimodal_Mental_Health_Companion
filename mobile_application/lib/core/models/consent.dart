/// What a consent key currently allows.
///
/// Anything short of [granted] fails closed: the feature behind the key does not
/// run. [notAsked] and [declined] are completed, non-punitive states, not
/// failures.
enum ConsentStatus { notAsked, granted, declined, revoked, needsReconsent }

/// One consent the app asks for, named `{category}:{modality}:{purpose}` as in
/// `docs/specifications/CONSENT.md` so this minimal store can later be absorbed
/// by the full one without renaming anything.
///
/// Only the keys the digital well-being work needs exist here.
class ConsentKey {
  const ConsentKey._({
    required this.category,
    required this.modality,
    required this.purpose,
    required this.currentVersion,
    this.parent,
  });

  final String category;
  final String modality;
  final String purpose;

  /// Version of the consent text on offer now, as `major.minor`. A change of
  /// major means the scope changed and consent must be asked for again.
  final String currentVersion;

  /// A sub-grant only counts while its parent is also granted.
  final ConsentKey? parent;

  String get key => '$category:$modality:$purpose';

  /// Reading usage events (screen time, active hours, sleep estimate) on this
  /// device to build daily features. Never leaves the phone.
  static const usageFootprint = ConsentKey._(
    category: 'usageFootprint',
    modality: 'metadata',
    purpose: 'localInsights',
    currentVersion: '1.0',
  );

  /// Keeping the names of the most-used apps, on device only. Category totals
  /// are the default and need only [usageFootprint].
  static const topAppNames = ConsentKey._(
    category: 'usageFootprint',
    modality: 'metadata',
    purpose: 'topAppNames',
    currentVersion: '1.0',
    parent: usageFootprint,
  );

  /// Sending the short profile snippet to the companion server so replies can
  /// reflect it.
  static const profileSnippet = ConsentKey._(
    category: 'profileSnippet',
    modality: 'text',
    purpose: 'chatCompanion',
    currentVersion: '1.0',
  );

  static const all = [usageFootprint, topAppNames, profileSnippet];

  static ConsentKey? fromKey(String key) {
    for (final candidate in all) {
      if (candidate.key == key) return candidate;
    }
    return null;
  }

  @override
  String toString() => key;
}

/// One decision the user made, kept so a consent can always be explained.
class ConsentEvent {
  const ConsentEvent({
    required this.key,
    required this.status,
    required this.textVersion,
    required this.occurredAt,
  });

  final String key;
  final ConsentStatus status;
  final String textVersion;
  final DateTime occurredAt;

  Map<String, Object?> toMap() => {
    'key': key,
    'status': status.name,
    'textVersion': textVersion,
    'occurredAt': occurredAt.toIso8601String(),
  };

  static ConsentEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final occurredAt = DateTime.tryParse(raw['occurredAt'] as String? ?? '');
    if (key is! String || occurredAt == null) return null;
    final status = ConsentStatus.values.firstWhere(
      (value) => value.name == raw['status'],
      orElse: () => ConsentStatus.declined,
    );
    // Only ever fail closed on something unreadable.
    if (status == ConsentStatus.notAsked ||
        status == ConsentStatus.needsReconsent) {
      return null;
    }
    return ConsentEvent(
      key: key,
      status: status,
      textVersion: raw['textVersion'] as String? ?? '0.0',
      occurredAt: occurredAt,
    );
  }
}

/// Every decision made, oldest first. The current state of a key is its latest
/// event, so history and state can never disagree.
class ConsentLedger {
  const ConsentLedger([this.events = const []]);

  final List<ConsentEvent> events;

  ConsentEvent? _latest(ConsentKey key) {
    for (var i = events.length - 1; i >= 0; i--) {
      if (events[i].key == key.key) return events[i];
    }
    return null;
  }

  /// What [key] allows right now, ignoring its parent.
  ConsentStatus statusOf(ConsentKey key) {
    final latest = _latest(key);
    if (latest == null) return ConsentStatus.notAsked;
    if (latest.status == ConsentStatus.granted &&
        _major(latest.textVersion) < _major(key.currentVersion)) {
      return ConsentStatus.needsReconsent;
    }
    return latest.status;
  }

  /// Whether the feature behind [key] may run: granted on the current text,
  /// and so is its parent, if it has one.
  bool isGranted(ConsentKey key) {
    if (statusOf(key) != ConsentStatus.granted) return false;
    final parent = key.parent;
    return parent == null || isGranted(parent);
  }

  ConsentLedger record(ConsentEvent event) =>
      ConsentLedger(List.unmodifiable([...events, event]));

  Map<String, Object?> toMap() => {
    'events': [for (final event in events) event.toMap()],
  };

  factory ConsentLedger.fromMap(Map<String, dynamic> map) {
    final raw = map['events'] as List<dynamic>? ?? const [];
    return ConsentLedger(
      List.unmodifiable([
        for (final entry in raw)
          if (ConsentEvent.fromMap(entry) case final event?) event,
      ]),
    );
  }

  static int _major(String version) =>
      int.tryParse(version.split('.').first) ?? 0;
}
