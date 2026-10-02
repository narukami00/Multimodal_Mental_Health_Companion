import '../../core/day_key.dart';
import '../../core/models/session_record.dart';
import '../recommendations/event_tagging.dart';
import 'pattern_features.dart';
import 'trend_break_detector.dart';

/// What was going on around a shift, as far as the person has already said.
///
/// Only their own words are read: the themes they wrote about in check-ins
/// around the time. Nothing is inferred about *why* and nothing is claimed: this
/// is material for asking, "anything going on?", never an answer.
class BreakContext {
  const BreakContext({
    required this.shift,
    required this.nearbyThemes,
    required this.moodShifted,
  });

  final TrendBreak shift;

  /// Themes (work, sleep and so on) found in check-ins from just before the shift
  /// to its latest day, most often mentioned first.
  final List<String> nearbyThemes;

  /// Whether their own mood word moved along with the phone.
  final bool moodShifted;

  bool get hasNearbyContext => nearbyThemes.isNotEmpty;

  /// The choices to offer when asking: themes already in their own words first,
  /// then the rest of the themes the app knows, each once.
  List<String> get promptThemes => [
    ...nearbyThemes,
    for (final theme in EventTaggingService.knownThemes)
      if (!nearbyThemes.contains(theme)) theme,
  ];
}

/// Joins a shift to the themes in check-ins around it.
///
/// [daysBefore] reaches a little before the shift began, since a reason usually
/// comes just ahead of it.
BreakContext linkBreakContext({
  required TrendBreak shift,
  required List<SessionRecord> sessions,
  int daysBefore = 1,
  EventTaggingService tagger = const EventTaggingService(),
}) {
  final from = dayKey(
    DateTime(
      shift.startDay.year,
      shift.startDay.month,
      shift.startDay.day - daysBefore,
    ),
  );
  final to = dayKey(shift.latestDay);

  final counts = <String, int>{};
  for (final session in sessions) {
    final key = dayKey(session.createdAt);
    if (key.compareTo(from) < 0 || key.compareTo(to) > 0) continue;
    final text = session.text?.trim();
    if (text == null || text.isEmpty) continue;
    for (final tag in tagger.extractKnownTags(text)) {
      counts[tag.canonicalLabel] = (counts[tag.canonicalLabel] ?? 0) + 1;
    }
  }

  final themes = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  return BreakContext(
    shift: shift,
    nearbyThemes: themes,
    moodShifted: shift.families.contains(PatternFamily.mood),
  );
}
