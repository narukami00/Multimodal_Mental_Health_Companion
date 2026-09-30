import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';

/// Checks the recommender against the real activity library rather than a
/// hand-built one. The design rests on assumptions about what that library
/// contains — enough gentle options to fill a fortnight, spread widely enough to
/// vary — and those were never actually measured.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Activity> library;

  setUpAll(() async {
    library = await AssetActivityLibraryRepository().load();
  });

  group('the starter pool', () {
    test('is large enough to fill the fortnight without repeats', () async {
      final pool = library.where(isStarterCandidate).toList();

      // One a day for fourteen days. Anything less and the tour repeats itself
      // inside its own window, which reads as a lack of imagination.
      expect(
        pool.length,
        greaterThanOrEqualTo(14),
        reason: 'only ${pool.length} starter candidates in ${library.length}',
      );
    });

    test('spans enough types for the no-repeat-type rule to hold', () async {
      final types = library
          .where(isStarterCandidate)
          .map((activity) => activity.type)
          .toSet();

      // The tour never shows the same type on consecutive days, so fewer than
      // five types would make that rule impossible to satisfy for long.
      expect(types.length, greaterThanOrEqualTo(5));
    });

    test('is not the whole library, or the tour is not a gentle one', () {
      final pool = library.where(isStarterCandidate).length;

      expect(pool, lessThan(library.length));
      expect(pool, greaterThan(0));
    });

    test('every candidate is short enough to start without deciding to', () {
      for (final activity in library.where(isStarterCandidate)) {
        expect(activity.effort, ActivityEffort.low);
        expect(
          activity.durationMinutes,
          lessThanOrEqualTo(RecommendationEngine.starterDurationCeiling),
        );
      }
    });
  });

  group('a fortnight of the tour', () {
    test('never repeats a type on consecutive days', () {
      const engine = RecommendationEngine();
      var history = <SuggestionRecord>[];
      var start = DateTime(2026, 9, 1, 10);
      ActivityType? previous;
      final seen = <ActivityType>{};

      for (var day = 0; day < 14; day++) {
        final now = start.add(Duration(days: day));
        final pick = engine.choose(
          activities: library,
          profile: const UserProfile(),
          // Ages 0 to 13 are the tour's fourteen days.
          context: RecommendationContext(profileAgeDays: day),
          history: history,
          now: now,
        );
        expect(pick, isNotNull, reason: 'the tour ran dry on day ${day + 1}');
        expect(pick!.source, SuggestionSource.starter);

        expect(
          pick.activity.type,
          isNot(previous),
          reason: 'repeated ${pick.activity.type} on day ${day + 1}',
        );
        previous = pick.activity.type;
        seen.add(pick.activity.type);

        history = [
          ...history,
          SuggestionRecord(
            id: 'day-$day',
            activityId: pick.activity.id,
            shownAt: now,
            contextTags: const [],
            proactive: true,
          ),
        ];
      }

      // A fortnight should not be one type over and over.
      expect(seen.length, greaterThanOrEqualTo(5));
    });

    test('gives out a different activity each day', () {
      const engine = RecommendationEngine();
      var history = <SuggestionRecord>[];
      final chosen = <String>[];

      for (var day = 0; day < 14; day++) {
        final now = DateTime(2026, 9, 1, 10).add(Duration(days: day));
        final pick = engine.choose(
          activities: library,
          profile: const UserProfile(),
          context: RecommendationContext(profileAgeDays: day),
          history: history,
          now: now,
        )!;
        chosen.add(pick.activity.id);
        history = [
          ...history,
          SuggestionRecord(
            id: 'day-$day',
            activityId: pick.activity.id,
            shownAt: now,
            contextTags: const [],
            proactive: true,
          ),
        ];
      }

      // The second week must not be the first week again.
      expect(chosen.toSet().length, greaterThanOrEqualTo(14));
    });
  });

  group('the explore quota', () {
    test('a user with no feedback gets only unfamiliar ideas', () {
      // Not a bug: with nothing learned, there is nothing to balance against,
      // and the plan says an empty exploit slot falls back to explore rather
      // than going quiet.
      const engine = RecommendationEngine();
      var history = <SuggestionRecord>[];

      for (var slot = 0; slot < 5; slot++) {
        final at = DateTime(2026, 10, 1, 9).add(Duration(hours: 25 * slot));
        final pick = engine.choose(
          activities: library,
          profile: const UserProfile(),
          context: const RecommendationContext(
            profileAgeDays: 60,
            currentState: 'steady',
          ),
          history: history,
          now: at,
        )!;
        expect(pick.source, SuggestionSource.explore);
        history = [
          ...history,
          SuggestionRecord(
            id: 'slot-$slot',
            activityId: pick.activity.id,
            shownAt: at,
            contextTags: const ['steady'],
            proactive: true,
            source: pick.source,
          ),
        ];
      }
    });

    test('holds the promised share once learned picks exist', () {
      const engine = RecommendationEngine();
      final start = DateTime(2026, 9, 20, 10);

      // Give a handful of activities enough outcomes to clear the gate, so the
      // quota has something to balance against.
      var history = <SuggestionRecord>[
        for (final activity in library.take(8))
          for (var i = 0; i < 5; i++)
            SuggestionRecord(
              id: '${activity.id}-$i',
              activityId: activity.id,
              shownAt: start.subtract(Duration(days: i + 1)),
              contextTags: const ['steady'],
              proactive: true,
              source: SuggestionSource.learned,
              done: true,
              useful: SuggestionUsefulness.up,
            ),
      ];

      var exploreCount = 0;
      var slots = 0;
      for (var slot = 0; slot < 24; slot++) {
        final at = start.add(Duration(hours: 25 * slot));
        final pick = engine.choose(
          activities: library,
          profile: const UserProfile(),
          context: const RecommendationContext(
            profileAgeDays: 60,
            currentState: 'steady',
          ),
          history: history,
          now: at,
        );
        if (pick == null) continue;
        slots++;
        if (pick.source == SuggestionSource.explore) exploreCount++;
        history = [
          ...history,
          SuggestionRecord(
            id: 'slot-$slot',
            activityId: pick.activity.id,
            shownAt: at,
            contextTags: const ['steady'],
            proactive: true,
            source: pick.source,
          ),
        ];
      }

      expect(slots, greaterThan(10));
      final share = exploreCount / slots;
      // The target after the settling point is a third, with a fifth as a
      // floor. Anything far outside that means the quota is not being honoured.
      expect(share, greaterThanOrEqualTo(0.2));
      expect(share, lessThanOrEqualTo(0.6));
    });
  });

  group('the honest limit', () {
    test('a slow start is what a new user actually gets', () {
      // With no check-ins and no feedback there is no context to match on, so
      // no activity can clear the gate. Everything offered is editorial. This
      // is the limit recorded in the plan, expressed as a test rather than a
      // sentence in a document.
      const engine = RecommendationEngine();
      final pick = engine.choose(
        activities: library,
        profile: const UserProfile(),
        context: const RecommendationContext(profileAgeDays: 30),
        history: const [],
        now: DateTime(2026, 10, 1, 10),
      );

      expect(pick, isNotNull);
      expect(pick!.confidence, 0);
      expect(pick.source, isNot(SuggestionSource.learned));
    });

    test('no activity is claimed as a personal fit on thin evidence', () {
      const engine = RecommendationEngine();

      for (final activity in library) {
        final pick = engine.choose(
          activities: [activity],
          profile: const UserProfile(),
          context: RecommendationContext(
            profileAgeDays: 40,
            currentState: 'steady',
          ),
          history: [
            // A single good outcome: the most that could be claimed from one
            // good day.
            SuggestionRecord(
              id: 'one',
              activityId: activity.id,
              shownAt: DateTime(2026, 9, 25, 10),
              contextTags: const ['steady'],
              proactive: true,
              done: true,
              useful: SuggestionUsefulness.up,
            ),
          ],
          now: DateTime(2026, 10, 1, 10),
        );

        // Either nothing is offered, or it is not dressed up as learned.
        if (pick != null) {
          expect(
            pick.source,
            isNot(SuggestionSource.learned),
            reason: '${activity.id} was claimed as a fit from one outcome',
          );
        }
      }
    });
  });
}
