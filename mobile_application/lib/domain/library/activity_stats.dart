import '../../core/constants/moods.dart';
import '../../core/models/suggestion_record.dart';
import '../recommendations/mood_change.dart';

/// What the person's own history says about one activity: how often it was offered, done or turned
/// down, how they rated it, and how they said they felt afterwards. Only what they reported; nothing
/// here says an idea caused a feeling.
class ActivityStats {
  const ActivityStats({
    this.offered = 0,
    this.done = 0,
    this.skipped = 0,
    this.ratedCount = 0,
    this.averageRating,
    this.lighter = 0,
    this.same = 0,
    this.heavier = 0,
    this.lastDone,
    this.feltAfter = const {},
  });

  final int offered;
  final int done;
  final int skipped;
  final int ratedCount;

  /// 1..5, over the records that have a rating; null when none do.
  final double? averageRating;

  /// Of the times they did it and gave both mood words: lighter, about the same, heavier afterwards.
  final int lighter;
  final int same;
  final int heavier;
  final DateTime? lastDone;

  /// Mood word (internal Steady/Bright/...) -> times chosen after doing it.
  final Map<String, int> feltAfter;

  bool get tried => done > 0;
  int get compared => lighter + same + heavier;

  static const empty = ActivityStats();

  /// One entry per activity id that appears in [history].
  static Map<String, ActivityStats> byActivity(List<SuggestionRecord> history) {
    final groups = <String, List<SuggestionRecord>>{};
    for (final r in history) {
      groups.putIfAbsent(r.activityId, () => []).add(r);
    }
    return {for (final e in groups.entries) e.key: _of(e.value)};
  }

  static ActivityStats _of(List<SuggestionRecord> records) {
    var done = 0, skipped = 0, rated = 0, ratingSum = 0, lighter = 0, same = 0, heavier = 0;
    DateTime? last;
    final felt = <String, int>{};
    for (final r in records) {
      if (r.status == SuggestionStatus.skipped) skipped++;
      if (r.done == true) {
        done++;
        if (last == null || r.shownAt.isAfter(last)) last = r.shownAt;
        final change = moodChange(r.moodBefore, r.moodAfter);
        if (change != null) {
          if (change >= 0.5) {
            lighter++;
          } else if (change <= -0.5) {
            heavier++;
          } else {
            same++;
          }
        }
        final after = r.moodAfter?.trim().toLowerCase();
        for (final word in Moods.values) {
          if (word.toLowerCase() == after) felt[word] = (felt[word] ?? 0) + 1;
        }
      }
      final stars = r.rating;
      if (stars != null && stars > 0) {
        rated++;
        ratingSum += stars;
      }
    }
    return ActivityStats(
      offered: records.length,
      done: done,
      skipped: skipped,
      ratedCount: rated,
      averageRating: rated == 0 ? null : ratingSum / rated,
      lighter: lighter,
      same: same,
      heavier: heavier,
      lastDone: last,
      feltAfter: felt,
    );
  }
}
