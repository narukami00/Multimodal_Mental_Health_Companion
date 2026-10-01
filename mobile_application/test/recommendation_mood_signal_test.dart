import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';

final _now = DateTime(2026, 10, 1, 12);

Activity _activity() => Activity(
  id: 'walk',
  title: 'A short walk',
  description: 'A small thing to try.',
  type: ActivityType.movement,
  effort: ActivityEffort.low,
  durationMinutes: 10,
  contexts: const [],
  targetStates: const [],
  review: ActivityReviewMetadata(
    status: ActivityReviewStatus.approved,
    evidenceTier: ActivityEvidenceTier.lifestyle,
    reviewerRole: 'test',
    reviewedAt: DateTime(2026, 1, 1),
  ),
);

SuggestionRecord _record({
  SuggestionUsefulness? useful,
  bool done = true,
  String? moodBefore,
  String? moodAfter,
  String id = 'r',
}) => SuggestionRecord(
  id: id,
  activityId: 'walk',
  shownAt: _now.subtract(const Duration(days: 1)),
  contextTags: const ['steady'],
  status: done ? SuggestionStatus.completed : SuggestionStatus.shown,
  done: done ? true : null,
  useful: useful,
  moodBefore: moodBefore,
  moodAfter: moodAfter,
);

({double confidence, double n}) _standing(List<SuggestionRecord> records) {
  final standing = const RecommendationEngine()
      .standingOf(
        activities: [_activity()],
        profile: const UserProfile(),
        context: const RecommendationContext(
          currentState: 'steady',
          profileAgeDays: 30,
        ),
        history: records,
        now: _now,
      )
      .single;
  return (confidence: standing.confidence, n: standing.evidenceN);
}

void main() {
  group('rated ideas: the rating decides, the mood change only nudges', () {
    final baseline = _standing([_record(useful: SuggestionUsefulness.up)]);

    test('no mood information changes nothing', () {
      expect(
        _standing([_record(useful: SuggestionUsefulness.up)]).n,
        baseline.n,
      );
    });

    test('a mood that rose after a thumbs-up is believed a little more', () {
      final result = _standing([
        _record(
          useful: SuggestionUsefulness.up,
          moodBefore: 'Wobbly',
          moodAfter: 'Steady',
        ),
      ]);

      expect(result.n / baseline.n, closeTo(RecommendationEngine.moodAgreesWeight, 1e-9));
      expect(result.confidence, greaterThan(baseline.confidence));
    });

    test('a mood that fell after a thumbs-up is believed a little less', () {
      final result = _standing([
        _record(
          useful: SuggestionUsefulness.up,
          moodBefore: 'Bright',
          moodAfter: 'Tender',
        ),
      ]);

      expect(
        result.n / baseline.n,
        closeTo(RecommendationEngine.moodDisagreesWeight, 1e-9),
      );
      expect(result.confidence, lessThan(baseline.confidence));
      // Still a thumbs-up: the idea is not turned against the person.
      expect(result.confidence, greaterThan(0));
    });

    test('a thumbs-down is never turned into a success by a better mood', () {
      final down = _standing([
        _record(
          useful: SuggestionUsefulness.down,
          moodBefore: 'Wobbly',
          moodAfter: 'Bright',
        ),
      ]);

      // Zero successes, whatever the mood did.
      expect(down.confidence, 0);
    });

    test('a change too small to tell from noise is ignored', () {
      // Steady to Quiet is a quarter step on the ordering.
      final small = _standing([
        _record(
          useful: SuggestionUsefulness.up,
          moodBefore: 'Steady',
          moodAfter: 'Quiet',
        ),
      ]);

      expect(small.n, baseline.n);
      expect(small.confidence, baseline.confidence);
    });

    test('a mood after with no mood before cannot be read as a change', () {
      final result = _standing([
        _record(useful: SuggestionUsefulness.up, moodAfter: 'Bright'),
      ]);

      expect(result.n, baseline.n);
    });
  });

  group('unrated completions: the mood change is the only signal', () {
    final baseline = _standing([_record()]);

    test('a completion with no mood information keeps its neutral value', () {
      expect(_standing([_record()]).confidence, baseline.confidence);
    });

    test('an improvement makes the idea look a little better', () {
      final better = _standing([
        _record(moodBefore: 'Wobbly', moodAfter: 'Bright'),
      ]);

      expect(better.confidence, greaterThan(baseline.confidence));
      // The weight is untouched: only the value moved.
      expect(better.n, baseline.n);
    });

    test('a worse mood makes it look a little worse', () {
      final worse = _standing([
        _record(moodBefore: 'Bright', moodAfter: 'Wobbly'),
      ]);

      expect(worse.confidence, lessThan(baseline.confidence));
      expect(worse.n, baseline.n);
    });

    test('the effect is bounded either side of neutral', () {
      final best = _standing([
        _record(moodBefore: 'Wobbly', moodAfter: 'Bright'),
      ]);
      final worst = _standing([
        _record(moodBefore: 'Bright', moodAfter: 'Wobbly'),
      ]);

      // One unrated completion can never look like a thumbs-up or a thumbs-down.
      final thumbsUp = _standing([_record(useful: SuggestionUsefulness.up)]);
      expect(best.confidence, lessThan(thumbsUp.confidence));
      expect(worst.confidence, greaterThanOrEqualTo(0));
    });

    test('one improvement alone never reaches the learned gate', () {
      final better = _standing([
        _record(moodBefore: 'Wobbly', moodAfter: 'Bright'),
      ]);

      expect(better.confidence, lessThan(RecommendationEngine.confidenceGate));
      expect(better.n, lessThan(RecommendationEngine.evidenceGate));
    });
  });

  test('a mood recorded on something never done counts for nothing', () {
    final notDone = _standing([
      _record(done: false, moodBefore: 'Wobbly', moodAfter: 'Bright'),
    ]);

    expect(notDone.n, 0);
    expect(notDone.confidence, 0);
  });
}
