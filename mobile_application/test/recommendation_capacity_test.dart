import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/domain/capacity/capacity_estimator.dart';
import 'package:solace_mobile/domain/capacity/mood_trend.dart';
import 'package:solace_mobile/domain/profile/behavioral_profile.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/suggestions/suggestion_context.dart';

final _now = DateTime(2026, 10, 1, 10);

Activity _activity(
  String id, {
  ActivityType type = ActivityType.social,
  ActivityEffort effort = ActivityEffort.low,
  int minutes = 5,
}) => Activity(
  id: id,
  title: 'Idea $id',
  description: 'A small thing to try.',
  type: type,
  effort: effort,
  durationMinutes: minutes,
  contexts: const [],
  targetStates: const ['steady'],
  review: ActivityReviewMetadata(
    status: ActivityReviewStatus.approved,
    evidenceTier: ActivityEvidenceTier.lifestyle,
    reviewerRole: 'test',
    reviewedAt: DateTime(2026, 1, 1),
  ),
);

Capacity _capacity(CapacityLevel level) => Capacity(
  level: level,
  confidence: 0.8,
  reasons: const [],
  score: switch (level) {
    CapacityLevel.low => -3,
    CapacityLevel.medium => 0,
    CapacityLevel.high => 2,
  },
);

Recommendation? _choose(
  List<Activity> library, {
  Capacity? capacity,
  List<SuggestionRecord> history = const [],
  String? currentState,
}) {
  return const RecommendationEngine().choose(
    activities: library,
    profile: const UserProfile(),
    context: RecommendationContext(
      currentState: currentState,
      profileAgeDays: 30,
      capacity: capacity,
    ),
    history: history,
    now: _now,
  );
}

void main() {
  group('effort', () {
    final onlyMedium = [_activity('m', effort: ActivityEffort.medium)];

    test('with no capacity estimate, nothing changes', () {
      expect(_choose(onlyMedium)?.activity.id, 'm');
    });

    test('low capacity keeps offers at low effort', () {
      expect(_choose(onlyMedium, capacity: _capacity(CapacityLevel.low)), isNull);
    });

    test('medium and high capacity leave effort alone', () {
      for (final level in [CapacityLevel.medium, CapacityLevel.high]) {
        expect(_choose(onlyMedium, capacity: _capacity(level))?.activity.id, 'm');
      }
    });
  });

  group('length', () {
    final library = [
      _activity('a-long', minutes: 20),
      _activity('b-short', minutes: 5),
    ];

    test('with no estimate, the long one is as eligible as any', () {
      expect(_choose(library)?.activity.id, 'a-long');
    });

    test('low capacity trims long ideas', () {
      expect(
        _choose(library, capacity: _capacity(CapacityLevel.low))?.activity.id,
        'b-short',
      );
    });

    test('medium capacity trims only the longest', () {
      expect(
        _choose(library, capacity: _capacity(CapacityLevel.medium))
            ?.activity
            .id,
        'b-short',
      );
      final fifteen = [
        _activity('a-fifteen', minutes: 15),
        _activity('b-short', minutes: 5),
      ];
      expect(
        _choose(fifteen, capacity: _capacity(CapacityLevel.medium))
            ?.activity
            .id,
        'a-fifteen',
      );
    });

    test('high capacity leaves length alone', () {
      expect(
        _choose(library, capacity: _capacity(CapacityLevel.high))?.activity.id,
        'a-long',
      );
    });

    test('the cap is soft: it never leaves the engine with nothing to say', () {
      final onlyLong = [_activity('long', minutes: 25)];

      expect(
        _choose(onlyLong, capacity: _capacity(CapacityLevel.low))?.activity.id,
        'long',
      );
    });
  });

  group('lean towards gentle kinds', () {
    final library = [
      _activity('a-move', type: ActivityType.movement),
      _activity('b-mind', type: ActivityType.mindfulness),
    ];

    test('at low capacity an unfamiliar pick comes from a gentle kind', () {
      expect(_choose(library)?.activity.id, 'a-move');
      expect(
        _choose(library, capacity: _capacity(CapacityLevel.low))?.activity.id,
        'b-mind',
      );
    });

    test('medium and high capacity do not lean', () {
      for (final level in [CapacityLevel.medium, CapacityLevel.high]) {
        expect(_choose(library, capacity: _capacity(level))?.activity.id, 'a-move');
      }
    });

    test('with no gentle kind on offer, it falls back instead of going quiet', () {
      final onlyMovement = [_activity('a-move', type: ActivityType.movement)];

      expect(
        _choose(onlyMovement, capacity: _capacity(CapacityLevel.low))
            ?.activity
            .id,
        'a-move',
      );
    });

    test('a learned pick gets a nudge, not a mandate', () {
      List<SuggestionRecord> history(String id, int count) => [
        for (var i = 0; i < count; i++)
          SuggestionRecord(
            id: '$id-$i',
            activityId: id,
            shownAt: _now.subtract(Duration(days: i + 3)),
            contextTags: const ['steady'],
            status: SuggestionStatus.completed,
            rating: 5,
            source: SuggestionSource.learned,
          ),
      ];
      final explore = [
        for (var i = 0; i < 5; i++)
          SuggestionRecord(
            id: 'explore-$i',
            activityId: 'elsewhere-$i',
            shownAt: _now.subtract(Duration(days: i + 1)),
            contextTags: const [],
            status: SuggestionStatus.skipped,
            skipReason: SuggestionSkipReason.notNow,
            source: SuggestionSource.explore,
          ),
      ];

      // Equal evidence for both: the gentle kind wins at low capacity only.
      final even = [...explore, ...history('a-move', 5), ...history('b-mind', 5)];
      final unaided = _choose(library, history: even, currentState: 'steady');
      final tired = _choose(
        library,
        history: even,
        currentState: 'steady',
        capacity: _capacity(CapacityLevel.low),
      );
      expect(unaided?.source, SuggestionSource.learned);
      expect(unaided?.activity.id, 'a-move');
      expect(tired?.activity.id, 'b-mind');

      // Far stronger evidence for the other kind still wins.
      final lopsided = [
        ...explore,
        ...history('a-move', 12),
        ...history('b-mind', 5),
      ];
      final stillMove = _choose(
        library,
        history: lopsided,
        currentState: 'steady',
        capacity: _capacity(CapacityLevel.low),
      );
      expect(stillMove?.activity.id, 'a-move');
    });
  });

  group('explanation', () {
    final library = [_activity('only')];

    test('says only that it was kept small, and only at low capacity', () {
      final low = _choose(library, capacity: _capacity(CapacityLevel.low))!;
      final high = _choose(library, capacity: _capacity(CapacityLevel.high))!;
      final none = _choose(library)!;

      expect(low.explanation, endsWith('Kept small for a slower moment.'));
      expect(high.explanation, isNot(contains('Kept small')));
      expect(none.explanation, isNot(contains('Kept small')));
    });

    test('never reveals why', () {
      final low = _choose(library, capacity: _capacity(CapacityLevel.low))!;

      for (final word in ['sleep', 'slept', 'tired', 'night', 'mood', 'phone']) {
        expect(low.explanation.toLowerCase(), isNot(contains(word)));
      }
    });
  });

  group('the context built from what the app knows', () {
    SessionRecord session(DateTime at, String? mood) => SessionRecord(
      id: at.microsecondsSinceEpoch.toString(),
      createdAt: at,
      mode: CaptureMode.text,
      mood: mood,
    );

    const withSleep = UserProfile(
      sleepStartMinutes: 23 * 60,
      sleepEndMinutes: 7 * 60,
    );

    test('carries a capacity estimate', () {
      final context = buildRecommendationContext(
        profile: withSleep,
        sessions: const [],
        now: DateTime(2026, 10, 1, 15),
      );

      expect(context.capacity, isNotNull);
      expect(context.capacity!.level, CapacityLevel.high);
      expect(context.capacity!.reasons, [CapacityReason.daytime]);
    });

    test('uses the stated sleep hours', () {
      final context = buildRecommendationContext(
        profile: withSleep,
        sessions: const [],
        now: DateTime(2026, 10, 1, 3),
      );

      expect(context.capacity!.level, CapacityLevel.low);
      expect(context.capacity!.reasons, [CapacityReason.inSleepWindow]);
    });

    test('works from the clock alone when no sleep hours were given', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: const [],
        now: DateTime(2026, 10, 1, 14),
      );

      expect(context.capacity!.level, CapacityLevel.medium);
      expect(context.capacity!.confidence, closeTo(0.2, 1e-9));
    });

    test('a recent wobbly check-in lowers it, and an old one does not', () {
      final recent = buildRecommendationContext(
        profile: withSleep,
        sessions: [session(DateTime(2026, 10, 1, 13), 'Wobbly')],
        now: DateTime(2026, 10, 1, 15),
      );
      final old = buildRecommendationContext(
        profile: withSleep,
        sessions: [session(DateTime(2026, 9, 29, 13), 'Wobbly')],
        now: DateTime(2026, 10, 1, 15),
      );

      expect(recent.capacity!.level, CapacityLevel.low);
      expect(recent.capacity!.reasons, contains(CapacityReason.lowMood));
      expect(old.capacity!.reasons, isNot(contains(CapacityReason.lowMood)));
    });

    test('a falling run of days is noticed', () {
      final context = buildRecommendationContext(
        profile: withSleep,
        sessions: [
          session(DateTime(2026, 10, 1, 9), 'Tender'),
          session(DateTime(2026, 9, 30, 9), 'Quiet'),
          session(DateTime(2026, 9, 29, 9), 'Bright'),
        ],
        now: DateTime(2026, 10, 1, 15),
      );

      expect(context.capacity!.reasons, contains(CapacityReason.decliningMood));
    });
  });

  group('dailyMoodScores', () {
    SessionRecord at(DateTime when, String? mood) => SessionRecord(
      id: when.microsecondsSinceEpoch.toString(),
      createdAt: when,
      mode: CaptureMode.text,
      mood: mood,
    );

    test('one median per day, oldest first, skipping days with no mood', () {
      final scores = dailyMoodScores(
        sessions: [
          at(DateTime(2026, 10, 1, 9), 'Bright'),
          at(DateTime(2026, 10, 1, 20), 'Wobbly'),
          at(DateTime(2026, 9, 29, 9), 'Steady'),
          at(DateTime(2026, 9, 30, 9), null),
        ],
        now: DateTime(2026, 10, 1, 22),
      );

      // Sept 29 steady; Sept 30 has no mood; Oct 1 median of Bright and Wobbly.
      expect(scores, [0.25, 0.0]);
    });

    test('only looks back the requested number of days', () {
      final scores = dailyMoodScores(
        sessions: [
          at(DateTime(2026, 9, 20, 9), 'Bright'),
          at(DateTime(2026, 10, 1, 9), 'Steady'),
        ],
        now: DateTime(2026, 10, 1, 22),
        days: 3,
      );

      expect(scores, [0.25]);
    });
  });

  test('the behavioral profile reports the capacity effect, not its inputs', () {
    final profile = BehavioralProfile.compute(
      profile: const UserProfile(),
      sessions: const [],
      suggestionHistory: const [],
      library: const [],
      context: RecommendationContext(capacity: _capacity(CapacityLevel.low)),
      now: _now,
    );

    expect(profile.engineState.capacityLevel, CapacityLevel.low);

    final without = BehavioralProfile.compute(
      profile: const UserProfile(),
      sessions: const [],
      suggestionHistory: const [],
      library: const [],
      context: const RecommendationContext(),
      now: _now,
    );
    expect(without.engineState.capacityLevel, isNull);
  });
}
