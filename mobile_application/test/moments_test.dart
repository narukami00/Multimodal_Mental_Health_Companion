import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/shared_preferences_moment_repository.dart';
import 'package:solace_mobile/domain/memory/moment_extractor.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';

MomentCandidate _entry(String text, {String? ref = 'r1', String? mood}) => MomentCandidate(
  text: text,
  source: MomentSource.journal,
  createdAt: DateTime(2026, 10, 20, 18),
  sourceRef: ref,
  moodWord: mood,
);

void main() {
  const extractor = RuleBasedMomentExtractor();

  group('the rule-based extractor', () {
    test('finds a sentence where something good happened, in their words', () async {
      final proposal = await extractor.extract(
        _entry('Work was long. I had coffee with a friend and it was really nice. Tired now.'),
      );
      expect(proposal!.text, 'I had coffee with a friend and it was really nice.');
      expect(proposal.tone, MomentTone.warm);
      expect(proposal.occurredOn, '2026-10-20');
    });

    test('carries the mood word they chose and keeps it separate from any model reading', () async {
      final proposal = await extractor.extract(
        _entry('We went for a walk by the river and I felt calmer.', mood: 'Steady'),
      );
      expect(proposal!.moodWord, 'Steady');
      expect(proposal.emotionClass, isNull);
    });

    test('needs both something that happened and a warm word', () async {
      expect(await extractor.extract(_entry('I felt good today, no idea why.')), isNull);
      expect(await extractor.extract(_entry('I went to the shop on the corner today.')), isNull);
    });

    test('skips questions, and negated or hard sentences', () async {
      expect(await extractor.extract(_entry('Did I have a good time with them at the park?')), isNull);
      expect(await extractor.extract(_entry('I went out but it was not nice at all.')), isNull);
      expect(await extractor.extract(_entry('Honestly I did not enjoy the dinner we had.')), isNull);
    });

    test('never proposes anything sensitive, even when it sounds warm', () async {
      for (final text in [
        'I had a good cry at the funeral and felt lighter afterwards.',
        'I went to the hospital and the nurse was really nice to me.',
        'I paid off some of my debt and felt so relieved today.',
        'I thought about suicide but I called a friend and felt better.',
      ]) {
        expect(await extractor.extract(_entry(text)), isNull, reason: text);
      }
    });

    test('sensitive matching is by whole word', () {
      expect(momentIsSensitive('I saw my therapist and had a nice chat'), isFalse);
      expect(momentIsSensitive('I felt dead tired'), isTrue);
    });

    test('shortens a long sentence without rewording it', () async {
      final long =
          'I had a lovely long afternoon with my sister and we walked and talked '
          'and laughed about everything that happened over the whole year, and '
          'then we cooked together and it was so good.';
      final proposal = await extractor.extract(_entry(long));
      expect(proposal!.text.length, lessThanOrEqualTo(MemoryMoment.maxLength));
      expect(proposal.text.endsWith('…'), isTrue);
      expect(long.startsWith(proposal.text.substring(0, proposal.text.length - 1)), isTrue);
    });
  });

  group('the controller', () {
    late InMemoryMomentRepository repository;
    late MomentsController controller;
    var now = DateTime(2026, 10, 20, 18);

    setUp(() async {
      now = DateTime(2026, 10, 20, 18);
      repository = InMemoryMomentRepository();
      controller = MomentsController(repository: repository, clock: () => now);
      await controller.load();
    });

    const warm = 'I had coffee with a friend and it was really nice.';

    test('a proposal waits as pending and is not used by anything', () async {
      final moment = await controller.consider(_entry(warm));

      expect(moment!.state, MomentState.pending);
      expect(controller.pending, hasLength(1));
      expect(controller.confirmed, isEmpty);
      expect(controller.forSol, isEmpty);
      expect(controller.forInsights, isEmpty);
    });

    test('yes keeps it, and a warm confirmed moment reaches Insights and Sol', () async {
      final moment = (await controller.consider(_entry(warm)))!;
      await controller.confirm(moment.id);

      expect(controller.confirmed.single.text, warm);
      expect(controller.forInsights, hasLength(1));
      expect(controller.forSol, hasLength(1));
    });

    test('they can reword it when confirming, and that is recorded', () async {
      final moment = (await controller.consider(_entry(warm)))!;
      await controller.confirm(moment.id, text: 'Coffee with Sam was lovely.');

      expect(controller.confirmed.single.text, 'Coffee with Sam was lovely.');
      expect(controller.confirmed.single.editedByUser, isTrue);
    });

    test('no deletes it and leaves only a tombstone', () async {
      final moment = (await controller.consider(_entry(warm)))!;
      await controller.delete(moment.id);

      expect(controller.all, isEmpty);
      final stones = await repository.tombstones();
      expect(stones.single.id, moment.id);
      expect(stones.single.toMap().containsKey('text'), isFalse);
    });

    test('hidden moments are used by nothing and can come back', () async {
      final moment = (await controller.consider(_entry(warm)))!;
      await controller.confirm(moment.id);
      await controller.hide(moment.id);

      expect(controller.forSol, isEmpty);
      expect(controller.forInsights, isEmpty);
      expect(controller.hidden, hasLength(1));

      await controller.unhide(moment.id);
      expect(controller.forSol, hasLength(1));
    });

    test('hard moments never reach Insights, but can still inform Sol', () async {
      final moment = (await controller.addManual('Hard conversation with my manager.', tone: MomentTone.heavy))!;

      expect(moment.isConfirmed, isTrue);
      expect(controller.forInsights, isEmpty);
      expect(controller.forSol, hasLength(1));
    });

    test('the same entry is looked at once, and the same moment is not asked twice', () async {
      await controller.consider(_entry(warm));
      expect(await controller.consider(_entry(warm)), isNull);
      expect(
        await controller.consider(_entry(warm.toUpperCase(), ref: 'r2')),
        isNull,
      );
      expect(controller.pending, hasLength(1));
    });

    test('no more than three questions wait at once', () async {
      for (var i = 0; i < 5; i++) {
        await controller.consider(
          _entry('I went to the market number $i with a friend and it was so nice.', ref: 'r$i'),
        );
        now = now.add(const Duration(minutes: 1));
      }
      expect(controller.pending, hasLength(MomentsController.maxPending));
    });

    test('an unanswered question fades away after two weeks', () async {
      await controller.consider(_entry(warm));
      now = now.add(const Duration(days: 15));
      await controller.load();

      expect(controller.pending, isEmpty);
    });

    test('Sol is told only the most recent few', () async {
      for (var i = 0; i < 8; i++) {
        final m = await controller.addManual('Good thing number $i.');
        now = now.add(const Duration(minutes: 1));
        expect(m, isNotNull);
      }
      expect(controller.forSol, hasLength(MomentsController.maxForSol));
      expect(controller.forSol.first.text, 'Good thing number 7.');
    });

    test('deleting an entry takes its moments with it', () async {
      final moment = (await controller.consider(_entry(warm, ref: 'entry-9')))!;
      await controller.confirm(moment.id);
      await controller.deleteForSource('entry-9');

      expect(controller.all, isEmpty);
    });

    test('deleteAll clears moments and tombstones', () async {
      final moment = (await controller.consider(_entry(warm)))!;
      await controller.delete(moment.id);
      await controller.deleteAll();

      expect(await repository.tombstones(), isEmpty);
    });
  });

  group('storage', () {
    test('survives a restart, and drops unreadable records', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesMomentRepository(prefs);
      final controller = MomentsController(repository: repository);
      await controller.load();
      final moment = (await controller.addManual('A good walk by the river.'))!;

      final reopened = MomentsController(repository: SharedPreferencesMomentRepository(prefs));
      await reopened.load();
      expect(reopened.confirmed.single.id, moment.id);

      await prefs.setString('memory.moments', 'not json');
      final broken = MomentsController(repository: SharedPreferencesMomentRepository(prefs));
      await broken.load();
      expect(broken.all, isEmpty);
    });

    test('a damaged state reads as pending, never as something Sol is told', () {
      final moment = MemoryMoment.fromMap({
        'id': 'a',
        'text': 'A good day.',
        'createdAt': DateTime(2026, 10, 1).toIso8601String(),
        'occurredOn': '2026-10-01',
        'state': 'banana',
      });
      expect(moment!.state, MomentState.pending);
    });
  });
}
