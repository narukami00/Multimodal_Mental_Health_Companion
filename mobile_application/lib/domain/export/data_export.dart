import '../../core/models/break_annotation.dart';
import '../../core/models/consent.dart';
import '../../core/models/daily_features.dart';
import '../../core/models/memory_moment.dart';
import '../../core/models/session_record.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/research/ablations.dart';

/// Who an export is for, and so what it may carry.
///
/// [person] is everything the person made, in their own words, for them to keep.
/// [research] is the same structure with everything free-text and anything that
/// names an app removed, for analysis under a pseudonymous id. A clinician
/// report is a third, later view built from the same pieces.
enum ExportScope { person, research }

/// Everything an export is made from, already loaded.
class ExportSources {
  const ExportSources({
    required this.consent,
    this.dailyFeatures = const [],
    this.sessions = const [],
    this.suggestions = const [],
    this.moments = const [],
    this.momentTombstones = const [],
    this.breakAnnotations = const [],
  });

  final ConsentLedger consent;
  final List<DailyFeatures> dailyFeatures;
  final List<SessionRecord> sessions;
  final List<SuggestionRecord> suggestions;
  final List<MemoryMoment> moments;
  final List<MomentTombstone> momentTombstones;
  final List<BreakAnnotation> breakAnnotations;
}

/// The version of the export's shape. Bumped when a field is renamed or removed,
/// so an analysis can refuse a file it does not understand.
const exportSchemaVersion = 1;

/// Builds a versioned, deterministic export.
///
/// Pure: the same sources always give the same result, in a fixed order, so two
/// exports can be compared and a study can be reproduced. Rules that hold for
/// every scope:
/// - Phone-derived values appear only while phone patterns consent is granted.
///   Without it, stored days carry only what was made inside Solace.
/// - What a model inferred is kept apart and named (`emotionResults`,
///   `emotionClass`), never mixed into what the person said.
/// - Deleted moments appear only as ids and times, never their words.
/// - The arm of a study ([Ablations.label]) is stamped on, so a file always says
///   what the app was doing when it was made.
///
/// For [ExportScope.research] there is no free text anywhere (check-in text,
/// suggestion comments, moment text), no names of apps, and no way back to a
/// person except [participantId], which the caller makes up.
Map<String, Object?> buildDataExport({
  required ExportSources sources,
  required ExportScope scope,
  required String participantId,
  required DateTime exportedAt,
  Ablations? arm,
}) {
  final research = scope == ExportScope.research;
  final phoneAllowed = sources.consent.isGranted(ConsentKey.usageFootprint);

  final days = <Map<String, Object?>>[
    for (final row in [...sources.dailyFeatures]..sort((a, b) => a.dayKey.compareTo(b.dayKey)))
      _day(row, phoneAllowed: phoneAllowed, research: research),
  ];

  final checkIns = <Map<String, Object?>>[
    for (final s in [...sources.sessions]..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
      {
        'id': s.id,
        'createdAt': s.createdAt.toIso8601String(),
        'mode': s.mode.name,
        'mood': s.mood,
        'wordCount': _words(s.text),
        if (!research) 'text': s.text,
        'emotionResults': [for (final r in s.emotionResults) r.toMap()],
      },
  ];

  final suggestions = <Map<String, Object?>>[
    for (final r in [...sources.suggestions]..sort((a, b) => a.shownAt.compareTo(b.shownAt)))
      _suggestion(r, research: research),
  ];

  final moments = <Map<String, Object?>>[
    for (final m in [...sources.moments]..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
      {
        'id': m.id,
        'createdAt': m.createdAt.toIso8601String(),
        'occurredOn': m.occurredOn,
        'source': m.source.name,
        'state': m.state.name,
        'tone': m.tone.name,
        'moodWord': m.moodWord,
        'emotionClass': m.emotionClass,
        'emotionConfidence': m.emotionConfidence,
        'editedByUser': m.editedByUser,
        'wordCount': _words(m.text),
        if (!research) 'text': m.text,
      },
  ];

  final tombstones = <Map<String, Object?>>[
    for (final t in [...sources.momentTombstones]..sort((a, b) => a.deletedAt.compareTo(b.deletedAt)))
      t.toMap(),
  ];

  final shifts = <Map<String, Object?>>[
    for (final a in [...sources.breakAnnotations]..sort((a, b) => a.shownAt.compareTo(b.shownAt)))
      a.toMap(),
  ];

  return {
    'schemaVersion': exportSchemaVersion,
    'scope': scope.name,
    'participantId': participantId,
    'exportedAt': exportedAt.toIso8601String(),
    'arm': (arm ?? Ablations.current).label,
    'consentEvents': [for (final e in sources.consent.events) e.toMap()],
    'phoneSignalsIncluded': phoneAllowed,
    'dailyFeatures': days,
    'checkIns': checkIns,
    'suggestions': suggestions,
    'moments': moments,
    'momentTombstones': tombstones,
    'shiftAnswers': shifts,
  };
}

Map<String, Object?> _day(
  DailyFeatures row, {
  required bool phoneAllowed,
  required bool research,
}) {
  var shaped = row;
  if (!phoneAllowed && row.hasUsage) shaped = shaped.withoutUsage();
  if (research) shaped = shaped.withoutAppNames();
  return shaped.toMap();
}

Map<String, Object?> _suggestion(SuggestionRecord r, {required bool research}) {
  final map = Map<String, Object?>.of(r.toMap());
  // The free-text comment is the only part of a suggestion in someone's words.
  if (research) map.remove('comment');
  return map;
}

int _words(String? text) {
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
}
