import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
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
