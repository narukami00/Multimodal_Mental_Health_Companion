import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';

void main() {
  test('done and useful survive a round trip independently', () {
    final record = SuggestionRecord(
      id: 'a',
      activityId: 'movement-001',
      shownAt: DateTime(2026, 9, 22, 10),
      contextTags: const ['work'],
      status: SuggestionStatus.completed,
      source: SuggestionSource.learned,
      done: true,
      useful: SuggestionUsefulness.up,
    );

    final restored = SuggestionRecord.fromMap(record.toMap());

    expect(restored.done, isTrue);
    expect(restored.useful, SuggestionUsefulness.up);
    expect(restored.source, SuggestionSource.learned);
    expect(restored.status, SuggestionStatus.completed);
  });

  test('rating without doing it is stored, and is not a completion', () {
    final record = SuggestionRecord(
      id: 'a',
      activityId: 'movement-001',
      shownAt: DateTime(2026, 9, 22, 10),
      contextTags: const [],
      rating: 5,
      useful: SuggestionUsefulness.up,
    );

    final restored = SuggestionRecord.fromMap(record.toMap());

    expect(restored.done, isNull);
    expect(restored.status, SuggestionStatus.shown);
    expect(restored.useful, SuggestionUsefulness.up);
  });

  test('records written before these fields existed still load', () {
    // The exact shape an older build would have written.
    final restored = SuggestionRecord.fromMap({
      'id': 'legacy',
      'activityId': 'movement-001',
      'shownAt': '2026-09-22T10:00:00.000',
      'contextTags': ['work'],
      'status': 'completed',
      'rating': 5,
      'skipReason': null,
      'comment': null,
    });

    expect(restored.id, 'legacy');
    expect(restored.status, SuggestionStatus.completed);
    expect(restored.rating, 5);
    // No source is invented for it.
    expect(restored.source, isNull);
    expect(restored.done, isNull);
    expect(restored.useful, isNull);
  });

  test('an unrecognised source reads as unsourced rather than throwing', () {
    final restored = SuggestionRecord.fromMap({
      'id': 'x',
      'activityId': 'y',
      'shownAt': '2026-09-22T10:00:00.000',
      'contextTags': <String>[],
      'status': 'shown',
      'source': 'something-from-the-future',
      'useful': 'sideways',
    });

    expect(restored.source, isNull);
    expect(restored.useful, isNull);
  });

  test('the proactive flag survives a round trip', () {
    final record = SuggestionRecord(
      id: 'a',
      activityId: 'movement-001',
      shownAt: DateTime(2026, 9, 22, 10),
      contextTags: const [],
      proactive: true,
    );

    expect(SuggestionRecord.fromMap(record.toMap()).proactive, isTrue);
  });

  test('a record with no proactive flag is not treated as a nudge', () {
    // An older record must never silently consume today's nudge budget.
    final restored = SuggestionRecord.fromMap({
      'id': 'legacy',
      'activityId': 'movement-001',
      'shownAt': '2026-09-22T10:00:00.000',
      'contextTags': <String>[],
      'status': 'shown',
    });

    expect(restored.proactive, isFalse);
  });
}
