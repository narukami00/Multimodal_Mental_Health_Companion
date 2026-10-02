import '../../core/models/break_annotation.dart';
import '../../core/models/session_record.dart';
import 'break_context.dart';
import 'trend_break_detector.dart';

/// A question about a shift, ready to show.
class BreakPrompt {
  const BreakPrompt({required this.context, required this.isNew});

  final BreakContext context;

  /// True the first time it is put in front of the person, which is when it is
  /// recorded as shown and starts counting against the cap.
  final bool isNew;

  String get key => context.shift.key;
}

/// How long a question stays on screen before it quietly goes. Ignoring it is
/// not a decision, so it is never asked again either.
const breakPromptVisibleFor = Duration(hours: 24);

/// The quietest allowed gap between two questions, counted from when the earlier
/// one was shown.
const breakPromptCap = Duration(days: 7);

/// Decides whether to ask about a shift now, and about which.
///
/// Pure. Asking is a nudge, so it is held to the same standards as one:
///
/// - only a shift across families (what [detectTrendBreaks] surfaces);
/// - never while safety support is active, and never when the person has turned
///   these questions off;
/// - one question per shift, ever: answering or declining ends it, and ignoring
///   it lets it expire after [breakPromptVisibleFor];
/// - at most one new question per [breakPromptCap].
BreakPrompt? currentBreakPrompt({
  required TrendBreakReport report,
  required List<SessionRecord> sessions,
  required List<BreakAnnotation> annotations,
  required DateTime now,
  bool muted = false,
  bool safetyActive = false,
}) {
  final shift = report.surfaced;
  if (shift == null || muted || safetyActive) return null;

  BreakAnnotation? existing;
  for (final annotation in annotations) {
    if (annotation.breakKey == shift.key) existing = annotation;
  }

  final context = linkBreakContext(shift: shift, sessions: sessions);

  if (existing != null) {
    // Already decided, or already shown and since expired: never again.
    if (existing.status != BreakAnnotationStatus.shown) return null;
    if (now.difference(existing.shownAt) >= breakPromptVisibleFor) return null;
    return BreakPrompt(context: context, isNew: false);
  }

  final capped = annotations.any(
    (annotation) => now.difference(annotation.shownAt) < breakPromptCap,
  );
  if (capped) return null;

  return BreakPrompt(context: context, isNew: true);
}

/// The themes the person chose in the last [within], to be used as context for
/// what is offered next. Their own words, for a short while, and never inferred.
List<String> recentChosenThemes(
  List<BreakAnnotation> annotations,
  DateTime now, {
  Duration within = const Duration(days: 3),
}) {
  final themes = <String>{};
  for (final annotation in annotations) {
    final decided = annotation.decidedAt;
    final theme = annotation.theme;
    if (annotation.status != BreakAnnotationStatus.answered ||
        decided == null ||
        theme == null) {
      continue;
    }
    if (now.difference(decided) < within) themes.add(theme);
  }
  return themes.toList()..sort();
}
