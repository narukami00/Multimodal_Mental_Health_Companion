import '../../core/constants/moods.dart';
import '../../core/models/session_record.dart';
import '../../core/models/suggestion_record.dart';

/// How far back a check-in can be and still stand for "how they felt before" an idea they went on to do.
///
/// A mood from hours earlier says little about the moment they began, so an older one is treated as not
/// knowing.
const moodBeforeWindow = Duration(hours: 3);

/// How far back a check-in still counts as context for choosing an idea (how the person is doing around
/// now). Wider than [moodBeforeWindow] on purpose: choosing is not a measurement, so this is left as it
/// was before the pairing window was tightened.
const moodContextWindow = Duration(hours: 12);

/// The longest between starting an idea and saying it is done for the before-and-after moods to be read as a
/// pair. Past it the person may have done anything in between, so the pair says nothing about the idea.
const moodPairWindow = Duration(hours: 4);

/// The mood word from the latest check-in made at or before [shownAt] and
/// within [window] of it, or null if there is none.
///
/// Only check-ins that carry a recognised mood word count, so a check-in with
/// text and no mood does not stand in for one. The word is the one the app works
/// with ([SessionRecord.effectiveMood]: what the model read, else the picked word),
/// the same one used to decide whether the check-in counts. Returning the picked word
/// instead lost the "before" for every entry that was read by the model and had no word picked.
String? moodBeforeFor({
  required DateTime shownAt,
  required List<SessionRecord> sessions,
  Duration window = moodBeforeWindow,
}) {
  SessionRecord? best;
  for (final session in sessions) {
    if (session.createdAt.isAfter(shownAt)) continue;
    if (shownAt.difference(session.createdAt) > window) continue;
    if (Moods.score(session.effectiveMood) == null) continue;
    if (best == null || session.createdAt.isAfter(best.createdAt)) {
      best = session;
    }
  }
  return best?.effectiveMood;
}

/// The "before" mood for an idea they did, as of when they began.
///
/// What they said when asked directly wins over what a check-in implies. Otherwise it is the latest check-in
/// within [moodBeforeWindow] of [SuggestionRecord.acceptedAt] (the card's [SuggestionRecord.shownAt] for ideas
/// answered the older one-step way).
String? moodBeforeForRecord({
  required SuggestionRecord record,
  required List<SessionRecord> sessions,
}) {
  final asked = record.moodBefore?.trim();
  if (asked != null && asked.isNotEmpty) return asked;
  return moodBeforeFor(shownAt: record.acceptedAt ?? record.shownAt, sessions: sessions);
}

/// Whether the before-and-after moods of [record] can be read as a pair, given it is being finished at
/// [finishedAt]. Ideas answered the older one-step way have no start time and pair as before.
bool moodsPair(SuggestionRecord record, DateTime finishedAt) {
  final started = record.acceptedAt;
  if (started == null) return true;
  return finishedAt.difference(started) <= moodPairWindow;
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
