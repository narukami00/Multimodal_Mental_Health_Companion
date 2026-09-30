import '../../core/models/suggestion_record.dart';

/// One activity the user has actually rated.
class HelpedEntry {
  const HelpedEntry({
    required this.activityId,
    required this.ratedCount,
    required this.meanRating,
  });

  final String activityId;

  /// How many rated outcomes this is based on.
  final int ratedCount;

  final double meanRating;
}

/// Activities the user rated, using only their own ratings.
///
/// Deliberately narrow, because the risk here is a thin pattern read as a
/// prescription:
/// - only completed suggestions that the user actually rated are counted, so a
///   rating is never invented;
/// - suggestions that were merely shown, and then abandoned, are excluded;
/// - anything below [minOutcomes] is hidden rather than shown with a caveat.
List<HelpedEntry> whatHasHelped(
  List<SuggestionRecord> records, {
  int minOutcomes = 3,
}) {
  final totals = <String, ({int count, int sum})>{};
  for (final record in records) {
    if (record.status != SuggestionStatus.completed) continue;
    final rating = record.rating;
    if (rating == null) continue;

    final existing = totals[record.activityId];
    totals[record.activityId] = (
      count: (existing?.count ?? 0) + 1,
      sum: (existing?.sum ?? 0) + rating,
    );
  }

  final entries = <HelpedEntry>[
    for (final entry in totals.entries)
      if (entry.value.count >= minOutcomes)
        HelpedEntry(
          activityId: entry.key,
          ratedCount: entry.value.count,
          meanRating: entry.value.sum / entry.value.count,
        ),
  ];

  // Most-tried first, so the list leads with what the user has actually used.
  entries.sort((a, b) => b.ratedCount.compareTo(a.ratedCount));
  return entries;
}
