import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/rhythm/what_has_helped.dart';

int _id = 0;

SuggestionRecord _record({
  required String activityId,
  SuggestionStatus status = SuggestionStatus.completed,
  int? rating,
}) {
  _id++;
  return SuggestionRecord(
    id: 'r$_id',
    activityId: activityId,
    shownAt: DateTime(2026, 9, 20),
    contextTags: const [],
    status: status,
    rating: rating,
  );
}

void main() {
  setUp(() => _id = 0);

  test('hides anything below the outcome threshold', () {
    final entries = whatHasHelped([
      _record(activityId: 'walk', rating: 4),
      _record(activityId: 'walk', rating: 4),
    ]);

    expect(entries, isEmpty);
  });

  test('reports the mean of the user ratings once the threshold is met', () {
    final entries = whatHasHelped([
      _record(activityId: 'walk', rating: 4),
      _record(activityId: 'walk', rating: 5),
      _record(activityId: 'walk', rating: 3),
    ]);

    expect(entries.length, 1);
    expect(entries.single.activityId, 'walk');
    expect(entries.single.ratedCount, 3);
    expect(entries.single.meanRating, 4.0);
  });

  test('never invents a rating for an unrated completion', () {
    final entries = whatHasHelped([
      _record(activityId: 'walk', rating: 4),
      _record(activityId: 'walk', rating: 4),
      _record(activityId: 'walk', rating: 3),
      // Completed but the user never rated it: it must not be counted.
      _record(activityId: 'walk'),
    ]);

    expect(entries.single.ratedCount, 3);
  });

  test('ignores skipped and abandoned suggestions', () {
    final entries = whatHasHelped([
      _record(activityId: 'walk', rating: 4),
      _record(activityId: 'walk', rating: 4),
      _record(activityId: 'walk', rating: 4),
      _record(activityId: 'walk', status: SuggestionStatus.shown, rating: 5),
      _record(activityId: 'walk', status: SuggestionStatus.skipped),
    ]);

    expect(entries.single.ratedCount, 3);
  });

  test('groups by activity and leads with the most tried', () {
    final entries = whatHasHelped([
      for (var i = 0; i < 3; i++) _record(activityId: 'walk', rating: 4),
      for (var i = 0; i < 5; i++) _record(activityId: 'breathe', rating: 5),
    ]);

    expect(entries.length, 2);
    expect(entries.first.activityId, 'breathe');
    expect(entries.last.activityId, 'walk');
  });

  test('respects a custom threshold', () {
    final records = [_record(activityId: 'walk', rating: 4)];

    expect(whatHasHelped(records, minOutcomes: 1).length, 1);
    expect(whatHasHelped(records, minOutcomes: 2), isEmpty);
  });
}
