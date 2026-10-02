import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/features/suggestions/suggestion_context.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';

class _Library implements ActivityLibraryRepository {
  @override
  Future<List<Activity>> load() async => [
    Activity(
      id: 'only',
      title: 'A short walk',
      description: 'A small thing to try.',
      type: ActivityType.movement,
      effort: ActivityEffort.low,
      durationMinutes: 5,
      contexts: const [],
      targetStates: const [],
      review: ActivityReviewMetadata(
        status: ActivityReviewStatus.approved,
        evidenceTier: ActivityEvidenceTier.lifestyle,
        reviewerRole: 'test',
        reviewedAt: DateTime(2026, 1, 1),
      ),
    ),
  ];
}

SessionRecord _session(String text) => SessionRecord(
  id: '1',
  createdAt: DateTime(2026, 10, 1, 9),
  mode: CaptureMode.text,
  text: text,
  mood: 'Steady',
);

void main() {
  final now = DateTime(2026, 10, 1, 12);

  group('themes the person chose', () {
    test('count as context beside what they wrote about', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [_session('a long day at work')],
        now: now,
        extraTags: const ['sleep', 'money'],
      );

      expect(context.eventTags, ['work', 'sleep', 'money']);
      expect(context.normalizedTags, containsAll(['work', 'sleep', 'money']));
    });

    test('are counted once when they also wrote about them', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [_session('work is a lot')],
        now: now,
        extraTags: const ['work', 'home'],
      );

      expect(context.eventTags, ['work', 'home']);
    });

    test('apply even when the latest check-in said nothing', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: const [],
        now: now,
        extraTags: const ['health'],
      );

      expect(context.eventTags, ['health']);
    });

    test('change nothing when there are none', () {
      final plain = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [_session('work is a lot')],
        now: now,
      );
      final empty = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [_session('work is a lot')],
        now: now,
        extraTags: const [],
      );

      expect(plain.eventTags, empty.eventTags);
      expect(plain.eventTags, ['work']);
    });

    test('are remembered on the suggestion that was made in that context', () async {
      final controller = SuggestionController(
        libraryRepository: _Library(),
        suggestionRepository: InMemorySuggestionRepository(),
      );
      await controller.load();

      await controller.suggest(
        profile: const UserProfile(),
        context: buildRecommendationContext(
          profile: const UserProfile(),
          sessions: const [],
          now: now,
          extraTags: const ['work'],
        ),
        now: now,
      );

      // So later outcomes can be learned against the context they happened in.
      expect(controller.currentRecord!.contextTags, contains('work'));
    });
  });
}
