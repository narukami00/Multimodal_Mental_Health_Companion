import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/research/ablations.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/memory/companion_memory_context.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_context.dart';

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

double _evidence(SuggestionRecord record) => const RecommendationEngine()
    .standingOf(
      activities: [_activity()],
      profile: const UserProfile(),
      context: const RecommendationContext(currentState: 'steady', profileAgeDays: 30),
      history: [record],
      now: _now,
    )
    .single
    .evidenceN;

SuggestionRecord _record({String? before, String? after}) => SuggestionRecord(
  id: 'r',
  activityId: 'walk',
  shownAt: _now.subtract(const Duration(days: 1)),
  contextTags: const ['steady'],
  status: SuggestionStatus.completed,
  done: true,
  useful: SuggestionUsefulness.up,
  moodBefore: before,
  moodAfter: after,
);

void main() {
  tearDown(Ablations.reset);

  test('everything is on unless a study turns something off', () {
    expect(Ablations.current.capacity, isTrue);
    expect(Ablations.current.moodChangeOutcomes, isTrue);
    expect(Ablations.current.phoneSignals, isTrue);
    expect(Ablations.current.companionMemory, isTrue);
    expect(Ablations.current.label, 'all-on');
  });

  test('an arm is named by what it leaves out, in a fixed order', () {
    expect(const Ablations(phoneSignals: false, capacity: false).label, 'no-capacity+no-phone');
    expect(const Ablations(companionMemory: false).label, 'no-companion-memory');
  });

  group('capacity', () {
    RecommendationContext context() => buildRecommendationContext(
      profile: const UserProfile(),
      sessions: const [],
      now: DateTime(2026, 10, 1, 3),
    );

    test('on: the context carries a capacity reading', () {
      expect(context().capacity, isNotNull);
    });

    test('off: there is no capacity reading at all', () {
      Ablations.current = const Ablations(capacity: false);
      expect(context().capacity, isNull);
    });
  });

  group('how the person felt after an idea', () {
    test('on: a mood that rose after a thumbs-up counts a little more', () {
      final plain = _evidence(_record());
      final moved = _evidence(_record(before: 'Wobbly', after: 'Steady'));
      expect(moved, greaterThan(plain));
    });

    test('off: it counts exactly as if the mood had not been asked', () {
      Ablations.current = const Ablations(moodChangeOutcomes: false);
      final plain = _evidence(_record());
      expect(_evidence(_record(before: 'Wobbly', after: 'Steady')), plain);
      expect(_evidence(_record(before: 'Bright', after: 'Tender')), plain);
    });
  });

  group('what the companion is told', () {
    late ConsentController consent;
    late CompanionMemoryContext memory;

    setUp(() async {
      consent = ConsentController(repository: InMemoryConsentRepository());
      await consent.load();
      await consent.grant(ConsentKey.profileSnippet);
      await consent.grant(ConsentKey.memoryMoments);
      final repository = InMemoryProfileRepository();
      await repository.save(const UserProfile(interactionPreferences: ['Gentle tone']));
      final profile = ProfileController(repository: repository);
      await profile.load();
      final moments = MomentsController(repository: InMemoryMomentRepository());
      await moments.load();
      await moments.addManual('A good walk by the river.');
      memory = CompanionMemoryContext(
        consent: consent,
        profile: profile,
        moments: moments,
        sessions: () => const [],
        themes: () => const [],
        clock: () => _now,
      );
    });

    test('on: consented parts are sent', () {
      expect(memory.payload(), isNotNull);
    });

    test('off: nothing is sent even though everything was agreed to', () {
      Ablations.current = const Ablations(companionMemory: false);

      expect(memory.snippetOn, isFalse);
      expect(memory.momentsOn, isFalse);
      expect(memory.snippet().isEmpty, isTrue);
      expect(memory.momentLines(), isEmpty);
      expect(memory.payload(), isNull);
    });
  });
}
