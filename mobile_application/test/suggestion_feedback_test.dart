import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/domain/suggestions/suggestion_schedule.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';

class _FixedLibrary implements ActivityLibraryRepository {
  const _FixedLibrary(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

Activity _activity({
  required String id,
  ActivityEffort effort = ActivityEffort.low,
}) {
  return Activity(
    id: id,
    title: 'Activity $id',
    description: 'A small thing to try.',
    type: ActivityType.movement,
    effort: effort,
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
}

SuggestionController _controller(List<Activity> activities) {
  return SuggestionController(
    libraryRepository: _FixedLibrary(activities),
    suggestionRepository: InMemorySuggestionRepository(),
  );
}

const _context = RecommendationContext(profileAgeDays: 20);

void main() {
  group('recordCompletion', () {
    test('writes the completion without claiming anything helped', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
        userInitiated: true,
      );

      await controller.recordCompletion();

      final record = controller.currentRecord!;
      expect(record.status, SuggestionStatus.completed);
      expect(record.done, isTrue);
      // Doing it is not a statement that it helped.
      expect(record.useful, isNull);
      expect(record.rating, isNull);
    });
  });

  group('recordRating', () {
    test('rates an earlier completion without losing the completion', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
        userInitiated: true,
      );
      await controller.recordCompletion();
      final id = controller.currentRecord!.id;

      await controller.recordRating(
        recordId: id,
        usefulness: SuggestionUsefulness.up,
        rating: 5,
      );

      final record = controller.currentRecord!;
      expect(record.useful, SuggestionUsefulness.up);
      expect(record.rating, 5);
      // The completion survives a rating that arrives afterwards.
      expect(record.done, isTrue);
      expect(record.status, SuggestionStatus.completed);
    });

    test('a rating without doing it does not claim a completion', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
        userInitiated: true,
      );

      await controller.recordRating(
        recordId: controller.currentRecord!.id,
        usefulness: SuggestionUsefulness.down,
        rating: 1,
      );

      final record = controller.currentRecord!;
      expect(record.useful, SuggestionUsefulness.down);
      // Never inferred: the user never said they did it.
      expect(record.done, isNull);
      expect(record.status, SuggestionStatus.shown);
    });

    test('an unknown record id is ignored rather than throwing', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();

      await controller.recordRating(
        recordId: 'does-not-exist',
        usefulness: SuggestionUsefulness.up,
      );

      expect(controller.history, isEmpty);
    });
  });

  group('pendingRating', () {
    test('offers an unrated completion from the last two days', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
        userInitiated: true,
      );
      await controller.recordCompletion();

      expect(controller.pendingRating(), isNotNull);
    });

    test('stops offering it once it has been rated', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
        userInitiated: true,
      );
      await controller.recordCompletion();
      await controller.recordRating(
        recordId: controller.currentRecord!.id,
        usefulness: SuggestionUsefulness.up,
        rating: 4,
      );

      expect(controller.pendingRating(), isNull);
    });

    test('expires after forty-eight hours', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
        now: DateTime(2026, 9, 20, 10),
        userInitiated: true,
      );
      await controller.recordCompletion();

      expect(
        controller.pendingRating(now: DateTime(2026, 9, 20, 12)),
        isNotNull,
      );
      expect(
        controller.pendingRating(now: DateTime(2026, 9, 23, 10)),
        isNull,
      );
    });

    test('a suggestion that was only shown is not offered', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.suggest(
        profile: const UserProfile(),
        context: _context,
        userInitiated: true,
      );

      expect(controller.pendingRating(), isNull);
    });
  });

  group('peek', () {
    test('never writes a record, however many times it is asked', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.warmUp();

      // Home asks this on every rebuild. If it recorded anything, the counts
      // the confidence gate depends on would inflate with every frame.
      for (var i = 0; i < 25; i++) {
        controller.peek(
          profile: const UserProfile(),
          context: _context,
        );
      }

      expect(controller.history, isEmpty);
    });

    test('offers nothing until the library has been loaded', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();

      expect(
        controller.peek(profile: const UserProfile(), context: _context),
        isNull,
      );

      await controller.warmUp();
      expect(
        controller.peek(profile: const UserProfile(), context: _context),
        isNotNull,
      );
    });
  });

  group('commit', () {
    test('writes exactly one record for what was peeked', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.warmUp();
      final peeked = controller.peek(
        profile: const UserProfile(),
        context: _context,
      )!;

      await controller.commit(peeked, context: _context);

      expect(controller.history, hasLength(1));
      expect(controller.history.single.activityId, 'only');
      expect(controller.history.single.source, peeked.source);
    });
  });

  group('dismissRecord', () {
    test('declining suppresses the activity without counting against it', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      await controller.warmUp();
      final peeked = controller.peek(
        profile: const UserProfile(),
        context: _context,
      )!;
      final record = await controller.commit(peeked, context: _context);

      await controller.dismissRecord(
        record.id,
        reason: SuggestionSkipReason.notNow,
      );

      final saved = controller.history.single;
      expect(saved.status, SuggestionStatus.skipped);
      expect(saved.skipReason, SuggestionSkipReason.notNow);
      // Declining is free: it is not a completion, and it is not a verdict on
      // whether the activity helps.
      expect(saved.done, isNull);
      expect(saved.useful, isNull);
    });
  });

  group('the Home card after using the You page', () {
    test('asking for an idea does not silence the Home card', () async {
      final controller = _controller([
        _activity(id: 'a'),
        _activity(id: 'b'),
        _activity(id: 'c'),
      ]);
      await controller.load();
      await controller.warmUp();
      final profile = const UserProfile();

      // Exactly what testing the You page does: a user-initiated suggestion.
      final requested = await controller.suggest(
        profile: profile,
        context: _context,
        userInitiated: true,
      );
      expect(requested, isNotNull);

      // The peek Home uses must still find something. This was returning null,
      // so the card rendered nothing at all.
      final peeked = controller.peek(profile: profile, context: _context);
      expect(peeked, isNotNull);
    });

    test('a proactive nudge does use up the day', () async {
      final controller = _controller([_activity(id: 'a'), _activity(id: 'b')]);
      await controller.load();
      await controller.warmUp();
      final profile = const UserProfile();
      // Early days: one a day, so a single nudge exhausts the budget.
      const earlyContext = RecommendationContext(profileAgeDays: 5);

      final peeked = controller.peek(
        profile: profile,
        context: earlyContext,
      )!;
      await controller.commit(peeked, context: earlyContext, proactive: true);

      expect(
        controller.peek(profile: profile, context: earlyContext),
        isNull,
      );
    });

    test('the schedule and the engine agree on what is due', () async {
      final controller = _controller([_activity(id: 'a'), _activity(id: 'b')]);
      await controller.load();
      await controller.warmUp();
      final profile = const UserProfile();
      final now = DateTime.now();

      // If these two ever disagree, the card is shown with nothing in it.
      final due = const SuggestionSchedule().isDue(
        history: controller.history,
        profileAgeDays: null,
        checkInCompletedToday: true,
        now: now,
      );
      final peeked = controller.peek(
        profile: profile,
        context: _context,
        now: now,
      );

      expect(due, peeked != null);
    });
  });

  group('impact', () {
    test('"not for me" takes the activity out of future picks', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      final profile = const UserProfile();

      final first = await controller.suggest(
        profile: profile,
        context: _context,
        userInitiated: true,
      );
      expect(first?.activity.id, 'only');

      await controller.submitFeedback(
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notForMe,
      );

      // The month-long hide means there is genuinely nothing left to offer.
      final second = await controller.suggest(
        profile: profile,
        context: _context,
        userInitiated: true,
      );
      expect(second, isNull);
    });

    test('"too much right now" keeps the next suggestion gentle', () async {
      final controller = _controller([
        _activity(id: 'gentle-a', effort: ActivityEffort.low),
        _activity(id: 'gentle-b', effort: ActivityEffort.low),
        _activity(id: 'demanding', effort: ActivityEffort.high),
      ]);
      await controller.load();
      final profile = const UserProfile();

      final first = await controller.suggest(
        profile: profile,
        context: _context,
        userInitiated: true,
      );
      await controller.submitFeedback(
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.tooHard,
      );

      final second = await controller.suggest(
        profile: profile,
        context: _context,
        userInitiated: true,
      );

      // The demanding option is now above the ceiling, so only the other
      // gentle one is reachable.
      expect(second, isNotNull);
      expect(second?.activity.effort, ActivityEffort.low);
      expect(second?.activity.id, isNot(first?.activity.id));
      expect(second?.activity.id, isNot('demanding'));
    });

    test('"not right now" leaves the activity available', () async {
      final controller = _controller([_activity(id: 'only')]);
      await controller.load();
      final profile = const UserProfile();

      await controller.suggest(
        profile: profile,
        context: _context,
        userInitiated: true,
      );
      await controller.submitFeedback(
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notNow,
      );

      // Suppressed for twelve hours, but not disqualified: a day later it is
      // available again, because declining is free.
      final later = await controller.suggest(
        profile: profile,
        context: _context,
        now: DateTime.now().add(const Duration(hours: 13)),
        userInitiated: true,
      );
      expect(later?.activity.id, 'only');
    });
  });
}
