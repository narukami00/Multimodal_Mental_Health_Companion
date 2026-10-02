import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/insights/mood_insights.dart';
import 'package:solace_mobile/domain/insights/what_helped.dart';

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _now = DateTime(2026, 10, 31, 20);

SessionRecord _s(int back, String? mood, {int hour = 9}) => SessionRecord(
  id: '$back-$mood-$hour',
  createdAt: DateTime(2026, 10, 31 - back, hour),
  mode: CaptureMode.text,
  text: 'x',
  mood: mood,
);

Activity _a(String id, ActivityType type) => Activity(
  id: id,
  title: id,
  description: '',
  type: type,
  effort: ActivityEffort.low,
  durationMinutes: 5,
  contexts: const [],
  targetStates: const [],
  review: ActivityReviewMetadata(
    status: ActivityReviewStatus.approved,
    evidenceTier: ActivityEvidenceTier.lifestyle,
    reviewerRole: 't',
    reviewedAt: DateTime(2026, 1, 1),
  ),
);

SuggestionRecord _r(String id, String activity, String? before, String? after, {bool done = true}) =>
    SuggestionRecord(
      id: id,
      activityId: activity,
      shownAt: DateTime(2026, 10, 30),
      contextTags: const [],
      done: done,
      moodBefore: before,
      moodAfter: after,
    );

void main() {
  group('mood strip', () {
    test('is exactly the asked-for days, oldest first, gaps left empty', () {
      final strip = moodStrip([_s(0, 'Bright'), _s(2, 'Wobbly')], _now);
      expect(strip.length, 30);
      expect(strip.last.mood, 'Bright');
      expect(strip[27].mood, 'Wobbly');
      expect(strip[28].mood, isNull);
      expect(strip.first.day, DateTime(2026, 10, 2));
    });

    test('the most frequent word wins a day, the latest breaks a tie', () {
      final strip = moodStrip(
        [_s(0, 'Quiet', hour: 8), _s(0, 'Bright', hour: 9), _s(0, 'Bright', hour: 10), _s(1, 'Quiet', hour: 8), _s(1, 'Tender', hour: 18)],
        _now,
      );
      expect(strip.last.mood, 'Bright');
      expect(strip[28].mood, 'Tender');
    });

    test('check-ins without a mood word do not count', () {
      expect(moodStripSummary(moodStrip([_s(0, null), _s(1, 'Nope')], _now)), isNull);
    });

    test('summary is plain and descriptive', () {
      final text = moodStripSummary(
        moodStrip([_s(0, 'Steady'), _s(1, 'Steady'), _s(2, 'Bright')], _now),
      )!;
      expect(text, 'You checked in on 3 of the last 30 days. Steady came up most, on 2.');
    });
  });

  group('what helped', () {
    final library = [_a('walk', ActivityType.movement), _a('tea', ActivityType.mindfulness)];

    test('needs three answered tries, and one lighter outcome', () {
      final history = [
        _r('1', 'walk', 'Wobbly', 'Steady'),
        _r('2', 'walk', 'Quiet', 'Bright'),
        _r('3', 'tea', 'Wobbly', 'Steady'),
      ];
      expect(whatHelped(history, library), isEmpty);
    });

    test('says what they reported, with counts', () {
      final history = [
        _r('1', 'walk', 'Wobbly', 'Steady'),
        _r('2', 'walk', 'Quiet', 'Bright'),
        _r('3', 'walk', 'Steady', 'Steady'),
        _r('4', 'walk', 'Tender', 'Bright'),
      ];
      final result = whatHelped(history, library);
      expect(result.single.text, 'After moving your body, you said you felt lighter 3 of 4 times.');
    });

    test('unanswered and not-done records are not counted as no change', () {
      final history = [
        _r('1', 'walk', 'Wobbly', 'Steady'),
        _r('2', 'walk', 'Quiet', 'Bright'),
        _r('3', 'walk', 'Tender', null),
        _r('4', 'walk', null, 'Bright'),
        _r('5', 'walk', 'Wobbly', 'Bright', done: false),
      ];
      expect(whatHelped(history, library), isEmpty);
    });

    test('never judges or claims cause', () {
      final history = [for (var i = 0; i < 4; i++) _r('$i', 'walk', 'Wobbly', 'Bright')];
      final text = whatHelped(history, library).single.text.toLowerCase();
      for (final w in ['because', 'caused', 'works', 'cures', 'should']) {
        expect(text, isNot(contains(w)));
      }
    });
  });

  group('nights and moods', () {
    DailyFeatures night(int back, int startMinute) => DailyFeatures(
      dayKey: _key(DateTime(2026, 10, 31 - back)),
      sources: const {'usage', 'usageFinal'},
      estimatedSleepStartMinute: startMinute,
    );

    test('compares the days after later nights with the days after usual ones', () {
      final rows = <DailyFeatures>[];
      final sessions = <SessionRecord>[];
      for (var back = 2; back <= 21; back++) {
        final late = back.isEven;
        rows.add(night(back, late ? 60 : 23 * 60));
        // The day after the night of day `back` is `back - 1`.
        sessions.add(_s(back - 1, late ? 'Wobbly' : 'Steady'));
      }
      final result = nightsAndMoods(rows, sessions)!;
      expect(result.laterNights, 10);
      expect(result.laterNightsLow, 10);
      expect(result.usualNights, 10);
      expect(result.usualNightsLow, 0);
      expect(result.text, contains('does not mean one caused'));
    });

    test('says nothing without enough days in each group', () {
      final rows = [for (var b = 2; b <= 21; b++) night(b, 23 * 60)];
      final sessions = [for (var b = 1; b <= 20; b++) _s(b, 'Steady')];
      expect(nightsAndMoods(rows, sessions), isNull);
      expect(nightsAndMoods(const [], const []), isNull);
    });
  });
}
