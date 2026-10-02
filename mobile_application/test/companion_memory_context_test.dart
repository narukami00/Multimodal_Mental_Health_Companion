import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/memory/companion_memory_context.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';

void main() {
  late ConsentController consent;
  late ProfileController profile;
  late MomentsController moments;
  late CompanionMemoryContext context;

  setUp(() async {
    consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    final repository = InMemoryProfileRepository();
    await repository.save(const UserProfile(interactionPreferences: ['Gentle tone']));
    profile = ProfileController(repository: repository);
    await profile.load();
    moments = MomentsController(repository: InMemoryMomentRepository());
    await moments.load();
    context = CompanionMemoryContext(
      consent: consent,
      profile: profile,
      moments: moments,
      sessions: () => const [],
      themes: () => const ['work'],
      clock: () => DateTime(2026, 10, 20, 15),
    );
  });

  test('tells the server nothing until each part is agreed to', () async {
    await moments.addManual('A good walk by the river.');

    expect(context.payload(), isNull);
    expect(context.snippet().isEmpty, isTrue);
    expect(context.momentLines(), isEmpty);
  });

  test('the snippet needs its own consent and carries only words', () async {
    await consent.grant(ConsentKey.profileSnippet);

    final payload = context.payload()!;
    expect(payload['profile_snippet'], contains('gentle tone'));
    expect(payload['profile_snippet'], contains('work'));
    expect(payload.containsKey('memory_facts'), isFalse);
    expect(payload['v'], 1);
  });

  test('moments are a separate consent, and only kept ones are sent', () async {
    await consent.grant(ConsentKey.memoryMoments);
    final kept = (await moments.addManual('A good walk by the river.'))!;
    await moments.addManual('Tea with my sister.');
    await moments.hide(kept.id);

    final payload = context.payload()!;
    expect(payload['memory_facts'], ['Tea with my sister.']);
    expect(payload.containsKey('profile_snippet'), isFalse);
  });

  test('withdrawing consent stops it at once', () async {
    await consent.grant(ConsentKey.memoryMoments);
    await moments.addManual('A good walk by the river.');
    expect(context.payload(), isNotNull);

    await consent.revoke(ConsentKey.memoryMoments);
    expect(context.payload(), isNull);
  });
}
