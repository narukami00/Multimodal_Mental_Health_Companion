import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/memory/companion_memory_context.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';
import 'package:solace_mobile/features/memory/user_facts_controller.dart';
import 'package:solace_mobile/features/memory/what_sol_remembers_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserFactsController', () {
    test('extracts non-clinical facts lazily after >=2 user turns with delta guard', () async {
      var calls = 0;
      var fakeNow = DateTime(2026, 11, 13, 10, 0);
      final controller = UserFactsController(
        clock: () => fakeNow,
        extractor: (turns, existing) async {
          calls++;
          return const UserFactExtractionResult(
            facts: [
              'Studies computer science',
              'Has a dog named Milo',
              'Diagnosed with clinical depression', // filtered by momentIsSensitive
              'Has a dog called Milo', // near duplicate
            ],
            identitySummary: 'They study computer science and have a dog named Milo.',
            method: 'model',
          );
        },
      );
      await controller.load();

      // Single user turn -> skipped.
      await controller.extractFromConversation(
        conversationId: 'conv_1',
        turns: const [
          {'role': 'user', 'text': 'I study computer science.'},
        ],
      );
      expect(calls, 0);
      expect(controller.facts, isEmpty);

      // Two user turns -> extracts & deduplicates & filters sensitive entries.
      final twoTurns = const [
        {'role': 'user', 'text': 'I study computer science.'},
        {'role': 'assistant', 'text': 'Nice!'},
        {'role': 'user', 'text': 'I also have a dog named Milo.'},
      ];
      await controller.extractFromConversation(
        conversationId: 'conv_1',
        turns: twoTurns,
      );
      expect(calls, 1);
      expect(controller.facts.map((f) => f.text).toList(), hasLength(2));
      expect(
        controller.facts.map((f) => f.text),
        containsAll(['Studies computer science', 'Has a dog named Milo']),
      );
      expect(
        controller.identitySummary,
        'They study computer science and have a dog named Milo.',
      );

      // Same turn count again -> skipped by delta check.
      await controller.extractFromConversation(
        conversationId: 'conv_1',
        turns: twoTurns,
      );
      expect(calls, 1);

      // Reload from persistence retains saved facts & summary.
      final reloaded = UserFactsController(clock: () => fakeNow);
      await reloaded.load();
      expect(reloaded.facts.map((f) => f.text), contains('Studies computer science'));
      expect(
        reloaded.identitySummary,
        'They study computer science and have a dog named Milo.',
      );

      // Age decay keeps weights bounded in [0.15, 1.0].
      fakeNow = fakeNow.add(const Duration(days: 60));
      final scores = controller.factRecencyScores();
      expect(scores.every((s) => s >= 0.15 && s <= 1.0), isTrue);
      expect(scores.first, lessThan(0.5));
    });

    test('supports manual add, pin ordering, single delete, and forgetAll', () async {
      var fakeNow = DateTime(2026, 11, 13, 9, 0);
      final controller = UserFactsController(clock: () => fakeNow);
      await controller.load();

      final first = (await controller.addManual('Prefers chamomile tea at night'))!;
      fakeNow = fakeNow.add(const Duration(minutes: 5));
      final second = (await controller.addManual('Prepares for algorithms finals'))!;
      // Both manual adds are pinned; newest updated first.
      expect(controller.facts.first.id, second.id);

      // Unpin second -> pinned (first) moves ahead.
      await controller.togglePin(second.id);
      expect(controller.facts.first.id, first.id);

      await controller.deleteFact(first.id);
      expect(controller.facts.map((f) => f.id).toList(), [second.id]);

      await controller.forgetAll();
      expect(controller.isEmpty, isTrue);
    });
  });

  group('CompanionMemoryContext + WhatSolRemembersPage with UserFacts', () {
    test('gates user_facts & identity_summary behind profileSnippet consent', () async {
      final consent = ConsentController(repository: InMemoryConsentRepository());
      await consent.load();
      final profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();
      final moments = MomentsController(repository: InMemoryMomentRepository());
      await moments.load();
      final userFacts = UserFactsController();
      await userFacts.load();
      await userFacts.addManual('Lives with a cat named Nori');
      await userFacts.setIdentitySummary('They live with a cat named Nori.');

      final memory = CompanionMemoryContext(
        consent: consent,
        profile: profile,
        moments: moments,
        userFacts: userFacts,
        sessions: () => const [],
        themes: () => const [],
      );

      // Even with memoryMoments granted, user_facts stays blocked without profileSnippet.
      await consent.grant(ConsentKey.memoryMoments);
      expect(memory.payload(), isNull);

      await consent.grant(ConsentKey.profileSnippet);
      final payload = memory.payload()!;
      expect(payload['identity_summary'], 'They live with a cat named Nori.');
      expect(payload['user_facts'], ['Lives with a cat named Nori']);
      expect((payload['user_facts_recency'] as List).length, 1);
    });

    testWidgets('shows learned portrait/facts and lets user delete items in WhatSolRemembersPage', (tester) async {
      final consent = ConsentController(repository: InMemoryConsentRepository());
      await consent.load();
      final profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();
      final moments = MomentsController(repository: InMemoryMomentRepository());
      await moments.load();
      final userFacts = UserFactsController();
      await userFacts.load();
      final fact = (await userFacts.addManual('Walks outside during exam breaks'))!;
      await userFacts.setIdentitySummary('They take walks outside during exam breaks.');

      final memory = CompanionMemoryContext(
        consent: consent,
        profile: profile,
        moments: moments,
        userFacts: userFacts,
        sessions: () => const [],
        themes: () => const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WhatSolRemembersPage(
            moments: moments,
            memory: memory,
            consent: consent,
            profileController: profile,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('user-facts-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('user-identity-summary')), findsOneWidget);
      expect(find.text('Walks outside during exam breaks'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -320));
      await tester.pumpAndSettle();
      final deleteBtn = find.byKey(ValueKey('delete-user-fact-${fact.id}'));
      await tester.ensureVisible(deleteBtn);
      await tester.pumpAndSettle();
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(userFacts.facts, isEmpty);
      expect(find.byKey(const ValueKey('user-identity-summary')), findsNothing);
    });
  });
}
