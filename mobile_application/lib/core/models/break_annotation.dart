/// Where a "your days looked different, anything going on?" question stands.
enum BreakAnnotationStatus {
  /// It was put in front of them and not yet answered. It quietly expires.
  shown,

  /// They chose a theme, or said nothing in particular.
  answered,

  /// They said not now. Declining is a complete answer.
  dismissed,
}

/// What happened to one question about one shift.
///
/// Kept so the same shift is never asked about twice, so asking is capped, and so
/// a theme the person chose can be used as context. [theme] is null for "nothing
/// in particular", which is an answer and not a gap.
class BreakAnnotation {
  const BreakAnnotation({
    required this.breakKey,
    required this.status,
    required this.shownAt,
    this.decidedAt,
    this.theme,
  });

  final String breakKey;
  final BreakAnnotationStatus status;
  final DateTime shownAt;
  final DateTime? decidedAt;
  final String? theme;

  BreakAnnotation answered({String? theme, required DateTime at}) =>
      BreakAnnotation(
        breakKey: breakKey,
        status: BreakAnnotationStatus.answered,
        shownAt: shownAt,
        decidedAt: at,
        theme: theme,
      );

  BreakAnnotation dismissed({required DateTime at}) => BreakAnnotation(
    breakKey: breakKey,
    status: BreakAnnotationStatus.dismissed,
    shownAt: shownAt,
    decidedAt: at,
  );

  Map<String, Object?> toMap() => {
    'breakKey': breakKey,
    'status': status.name,
    'shownAt': shownAt.toIso8601String(),
    'decidedAt': decidedAt?.toIso8601String(),
    'theme': theme,
  };

  /// Reads a stored annotation, or null if it is unusable. An unreadable status
  /// reads as dismissed, so a damaged record can only ever mean "do not ask".
  static BreakAnnotation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['breakKey'];
    final shownAt = DateTime.tryParse(raw['shownAt'] as String? ?? '');
    if (key is! String || key.isEmpty || shownAt == null) return null;
    return BreakAnnotation(
      breakKey: key,
      status: BreakAnnotationStatus.values.firstWhere(
        (value) => value.name == raw['status'],
        orElse: () => BreakAnnotationStatus.dismissed,
      ),
      shownAt: shownAt,
      decidedAt: DateTime.tryParse(raw['decidedAt'] as String? ?? ''),
      theme: raw['theme'] as String?,
    );
  }
}
