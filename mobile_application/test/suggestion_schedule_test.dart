import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/suggestions/suggestion_schedule.dart';

const _schedule = SuggestionSchedule();
final _now = DateTime(2026, 9, 22, 14);

SuggestionRecord _shown({required DateTime at, String id = 'r'}) {
  return SuggestionRecord(
    id: id,
    activityId: 'a',
    shownAt: at,
    contextTags: const [],
  );
}

void main() {
  test('nothing is due before the day\'s check-in', () {
    // The suggestion is a follow-on from reflecting, not a separate demand.
    expect(
      _schedule.isDue(
        history: const [],
        profileAgeDays: 30,
        checkInCompletedToday: false,
        now: _now,
      ),
      isFalse,
    );
  });

  test('one is due once the check-in is done', () {
    expect(
      _schedule.isDue(
        history: const [],
        profileAgeDays: 30,
        checkInCompletedToday: true,
        now: _now,
      ),
      isTrue,
    );
  });

  test('the first fortnight caps at one a day', () {
    final history = [_shown(at: DateTime(2026, 9, 22, 9))];

    expect(
      _schedule.isDue(
        history: history,
        profileAgeDays: 5,
        checkInCompletedToday: true,
        now: _now,
      ),
      isFalse,
    );
  });

  test('afterwards a second one is allowed, four hours apart', () {
    final history = [_shown(at: DateTime(2026, 9, 22, 9))];

    expect(
      _schedule.isDue(
        history: history,
        profileAgeDays: 30,
        checkInCompletedToday: true,
        now: _now,
      ),
      isTrue,
    );
    // Still inside the minimum gap.
    expect(
      _schedule.isDue(
        history: history,
        profileAgeDays: 30,
        checkInCompletedToday: true,
        now: DateTime(2026, 9, 22, 11),
      ),
      isFalse,
    );
  });

  test('the daily cap holds however long the day is', () {
    final history = [
      _shown(at: DateTime(2026, 9, 22, 9), id: 'a'),
      _shown(at: DateTime(2026, 9, 22, 13), id: 'b'),
    ];

    expect(
      _schedule.isDue(
        history: history,
        profileAgeDays: 30,
        checkInCompletedToday: true,
        now: DateTime(2026, 9, 22, 20),
      ),
      isFalse,
    );
  });

  test('yesterday\'s suggestion does not count against today', () {
    expect(
      _schedule.isDue(
        history: [_shown(at: DateTime(2026, 9, 21, 20))],
        profileAgeDays: 30,
        checkInCompletedToday: true,
        now: _now,
      ),
      isTrue,
    );
  });
}
