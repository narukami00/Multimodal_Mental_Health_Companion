import '../../core/constants/moods.dart';
import '../../core/models/session_record.dart';

/// How far back a check-in can be and still stand for "how they felt before".
///
/// A mood from three days ago says nothing about the moment an idea was
/// offered, so an older one is treated as not knowing.
const moodBeforeWindow = Duration(hours: 12);

/// The mood word from the latest check-in made at or before [shownAt] and
/// within [window] of it, or null if there is none.
///
/// Only check-ins that carry a recognised mood word count, so a check-in with
/// text and no mood does not stand in for one.
String? moodBeforeFor({
  required DateTime shownAt,
  required List<SessionRecord> sessions,
  Duration window = moodBeforeWindow,
}) {
  SessionRecord? best;
  for (final session in sessions) {
    if (session.createdAt.isAfter(shownAt)) continue;
    if (shownAt.difference(session.createdAt) > window) continue;
    if (Moods.score(session.mood) == null) continue;
    if (best == null || session.createdAt.isAfter(best.createdAt)) {
      best = session;
    }
  }
  return best?.mood?.trim();
}

/// The change from [before] to [after], from -2 to 2, or null if either is
/// missing or unrecognised.
///
/// The mood words are an ordering, not a scale, so this is a direction with a
/// rough size. It is an outcome signal for the recommender and is never shown
/// to the user as a number.
double? moodChange(String? before, String? after) {
  final from = Moods.score(before);
  final to = Moods.score(after);
  if (from == null || to == null) return null;
  return to - from;
}
