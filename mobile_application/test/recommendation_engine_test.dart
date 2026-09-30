import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/domain/recommendations/event_tagging.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sparse history returns a low-pressure suggestion', () async {
    final activities = await AssetActivityLibraryRepository().load();
    final recommendation = const RecommendationEngine().choose(
      activities: activities,
      profile: UserProfile(),
      context: RecommendationContext(profileAgeDays: 20),
      history: [],
      now: DateTime(2026, 9, 22, 10),
    );

    expect(recommendation, isNotNull);
    expect(recommendation!.confidence, 0);
    expect(recommendation.isProactive, isFalse);
  });

  test('daily cap and active safety state are hard boundaries', () async {
    final activities = await AssetActivityLibraryRepository().load();
    final now = DateTime(2026, 9, 22, 10);
    final shown = SuggestionRecord(
      id: 'shown',
      activityId: activities.first.id,
      shownAt: now,
      contextTags: const [],
    );
    const engine = RecommendationEngine();

    expect(
      engine.choose(
        activities: activities,
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 3),
        history: [shown],
        now: now,
      ),
      isNull,
    );
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
    'repeated successful outcomes raise confidence without bypassing cooldown',
    () {
      final activity = _activity('movement-001');
      final now = DateTime(2026, 9, 22, 10);
      final history = [
        for (var index = 0; index < 5; index++)
          SuggestionRecord(
            id: 'record-$index',
            activityId: activity.id,
            shownAt: now.subtract(Duration(days: index + 3)),
            contextTags: const ['steady'],
            status: SuggestionStatus.completed,
            rating: 5,
          ),
      ];

      final recommendation = const RecommendationEngine().choose(
        activities: [activity],
        profile: const UserProfile(),
        context: const RecommendationContext(
          currentState: 'steady',
          profileAgeDays: 20,
        ),
        history: history,
        now: now,
      );

      expect(recommendation?.confidence, 1);
      expect(recommendation?.isProactive, isTrue);
    },
  );

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
    final history = [
      for (var index = 0; index < 5; index++)
        SuggestionRecord(
          id: 'ok-$index',
          activityId: activity.id,
          shownAt: now.subtract(Duration(days: index + 3)),
          contextTags: const ['steady'],
          status: SuggestionStatus.completed,
          rating: 5,
        ),
      // Declining for now is explicitly free, and a card the user never
      // answered is not a decision at all.
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

    final recommendation = const RecommendationEngine().choose(
      activities: [activity],
      profile: const UserProfile(),
      context: const RecommendationContext(
        currentState: 'steady',
        profileAgeDays: 20,
      ),
      history: history,
      now: now,
    );

    expect(recommendation?.confidence, 1);
  });

  test('"not for me" and "too hard" still count against an activity', () {
    final activity = _activity('movement-001');
    final now = DateTime(2026, 9, 22, 10);
    final history = [
      for (var index = 0; index < 3; index++)
        SuggestionRecord(
          id: 'ok-$index',
          activityId: activity.id,
          shownAt: now.subtract(Duration(days: index + 3)),
          contextTags: const ['steady'],
          status: SuggestionStatus.completed,
          rating: 5,
        ),
      SuggestionRecord(
        id: 'no',
        activityId: activity.id,
        shownAt: now.subtract(const Duration(days: 6)),
        contextTags: const ['steady'],
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notForMe,
      ),
    ];

    final recommendation = const RecommendationEngine().choose(
      activities: [activity],
      profile: const UserProfile(),
      context: const RecommendationContext(
        currentState: 'steady',
        profileAgeDays: 20,
      ),
      history: history,
      now: now,
    );

    // Four decisions, three of them successful.
    expect(recommendation?.confidence, closeTo(4 / 5 * 0.75, 0.0001));
  });

  test('a real context reaches the engine and can mark a suggestion proactive', () {
    final activity = _activity('movement-001');
    final now = DateTime(2026, 9, 22, 10);
    final history = [
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

    // Passing no context used to make contextMatches always zero, so the
    // proactive path could never fire.
    final withoutContext = const RecommendationEngine().choose(
      activities: [activity],
      profile: const UserProfile(),
      context: const RecommendationContext(profileAgeDays: 20),
      history: history,
      now: now,
    );
    expect(withoutContext?.isProactive, isFalse);

    final withContext = const RecommendationEngine().choose(
      activities: [activity],
      profile: const UserProfile(),
      context: const RecommendationContext(
        currentState: 'steady',
        profileAgeDays: 20,
      ),
      history: history,
      now: now,
    );
    expect(withContext?.isProactive, isTrue);
  });
}

Activity _activity(String id) {
  return Activity(
    id: id,
    title: 'A small walk',
    description: 'Walk at a comfortable pace for a few minutes.',
    type: ActivityType.movement,
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
