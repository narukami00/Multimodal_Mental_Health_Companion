import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/domain/recommendations/event_tagging.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sparse history never claims a personal fit', () async {
    final activities = await AssetActivityLibraryRepository().load();
    final recommendation = const RecommendationEngine().choose(
      activities: activities,
      profile: UserProfile(),
      context: RecommendationContext(profileAgeDays: 20),
      history: [],
      now: DateTime(2026, 9, 22, 10),
    );

    expect(recommendation, isNotNull);
    // With no history and no context, the pick is editorial, not learned, and
    // carries no confidence.
    expect(recommendation!.confidence, 0);
    expect(recommendation.source, isNot(SuggestionSource.learned));
  });

  test('active safety state is a hard boundary', () async {
    final activities = await AssetActivityLibraryRepository().load();
    final now = DateTime(2026, 9, 22, 10);
    const engine = RecommendationEngine();

    expect(
      engine.choose(
        activities: activities,
        profile: const UserProfile(),
        context: const RecommendationContext(safetyActive: true),
        history: const [],
        now: now,
      ),
      isNull,
    );
  });

  test(
    'a well-evidenced activity becomes a learned pick once the quota is met',
    () {
      final activity = _activity('movement-001');
      final other = _activity('mindfulness-001', type: ActivityType.mindfulness);
      final now = DateTime(2026, 9, 22, 10);
      final history = [
        // Recent slots are already exploratory, so the explore quota is
        // satisfied and the engine is free to pick a learned option.
        for (var index = 0; index < 5; index++)
          SuggestionRecord(
            id: 'explore-$index',
            activityId: 'elsewhere-$index',
            shownAt: now.subtract(Duration(days: index + 1)),
            contextTags: const [],
            status: SuggestionStatus.skipped,
            skipReason: SuggestionSkipReason.notNow,
            source: SuggestionSource.explore,
          ),
        for (var index = 0; index < 5; index++)
          SuggestionRecord(
            id: 'record-$index',
            activityId: activity.id,
            shownAt: now.subtract(Duration(days: index + 3)),
            contextTags: const ['steady'],
            status: SuggestionStatus.completed,
            rating: 5,
            source: SuggestionSource.learned,
          ),
      ];

      final recommendation = const RecommendationEngine().choose(
        activities: [activity, other],
        profile: const UserProfile(),
        context: const RecommendationContext(
          currentState: 'steady',
          profileAgeDays: 20,
        ),
        history: history,
        now: now,
      );

      expect(recommendation?.activity.id, activity.id);
      expect(recommendation?.source, SuggestionSource.learned);
      // Five clean outcomes settle just above the gate once recency decay is
      // applied, rather than at the 1.0 a plain ratio would have given.
      expect(recommendation?.confidence, greaterThan(0.6));
      expect(recommendation?.confidence, lessThanOrEqualTo(0.65));
      expect(recommendation?.isProactive, isTrue);
      expect(
        recommendation?.explanation,
        isNot(contains('starter')),
      );
    },
  );

  test('one good day is not enough to claim a fit', () {
    final activity = _activity('movement-001');
    final other = _activity('mindfulness-001', type: ActivityType.mindfulness);
    final now = DateTime(2026, 9, 22, 10);
    final history = [
      for (var index = 0; index < 5; index++)
        SuggestionRecord(
          id: 'explore-$index',
          activityId: 'elsewhere-$index',
          shownAt: now.subtract(Duration(days: index + 1)),
          contextTags: const [],
          status: SuggestionStatus.skipped,
          skipReason: SuggestionSkipReason.notNow,
          source: SuggestionSource.explore,
        ),
      SuggestionRecord(
        id: 'only',
        activityId: activity.id,
        shownAt: now.subtract(const Duration(days: 3)),
        contextTags: const ['steady'],
        status: SuggestionStatus.completed,
        rating: 5,
        source: SuggestionSource.learned,
      ),
    ];

    final recommendation = const RecommendationEngine().choose(
      activities: [activity, other],
      profile: const UserProfile(),
      context: const RecommendationContext(
        currentState: 'steady',
        profileAgeDays: 20,
      ),
      history: history,
      now: now,
    );

    // A single success fails the evidence gate, so it cannot be presented as a
    // personal fit even though it succeeded.
    expect(recommendation?.source, isNot(SuggestionSource.learned));
  });

  test('event tags normalize known aliases without diagnosing a cause', () {
    const service = EventTaggingService();
    final userTag = service.fromUserLabel(
      '  Office  ',
      now: DateTime(2026, 9, 22),
    );
    final extracted = service.extractKnownTags(
      'Work felt long and I was thinking about sleep.',
      now: DateTime(2026, 9, 22),
    );

    expect(userTag.canonicalLabel, 'work');
    expect(userTag.source.name, 'user');
    expect(
      extracted.map((tag) => tag.canonicalLabel),
      containsAll(['work', 'sleep']),
    );
  });

  test('"not now" and abandoned suggestions never lower confidence', () {
    final activity = _activity('movement-001');
    final now = DateTime(2026, 9, 22, 10);
    final successes = [
      for (var index = 0; index < 5; index++)
        SuggestionRecord(
          id: 'ok-$index',
          activityId: activity.id,
          shownAt: now.subtract(Duration(days: index + 3)),
          contextTags: const ['steady'],
          status: SuggestionStatus.completed,
          rating: 5,
        ),
    ];
    // Declining for now is explicitly free, and a card the user never answered
    // is not a decision at all.
    final noise = [
      SuggestionRecord(
        id: 'later',
        activityId: activity.id,
        shownAt: now.subtract(const Duration(days: 9)),
        contextTags: const ['steady'],
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notNow,
      ),
      SuggestionRecord(
        id: 'abandoned',
        activityId: activity.id,
        shownAt: now.subtract(const Duration(days: 10)),
        contextTags: const ['steady'],
      ),
    ];

    double confidenceFor(List<SuggestionRecord> history) {
      return const RecommendationEngine()
          .choose(
            activities: [activity],
            profile: const UserProfile(),
            context: const RecommendationContext(
              currentState: 'steady',
              profileAgeDays: 20,
            ),
            history: history,
            now: now,
          )!
          .confidence;
    }

    expect(confidenceFor([...successes, ...noise]), confidenceFor(successes));
  });

  test('"not for me" still counts against an activity', () {
    final activity = _activity('movement-001');
    final now = DateTime(2026, 9, 22, 10);
    final successes = [
      for (var index = 0; index < 3; index++)
        SuggestionRecord(
          id: 'ok-$index',
          activityId: activity.id,
          shownAt: now.subtract(Duration(days: index + 3)),
          contextTags: const ['steady'],
          status: SuggestionStatus.completed,
          rating: 5,
        ),
    ];
    final rejection = SuggestionRecord(
      id: 'no',
      activityId: activity.id,
      // Old enough that the month-long hide has lapsed, so the activity is
      // choosable and its confidence can be read.
      shownAt: now.subtract(const Duration(days: 40)),
      contextTags: const ['steady'],
      status: SuggestionStatus.skipped,
      skipReason: SuggestionSkipReason.notForMe,
    );

    double confidenceFor(List<SuggestionRecord> history) {
      return const RecommendationEngine()
          .choose(
            activities: [activity],
            profile: const UserProfile(),
            context: const RecommendationContext(
              currentState: 'steady',
              profileAgeDays: 20,
            ),
            history: history,
            now: now,
          )!
          .confidence;
    }

    expect(
      confidenceFor([...successes, rejection]),
      lessThan(confidenceFor(successes)),
    );
  });

  test('a real context reaches the engine and changes the outcome', () {
    final activity = _activity('movement-001');
    final other = _activity('mindfulness-001', type: ActivityType.mindfulness);
    final now = DateTime(2026, 9, 22, 10);
    final history = [
      // Exploratory slots already used, so the learned path is available.
      for (var index = 0; index < 5; index++)
        SuggestionRecord(
          id: 'explore-$index',
          activityId: 'elsewhere-$index',
          shownAt: now.subtract(Duration(days: index + 1)),
          contextTags: const [],
          status: SuggestionStatus.skipped,
          skipReason: SuggestionSkipReason.notNow,
          source: SuggestionSource.explore,
        ),
      for (var index = 0; index < 5; index++)
        SuggestionRecord(
          id: 'ok-$index',
          activityId: activity.id,
          shownAt: now.subtract(Duration(days: index + 3)),
          contextTags: const ['steady'],
          status: SuggestionStatus.completed,
          rating: 5,
          source: SuggestionSource.learned,
        ),
    ];

    Recommendation? chooseFor(RecommendationContext context) {
      return const RecommendationEngine().choose(
        activities: [activity, other],
        profile: const UserProfile(),
        context: context,
        history: history,
        now: now,
      );
    }

    // Passing no context used to make contextMatches always zero, so a learned
    // pick was impossible and the proactive path could never fire.
    final withoutContext = chooseFor(
      const RecommendationContext(profileAgeDays: 20),
    );
    expect(withoutContext?.confidence, 0);
    expect(withoutContext?.source, isNot(SuggestionSource.learned));

    final withContext = chooseFor(
      const RecommendationContext(currentState: 'steady', profileAgeDays: 20),
    );
    expect(withContext?.confidence, greaterThan(0.6));
    expect(withContext?.isProactive, isTrue);
    expect(withContext?.source, SuggestionSource.learned);
  });
}

Activity _activity(String id, {ActivityType type = ActivityType.movement}) {
  return Activity(
    id: id,
    title: type == ActivityType.mindfulness
        ? 'A slow breath'
        : 'A small walk',
    description: 'Walk at a comfortable pace for a few minutes.',
    type: type,
    effort: ActivityEffort.low,
    durationMinutes: 8,
    contexts: const ['outdoors'],
    targetStates: const ['steady'],
    review: ActivityReviewMetadata(
      status: ActivityReviewStatus.approved,
      evidenceTier: ActivityEvidenceTier.lifestyle,
      reviewerRole: 'lifestyle_reviewer',
      reviewedAt: DateTime(2026, 9, 22),
    ),
  );
}
