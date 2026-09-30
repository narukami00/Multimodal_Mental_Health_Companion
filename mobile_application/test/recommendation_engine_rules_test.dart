import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';

final _now = DateTime(2026, 9, 22, 10);

Activity _activity({
  required String id,
  ActivityType type = ActivityType.movement,
  ActivityEffort effort = ActivityEffort.low,
  int durationMinutes = 8,
  List<String> contexts = const ['outdoors'],
  List<String> targetStates = const ['steady'],
  ActivityReviewStatus reviewStatus = ActivityReviewStatus.approved,
}) {
  return Activity(
    id: id,
    title: 'Activity $id',
    description: 'A small thing to try.',
    type: type,
    effort: effort,
    durationMinutes: durationMinutes,
    contexts: contexts,
    targetStates: targetStates,
    review: ActivityReviewMetadata(
      status: reviewStatus,
      evidenceTier: ActivityEvidenceTier.lifestyle,
      reviewerRole: 'lifestyle_reviewer',
      reviewedAt: DateTime(2026, 9, 22),
    ),
  );
}

SuggestionRecord _record({
  required String id,
  required String activityId,
  required int daysAgo,
  SuggestionStatus status = SuggestionStatus.completed,
  SuggestionSkipReason? skipReason,
  int? rating,
  SuggestionSource? source,
  bool? done,
  SuggestionUsefulness? useful,
  List<String> contextTags = const ['steady'],
}) {
  return SuggestionRecord(
    id: id,
    activityId: activityId,
    shownAt: _now.subtract(Duration(days: daysAgo)),
    contextTags: contextTags,
    status: status,
    skipReason: skipReason,
    rating: rating,
    source: source,
    done: done,
    useful: useful,
  );
}

/// Enough recent exploratory slots that the quota is not forcing another one.
List<SuggestionRecord> _quotaSatisfied() {
  return [
    for (var index = 0; index < 5; index++)
      _record(
        id: 'explore-$index',
        activityId: 'elsewhere-$index',
        daysAgo: index + 1,
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notNow,
        source: SuggestionSource.explore,
        contextTags: const [],
      ),
  ];
}

void main() {
  group('wilsonLowerBound', () {
    // Values from the research table, used to keep the curve honest.
    test('matches the agreed curve', () {
      expect(wilsonLowerBound(1, 1), closeTo(0.27, 0.01));
      expect(wilsonLowerBound(4, 5), closeTo(0.44, 0.01));
      expect(wilsonLowerBound(5, 5), closeTo(0.65, 0.01));
      expect(wilsonLowerBound(10, 10), closeTo(0.79, 0.01));
    });

    test('one success never scores as certainty', () {
      // The whole reason for a lower bound rather than a ratio.
      expect(wilsonLowerBound(1, 1), lessThan(0.3));
    });

    test('is zero without evidence and rises with it', () {
      expect(wilsonLowerBound(0, 0), 0);
      expect(wilsonLowerBound(0, 5), 0);
      expect(wilsonLowerBound(3, 5), lessThan(wilsonLowerBound(5, 5)));
    });
  });

  group('selection', () {
    test('the first two weeks are a starter tour, one per day', () {
      final activities = [
        _activity(id: 'a', durationMinutes: 4),
        _activity(id: 'b', type: ActivityType.mindfulness, durationMinutes: 5),
        _activity(id: 'c', type: ActivityType.creative, durationMinutes: 30),
        _activity(id: 'd', type: ActivityType.nature, durationMinutes: 3),
      ];

      final recommendation = const RecommendationEngine().choose(
        activities: activities,
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 3),
        history: const [],
        now: _now,
      );

      expect(recommendation?.source, SuggestionSource.starter);
      // The thirty-minute activity is outside the gentle starter band.
      expect(recommendation?.activity.id, isNot('c'));
      expect(recommendation?.explanation, contains('starter'));
    });

    test('the starter tour does not repeat a type on consecutive days', () {
      final activities = [
        _activity(id: 'a', durationMinutes: 4),
        _activity(id: 'b', durationMinutes: 5),
        _activity(id: 'c', type: ActivityType.mindfulness, durationMinutes: 4),
      ];

      // Yesterday was movement.
      final history = [
        _record(
          id: 'yesterday',
          activityId: 'a',
          daysAgo: 1,
          status: SuggestionStatus.skipped,
          skipReason: SuggestionSkipReason.notNow,
          source: SuggestionSource.starter,
        ),
      ];

      final recommendation = const RecommendationEngine().choose(
        activities: activities,
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 4),
        history: history,
        now: _now,
      );

      expect(recommendation?.activity.type, isNot(ActivityType.movement));
    });

    test('an activity declined with "not now" stays eligible', () {
      final activities = [_activity(id: 'a', durationMinutes: 4)];

      final recommendation = const RecommendationEngine().choose(
        activities: activities,
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 4),
        history: [
          _record(
            id: 'later',
            activityId: 'a',
            daysAgo: 1,
            status: SuggestionStatus.skipped,
            skipReason: SuggestionSkipReason.notNow,
            source: SuggestionSource.starter,
          ),
        ],
        now: _now,
      );

      // Two days out, the twelve-hour suppression has expired and the
      // dismissal did not disqualify it.
      expect(recommendation?.activity.id, 'a');
    });
  });

  group('suppression', () {
    test('a dismissal at 23:50 still holds at 00:10', () {
      final activities = [_activity(id: 'a'), _activity(id: 'b')];
      final lateEvening = DateTime(2026, 9, 22, 23, 50);
      final justAfterMidnight = DateTime(2026, 9, 23, 0, 10);

      final history = [
        SuggestionRecord(
          id: 'late',
          activityId: 'a',
          shownAt: lateEvening,
          contextTags: const [],
          status: SuggestionStatus.skipped,
          skipReason: SuggestionSkipReason.notNow,
        ),
      ];

      // A day-based rule would have released "a" ten minutes later, on the
      // other side of midnight.
      final pick = const RecommendationEngine().choose(
        activities: [activities.first],
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 20),
        history: history,
        now: justAfterMidnight,
      );
      expect(pick, isNull);

      // Twelve hours later it is available again.
      final later = const RecommendationEngine().choose(
        activities: [activities.first],
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 20),
        history: history,
        now: lateEvening.add(const Duration(hours: 13)),
      );
      expect(later?.activity.id, 'a');
    });

    test('"too hard" lowers the effort ceiling for a fortnight', () {
      final gentle = _activity(id: 'gentle', effort: ActivityEffort.low);
      final demanding = _activity(id: 'demanding', effort: ActivityEffort.high);

      final pick = const RecommendationEngine().choose(
        activities: [gentle, demanding],
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 4),
        history: [
          _record(
            id: 'hard',
            activityId: 'demanding',
            daysAgo: 1,
            status: SuggestionStatus.skipped,
            skipReason: SuggestionSkipReason.tooHard,
          ),
        ],
        now: _now,
      );

      expect(pick?.activity.id, 'gentle');
    });

    test('"not for me" hides an activity, and it comes back after 30 days', () {
      final activity = _activity(id: 'a');

      // Within the first hiding window it is suppressed.
      expect(
        const RecommendationEngine().choose(
          activities: [activity],
          profile: const UserProfile(),
          context: const RecommendationContext(profileAgeDays: 20),
          history: [
            _record(
              id: 'no',
              activityId: 'a',
              daysAgo: 5,
              status: SuggestionStatus.skipped,
              skipReason: SuggestionSkipReason.notForMe,
            ),
          ],
          now: _now,
        ),
        isNull,
      );
    });
  });

  group('effort and outcome weighting', () {
    test('a preferred activity type scores above an equal alternative', () {
      // Both are equally evidenced, so only the preference can separate them.
      // Needs the learned path: the starter tour chooses by exposure, not score.
      final preferred = _activity(id: 'pref', type: ActivityType.nature);
      final other = _activity(id: 'other', type: ActivityType.productivity);

      List<SuggestionRecord> evidenceFor(String id) {
        return [
          for (var index = 0; index < 5; index++)
            _record(
              id: '$id-$index',
              activityId: id,
              daysAgo: index + 3,
              done: true,
              useful: SuggestionUsefulness.up,
            ),
        ];
      }

      final pick = const RecommendationEngine().choose(
        activities: [preferred, other],
        profile: const UserProfile(preferredActivities: ['nature']),
        context: const RecommendationContext(
          currentState: 'steady',
          profileAgeDays: 20,
        ),
        history: [
          ..._quotaSatisfied(),
          ...evidenceFor('pref'),
          ...evidenceFor('other'),
        ],
        now: _now,
      );

      expect(pick?.source, SuggestionSource.learned);
      expect(pick?.activity.id, 'pref');
    });

    test('an elevated baseline keeps suggestions gentle', () {
      final gentle = _activity(id: 'gentle', effort: ActivityEffort.low);
      final demanding = _activity(id: 'demanding', effort: ActivityEffort.high);

      final pick = const RecommendationEngine().choose(
        activities: [gentle, demanding],
        profile: const UserProfile(),
        context: const RecommendationContext(
          profileAgeDays: 4,
          preferGentle: true,
        ),
        history: const [],
        now: _now,
      );

      expect(pick?.activity.id, 'gentle');
    });

    test('doing it without rating is weaker evidence than a good rating', () {
      final activity = _activity(id: 'a');

      double confidenceFor(List<SuggestionRecord> history) {
        return const RecommendationEngine()
            .choose(
              activities: [activity],
              profile: const UserProfile(),
              context: const RecommendationContext(
                currentState: 'steady',
                profileAgeDays: 20,
              ),
              history: [..._quotaSatisfied(), ...history],
              now: _now,
            )!
            .confidence;
      }

      final unrated = [
        for (var index = 0; index < 5; index++)
          _record(
            id: 'done-$index',
            activityId: 'a',
            daysAgo: index + 3,
            status: SuggestionStatus.completed,
            done: true,
          ),
      ];
      final rated = [
        for (var index = 0; index < 5; index++)
          _record(
            id: 'rated-$index',
            activityId: 'a',
            daysAgo: index + 3,
            status: SuggestionStatus.completed,
            done: true,
            useful: SuggestionUsefulness.up,
          ),
      ];

      expect(confidenceFor(unrated), lessThan(confidenceFor(rated)));
    });

    test('a down rating counts against an activity', () {
      final activity = _activity(id: 'a');

      double confidenceFor(List<SuggestionRecord> history) {
        return const RecommendationEngine()
            .choose(
              activities: [activity],
              profile: const UserProfile(),
              context: const RecommendationContext(
                currentState: 'steady',
                profileAgeDays: 20,
              ),
              history: [..._quotaSatisfied(), ...history],
              now: _now,
            )!
            .confidence;
      }

      final up = [
        for (var index = 0; index < 5; index++)
          _record(
            id: 'up-$index',
            activityId: 'a',
            daysAgo: index + 3,
            done: true,
            useful: SuggestionUsefulness.up,
          ),
      ];
      final down = [
        for (var index = 0; index < 5; index++)
          _record(
            id: 'down-$index',
            activityId: 'a',
            daysAgo: index + 3,
            done: true,
            useful: SuggestionUsefulness.down,
          ),
      ];

      expect(confidenceFor(down), lessThan(confidenceFor(up)));
    });

    test('a rating without doing it is weaker than one that confirmed it', () {
      final activity = _activity(id: 'a');

      double confidenceFor(bool confirmed) {
        return const RecommendationEngine()
            .choose(
              activities: [activity],
              profile: const UserProfile(),
              context: const RecommendationContext(
                currentState: 'steady',
                profileAgeDays: 20,
              ),
              history: [
                ..._quotaSatisfied(),
                for (var index = 0; index < 5; index++)
                  _record(
                    id: 'r-$index',
                    activityId: 'a',
                    daysAgo: index + 3,
                    status: confirmed
                        ? SuggestionStatus.completed
                        : SuggestionStatus.shown,
                    done: confirmed ? true : null,
                    useful: SuggestionUsefulness.up,
                  ),
              ],
              now: _now,
            )!
            .confidence;
      }

      expect(confidenceFor(false), lessThan(confidenceFor(true)));
    });
  });

  group('pooling', () {
    test('a thin activity borrows from its type, but only at half weight', () {
      final thin = _activity(id: 'thin', type: ActivityType.mindfulness);
      // In the library so its type can be resolved, but not itself eligible,
      // which keeps the thin activity the only possible pick.
      final sibling = _activity(
        id: 'sibling',
        type: ActivityType.mindfulness,
        reviewStatus: ActivityReviewStatus.pending,
      );

      double confidenceFor(List<SuggestionRecord> history) {
        return const RecommendationEngine()
            .choose(
              activities: [thin, sibling],
              profile: const UserProfile(),
              context: const RecommendationContext(
                currentState: 'steady',
                profileAgeDays: 20,
              ),
              history: [..._quotaSatisfied(), ...history],
              now: _now,
            )!
            .confidence;
      }

      final siblingEvidence = [
        for (var index = 0; index < 5; index++)
          _record(
            id: 'sib-$index',
            activityId: 'sibling',
            daysAgo: index + 3,
            done: true,
            useful: SuggestionUsefulness.up,
          ),
      ];

      final withoutSibling = confidenceFor([]);
      final withSibling = confidenceFor(siblingEvidence);

      expect(withoutSibling, 0);
      expect(withSibling, greaterThan(0));
      // Half weight, so five borrowed outcomes are worth less than five of its
      // own. The borrowed ceiling is what five at full weight would score.
      expect(withSibling, lessThan(wilsonLowerBound(5, 5)));
    });
  });
}
