/// Coarse valence group a class belongs to.
///
/// [unmapped] is what a label the taxonomy does not know resolves to. It is
/// never an error: the model's class set may change before it is final, and a
/// result carrying an unfamiliar label must still be stored and counted.
enum AffectGroup { positive, negative, neutral, unmapped }

/// How activated a class usually is. Optional per class, because the model
/// outputs classes with a confidence and nothing else: no valence or arousal.
enum ArousalBand { low, medium, high }

/// One class the emotion model can output.
class EmotionClass {
  const EmotionClass({
    required this.label,
    required this.affectGroup,
    this.arousalBand,
  });

  /// Stored lower-case and trimmed, so lookups ignore case and padding.
  final String label;
  final AffectGroup affectGroup;
  final ArousalBand? arousalBand;

  Map<String, Object?> toMap() => {
    'label': label,
    'affectGroup': affectGroup.name,
    'arousalBand': arousalBand?.name,
  };
}

/// The set of classes the emotion model outputs, and what each one means to the
/// rest of the app.
///
/// This is the **only** place class names are known. Everything else reads
/// [affectGroupOf] and [arousalBandOf], so changing the class set is a data
/// change here and nowhere else. It round-trips through [toMap]/[fromMap] so it
/// can later be shipped as an asset instead of a constant.
class EmotionTaxonomy {
  const EmotionTaxonomy({required this.version, required this.classes});

  /// Reads a taxonomy from decoded JSON. Malformed entries are skipped rather
  /// than failing the whole file, and the first entry wins for a repeated label.
  factory EmotionTaxonomy.fromMap(Map<String, dynamic> map) {
    final seen = <String>{};
    final classes = <EmotionClass>[];
    for (final entry in map['classes'] as List<dynamic>? ?? const []) {
      if (entry is! Map) continue;
      final label = _normalize(entry['label']);
      if (label == null || !seen.add(label)) continue;
      classes.add(
        EmotionClass(
          label: label,
          affectGroup: _enumByName(
            AffectGroup.values,
            entry['affectGroup'],
            AffectGroup.unmapped,
          ),
          arousalBand: _enumByNameOrNull(ArousalBand.values, entry['arousalBand']),
        ),
      );
    }
    return EmotionTaxonomy(
      version: map['version'] as String? ?? 'unknown',
      classes: List.unmodifiable(classes),
    );
  }

  /// A provisional six-class set, standing in until the model's classes are
  /// final. Deliberately named as a placeholder: nothing may depend on these
  /// labels, only on the mapping interface below.
  static const placeholder = EmotionTaxonomy(
    version: 'placeholder-0',
    classes: [
      EmotionClass(
        label: 'joy',
        affectGroup: AffectGroup.positive,
        arousalBand: ArousalBand.medium,
      ),
      EmotionClass(
        label: 'calm',
        affectGroup: AffectGroup.positive,
        arousalBand: ArousalBand.low,
      ),
      EmotionClass(
        label: 'sadness',
        affectGroup: AffectGroup.negative,
        arousalBand: ArousalBand.low,
      ),
      EmotionClass(
        label: 'anxiety',
        affectGroup: AffectGroup.negative,
        arousalBand: ArousalBand.high,
      ),
      EmotionClass(
        label: 'anger',
        affectGroup: AffectGroup.negative,
        arousalBand: ArousalBand.high,
      ),
      EmotionClass(label: 'neutral', affectGroup: AffectGroup.neutral),
    ],
  );

  final String version;
  final List<EmotionClass> classes;

  List<String> get labels => [for (final c in classes) c.label];

  /// The class for [label], ignoring case and padding, or null if unknown.
  EmotionClass? lookup(String label) {
    final key = _normalize(label);
    if (key == null) return null;
    for (final candidate in classes) {
      if (candidate.label == key) return candidate;
    }
    return null;
  }

  /// [AffectGroup.unmapped] for any label this taxonomy does not know.
  AffectGroup affectGroupOf(String label) =>
      lookup(label)?.affectGroup ?? AffectGroup.unmapped;

  /// Null when the label is unknown or the taxonomy gives it no arousal band.
  ArousalBand? arousalBandOf(String label) => lookup(label)?.arousalBand;

  Map<String, Object?> toMap() => {
    'version': version,
    'classes': [for (final c in classes) c.toMap()],
  };

  static String? _normalize(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  static T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      _enumByNameOrNull(values, name) ?? fallback;

  static T? _enumByNameOrNull<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
