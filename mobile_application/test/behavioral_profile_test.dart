import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/domain/profile/behavioral_profile.dart';
import 'package:solace_mobile/domain/profile/quiz_bank.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';

final _now = DateTime(2026, 10, 1, 10);

Activity _activity(String id, ActivityType type, {ActivityEffort effort = ActivityEffort.low}) {
  return Activity(
    id: id,
    title: id,
    description: '',
    type: type,
    effort: effort,
    durationMinutes: 5,
    contexts: const [],
    targetStates: const [],
    review: ActivityReviewMetadata(
      status: ActivityReviewStatus.approved,
      evidenceTier: ActivityEvidenceTier.lifestyle,
      reviewerRole: 'test',
      reviewedAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
}

SessionRecord _session(DateTime at) {
  return SessionRecord(
    id: 's${at.microsecondsSinceEpoch}',
    createdAt: at,
    mode: CaptureMode.text,
  );
}

void main() {
  test('a fresh profile reads as untouched, with honest empty states', () {
    final profile = BehavioralProfile.compute(
      profile: const UserProfile(),
      sessions: const [],
      suggestionHistory: const [],
      library: [_activity('a1', ActivityType.movement)],
      context: const RecommendationContext(),
      now: _now,
    );

    expect(profile.totalAccepted, 0);
    expect(profile.totalAnswered, 0);
    expect(profile.typeAcceptance, isEmpty);
    expect(profile.engineState.daysLeftOfStarterTour, 14);
    expect(profile.engineState.typesClearingGate, isEmpty);
    expect(profile.engineState.hiddenCount, 0);
    expect(profile.baseline.preferGentle, isFalse);
  });

  test('completion, rejection and not-now are counted per their verdicts', () {
    const movement = 'a1';
    const mindfulness = 'a2';
    final history = [
      // Done and rated up.
      SuggestionRecord(
        id: 'r1',
        activityId: movement,
        shownAt: _now.subtract(const Duration(days: 2)),
        contextTags: const [],
        status: SuggestionStatus.completed,
        done: true,
        useful: SuggestionUsefulness.up,
      ),
      // Declined for real.
      SuggestionRecord(
        id: 'r2',
        activityId: movement,
        shownAt: _now.subtract(const Duration(days: 3)),
        contextTags: const [],
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notForMe,
      ),
      // Dismissed: no verdict, still an impression.
      SuggestionRecord(
        id: 'r3',
        activityId: mindfulness,
        shownAt: _now.subtract(const Duration(days: 1)),
        contextTags: const [],
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notNow,
      ),
    ];

    final profile = BehavioralProfile.compute(
      profile: const UserProfile(),
      sessions: const [],
      suggestionHistory: history,
      library: [
        _activity(movement, ActivityType.movement),
        _activity(mindfulness, ActivityType.mindfulness),
      ],
      context: const RecommendationContext(),
      now: _now,
    );

    final movementStats = profile.typeAcceptance[ActivityType.movement]!;
    expect(movementStats.completed, 1);
    expect(movementStats.declined, 1);
    expect(movementStats.usefulUp, 1);
    expect(movementStats.completionShare, closeTo(0.5, 0.001));
    expect(movementStats.subtitle, '1 of 2 completed');

    final mindfulnessStats = profile.typeAcceptance[ActivityType.mindfulness]!;
    expect(mindfulnessStats.notNow, 1);
    expect(mindfulnessStats.completed + mindfulnessStats.declined, 0);
    expect(mindfulnessStats.subtitle, 'Offered once, no answer yet');

    expect(profile.totalAccepted, 1);
    expect(profile.totalAnswered, 2);
  });

  test('never-suggest aliases and shelving surface as hidden ideas', () {
    final history = [
      for (var i = 0; i < 3; i++)
        SuggestionRecord(
          id: 'reject-$i',
          activityId: 'movement-1',
          shownAt: _now.subtract(Duration(days: 20 - i)),
          contextTags: const [],
          status: SuggestionStatus.skipped,
          skipReason: SuggestionSkipReason.notForMe,
        ),
    ];

    final shelved = BehavioralProfile.compute(
      profile: const UserProfile(),
      sessions: const [],
      suggestionHistory: history,
      library: [
        _activity('movement-1', ActivityType.movement),
        _activity('mind-1', ActivityType.mindfulness),
      ],
      context: const RecommendationContext(),
      now: _now,
    );
    expect(shelved.shelvedActivities.map((a) => a.id), ['movement-1']);
    expect(shelved.engineState.hiddenCount, 1);

    final never = BehavioralProfile.compute(
      profile: const UserProfile(neverSuggest: ['Exercise']),
      sessions: const [],
      suggestionHistory: const [],
      library: [_activity('movement-1', ActivityType.movement)],
      context: const RecommendationContext(),
      now: _now,
    );
    expect(never.neverSuggestedTypes, ['movement']);
    expect(never.engineState.hiddenCount, 1);
  });

  test('strong evidence in the active context clears the learned gate', () {
    final activity = _activity('movement-1', ActivityType.movement);
    // Five explore slots in the recent window satisfy the quota.
    final history = [
      for (var i = 0; i < 5; i++)
        SuggestionRecord(
          id: 'explore-$i',
          activityId: 'other-$i',
          shownAt: _now.subtract(Duration(days: i + 1)),
          contextTags: const [],
          status: SuggestionStatus.skipped,
          skipReason: SuggestionSkipReason.notNow,
          source: SuggestionSource.explore,
        ),
      for (var i = 0; i < 6; i++)
        SuggestionRecord(
          id: 'done-$i',
          activityId: 'movement-1',
          shownAt: _now.subtract(Duration(days: i + 1)),
          contextTags: const ['steady'],
          status: SuggestionStatus.completed,
          done: true,
          rating: 5,
          source: SuggestionSource.learned,
        ),
    ];

    final withTags = BehavioralProfile.compute(
      profile: const UserProfile(),
      sessions: const [],
      suggestionHistory: history,
      library: [activity],
      // Same tags as the records, so the evidence is all first-hand.
      context: const RecommendationContext(
        currentState: 'steady',
        profileAgeDays: 60,
      ),
      now: _now,
    );
    expect(withTags.engineState.typesClearingGate, ['movement']);

    final withoutTags = BehavioralProfile.compute(
      profile: const UserProfile(),
      sessions: const [],
      suggestionHistory: history,
      library: [activity],
      context: const RecommendationContext(profileAgeDays: 60),
      now: _now,
    );
    // The engine only credits evidence that shares the current context; the
    // page must say the same thing.
    expect(withoutTags.engineState.typesClearingGate, isEmpty);
  });

  test('a moderate GAD-7 or PHQ-9 turns on gentle-first', () {
    final profile = UserProfile(
      gad7Answers: {
        for (final question in gad7Questions) question.id: 2,
      },
    );
    final computed = BehavioralProfile.compute(
      profile: profile,
      sessions: const [],
      suggestionHistory: const [],
      library: const [],
      context: const RecommendationContext(),
      now: _now,
    );
    expect(computed.baseline.preferGentle, isTrue);
    final worry = computed.baseline.blocks
        .firstWhere((block) => block.label == 'Worry');
    expect(worry.skipped, isFalse);
    expect(worry.score, 14);
    expect(worry.summary, 'Done · 14 of 21');
  });

  test('skipped blocks read as answered by choice, not missing', () {
    final profile = UserProfile(
      skippedBlocks: [QuizBlock.erqS.name],
    );
    final computed = BehavioralProfile.compute(
      profile: profile,
      sessions: const [],
      suggestionHistory: const [],
      library: const [],
      context: const RecommendationContext(),
      now: _now,
    );
    final erq = computed.baseline.blocks
        .firstWhere((block) => block.label == 'Handling emotions');
    expect(erq.skipped, isTrue);
    expect(erq.summary, 'Skipped by choice');
    expect(computed.baseline.allAnsweredOrSkipped, isFalse);
  });

  test('momentum counts check-ins and rest days across the last two weeks', () {
    final restDays = [
      for (var i = 0; i < 3; i++)
        DateTime(2026, 9, 30)
            .subtract(Duration(days: i))
            .toIso8601String()
            .split('T')
            .first,
    ];
    final profile = UserProfile(
      firstRunAt: _now.subtract(const Duration(days: 60)),
      restDays: restDays,
    );
    final computed = BehavioralProfile.compute(
      profile: profile,
      sessions: [
        _session(_now.subtract(const Duration(hours: 1))),
        _session(_now.subtract(const Duration(days: 2))),
      ],
      suggestionHistory: const [],
      library: const [],
      context: const RecommendationContext(),
      now: _now,
    );
    expect(computed.momentum.checkInsLast14Days, 2);
    expect(computed.momentum.restDaysLast14Days, 3);
    expect(computed.engineState.profileAgeDays, 60);
    expect(computed.engineState.daysLeftOfStarterTour, 0);
    // 60 days in: explore share target has settled to its long-run value.
    expect(computed.engineState.exploreTargetShare, closeTo(0.3, 0.001));
  });
}
