/// Where a moment came from.
enum MomentSource { chat, journal, checkIn, review, manual }

/// Where a moment stands. Only [confirmed] moments are used by anything.
///
/// A moment is proposed ([pending]) and waits for a yes. Saying no deletes it;
/// there is no "declined" pile that quietly keeps the text.
enum MomentState { pending, confirmed, hidden }

/// How the moment sits emotionally, from what the person said.
enum MomentTone { warm, neutral, heavy }

/// One thing the person said happened, kept in their own framing and only after
/// they agreed.
///
/// What it holds is deliberately small. [text] is theirs (or their edit of it).
/// [moodWord] is the word *they* chose around then, when they chose one.
/// [emotionClass] and [emotionConfidence] are what a model read from the entry,
/// kept apart and labelled so nothing downstream mistakes a model's reading for
/// something the person said.
///
/// The same shape later serves an export for the person themselves or a
/// clinician: it has a stable id, a schema version, timestamps, an origin for
/// each kind of value, and an explicit state.
class MemoryMoment {
  const MemoryMoment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.occurredOn,
    required this.source,
    this.state = MomentState.pending,
    this.tone = MomentTone.warm,
    this.moodWord,
    this.emotionClass,
    this.emotionConfidence,
    this.editedByUser = false,
    this.sourceRef,
    this.updatedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  static const currentSchemaVersion = 1;

  /// A moment is a sentence, not an essay. Longer text is cut when proposed.
  static const maxLength = 140;

  final String id;
  final String text;
  final DateTime createdAt;

  /// Local `yyyy-MM-dd` the moment is about, usually the day it was written.
  final String occurredOn;
  final MomentSource source;
  final MomentState state;
  final MomentTone tone;

  /// Self-reported: the mood word they chose with that entry, if any.
  final String? moodWord;

  /// Model-inferred, from the entry text. Null until a model has read it.
  final String? emotionClass;
  final double? emotionConfidence;

  final bool editedByUser;

  /// The session or message it came from, so a deleted entry can take its
  /// proposed moments with it.
  final String? sourceRef;
  final DateTime? updatedAt;
  final int schemaVersion;

  bool get isConfirmed => state == MomentState.confirmed;

  MemoryMoment copyWith({
    String? text,
    MomentState? state,
    MomentTone? tone,
    bool? editedByUser,
    DateTime? updatedAt,
  }) {
    return MemoryMoment(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt,
      occurredOn: occurredOn,
      source: source,
      state: state ?? this.state,
      tone: tone ?? this.tone,
      moodWord: moodWord,
      emotionClass: emotionClass,
      emotionConfidence: emotionConfidence,
      editedByUser: editedByUser ?? this.editedByUser,
      sourceRef: sourceRef,
      updatedAt: updatedAt ?? this.updatedAt,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'occurredOn': occurredOn,
    'source': source.name,
    'state': state.name,
    'tone': tone.name,
    'moodWord': moodWord,
    'emotionClass': emotionClass,
    'emotionConfidence': emotionConfidence,
    'editedByUser': editedByUser,
    'sourceRef': sourceRef,
    'updatedAt': updatedAt?.toIso8601String(),
    'schemaVersion': schemaVersion,
  };

  /// Reads a stored moment, or null if it is unusable. An unreadable state reads
  /// as pending, so a damaged record can never become something Sol is told.
  static MemoryMoment? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    final createdAt = DateTime.tryParse(raw['createdAt'] as String? ?? '');
    final occurredOn = raw['occurredOn'];
    if (id is! String || id.isEmpty) return null;
    if (text is! String || text.trim().isEmpty) return null;
    if (createdAt == null || occurredOn is! String) return null;
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    return MemoryMoment(
      id: id,
      text: text,
      createdAt: createdAt,
      occurredOn: occurredOn,
      source: pick(MomentSource.values, raw['source'], MomentSource.manual),
      state: pick(MomentState.values, raw['state'], MomentState.pending),
      tone: pick(MomentTone.values, raw['tone'], MomentTone.neutral),
      moodWord: raw['moodWord'] as String?,
      emotionClass: raw['emotionClass'] as String?,
      emotionConfidence: (raw['emotionConfidence'] as num?)?.toDouble(),
      editedByUser: raw['editedByUser'] == true,
      sourceRef: raw['sourceRef'] as String?,
      updatedAt: DateTime.tryParse(raw['updatedAt'] as String? ?? ''),
      schemaVersion: (raw['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
    );
  }
}

/// That a moment existed and was deleted, without what it said. Kept so an
/// export and a sync can agree a thing is gone.
class MomentTombstone {
  const MomentTombstone({required this.id, required this.deletedAt});

  final String id;
  final DateTime deletedAt;

  Map<String, Object?> toMap() => {'id': id, 'deletedAt': deletedAt.toIso8601String()};

  static MomentTombstone? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final at = DateTime.tryParse(raw['deletedAt'] as String? ?? '');
    if (id is! String || at == null) return null;
    return MomentTombstone(id: id, deletedAt: at);
  }
}
