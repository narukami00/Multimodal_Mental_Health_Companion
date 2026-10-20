import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/mood_change.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';

class _Library implements ActivityLibraryRepository {
  const _Library(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

Activity _activity(String id) => Activity(
  id: id,
  title: 'Idea $id',
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

SuggestionController _controller([List<String> ids = const ['a']]) => SuggestionController(
  libraryRepository: _Library([for (final id in ids) _activity(id)]),
  suggestionRepository: InMemorySuggestionRepository(),
);

const _context = RecommendationContext(profileAgeDays: 20);

SessionRecord _checkIn(DateTime at, String mood) =>
    SessionRecord(id: at.microsecondsSinceEpoch.toString(), createdAt: at, mode: CaptureMode.text, mood: mood);

SuggestionRecord _record({DateTime? shownAt, DateTime? acceptedAt, String? moodBefore}) => SuggestionRecord(
  id: 'r',
  activityId: 'a',
  shownAt: shownAt ?? DateTime(2026, 10, 1, 9),
  contextTags: const [],
  acceptedAt: acceptedAt,
  moodBefore: moodBefore,
);

void main() {
  final base = DateTime(2026, 10, 1, 15);

  group('the record', () {
    test('keeps when it was started and finished, and reads old records as having neither', () {
      final record = _record(acceptedAt: DateTime(2026, 10, 1, 9, 5)).copyWith(completedAt: DateTime(2026, 10, 1, 9, 40));
      final back = SuggestionRecord.fromMap(Map<String, dynamic>.from(record.toMap()));

      expect(back.acceptedAt, DateTime(2026, 10, 1, 9, 5));
      expect(back.completedAt, DateTime(2026, 10, 1, 9, 40));

      final old = Map<String, dynamic>.from(record.toMap())
        ..remove('acceptedAt')
        ..remove('completedAt');
      expect(SuggestionRecord.fromMap(old).acceptedAt, isNull);
      expect(SuggestionRecord.fromMap(old).completedAt, isNull);
    });

    test('a mood before can be cleared, which copyWith alone could not do', () {
      final record = _record(moodBefore: 'Wobbly');
      expect(record.copyWith(moodAfter: 'Steady').moodBefore, 'Wobbly');
      expect(record.copyWith(clearMoodBefore: true).moodBefore, isNull);
    });
  });

  group('the mood before', () {
    test('is a check-in from the last few hours, not from half a day ago', () {
      expect(moodBeforeFor(shownAt: base, sessions: [_checkIn(base.subtract(const Duration(hours: 2)), 'Bright')]), 'Bright');
      expect(moodBeforeFor(shownAt: base, sessions: [_checkIn(base.subtract(const Duration(hours: 4)), 'Bright')]), isNull);
    });

    test('the recommender keeps its own, wider window for how the person is doing around now', () {
      final sessions = [_checkIn(base.subtract(const Duration(hours: 6)), 'Tender')];
      expect(moodBeforeFor(shownAt: base, sessions: sessions), isNull);
      expect(moodBeforeFor(shownAt: base, sessions: sessions, window: moodContextWindow), 'Tender');
    });

    test('is read as of when they started, not when the card appeared', () {
      // Shown in the morning, started in the evening: the afternoon check-in is what counts.
      final record = _record(shownAt: DateTime(2026, 10, 1, 8), acceptedAt: DateTime(2026, 10, 1, 18));
      final sessions = [_checkIn(DateTime(2026, 10, 1, 17), 'Quiet'), _checkIn(DateTime(2026, 10, 1, 8, 10), 'Bright')];

      expect(moodBeforeForRecord(record: record, sessions: sessions), 'Quiet');
    });

    test('an idea answered the older one-step way is still read as of when it was shown', () {
      final record = _record(shownAt: DateTime(2026, 10, 1, 8));
      final sessions = [_checkIn(DateTime(2026, 10, 1, 7), 'Bright'), _checkIn(DateTime(2026, 10, 1, 17), 'Quiet')];

      expect(moodBeforeForRecord(record: record, sessions: sessions), 'Bright');
    });

    test('what they said when asked directly wins over what a check-in implies', () {
      final record = _record(acceptedAt: base, moodBefore: 'Wobbly');
      final sessions = [_checkIn(base.subtract(const Duration(minutes: 10)), 'Bright')];

      expect(moodBeforeForRecord(record: record, sessions: sessions), 'Wobbly');
    });

    test('before and after only pair when it was finished within a few hours of starting', () {
      final started = _record(acceptedAt: base);
      expect(moodsPair(started, base.add(const Duration(hours: 1))), isTrue);
      expect(moodsPair(started, base.add(const Duration(hours: 5))), isFalse);
      expect(moodsPair(_record(), base.add(const Duration(days: 1))), isTrue, reason: 'no start time: the older flow');
    });
  });

  group('asking for an idea', () {
    test('another idea never repeats one already seen this sitting', () async {
      final controller = _controller(['a', 'b', 'c']);
      await controller.load();
      await controller.warmUp();

      final first = controller.peek(profile: const UserProfile(), context: _context)!;
      final second = controller.peek(profile: const UserProfile(), context: _context, excludeIds: {first.activity.id})!;
      final third = controller.peek(
        profile: const UserProfile(),
        context: _context,
        excludeIds: {first.activity.id, second.activity.id},
      )!;

      expect({first.activity.id, second.activity.id, third.activity.id}, hasLength(3));
      expect(
        controller.peek(profile: const UserProfile(), context: _context, excludeIds: {'a', 'b', 'c'}),
        isNull,
        reason: 'nothing left to offer is no answer, not a repeat',
      );
      expect(controller.history, isEmpty, reason: 'looking is never written down');
    });

    test('an idea asked for again the same day is its own try', () async {
      final controller = _controller();
      await controller.load();
      await controller.warmUp();
      final recommendation = controller.peek(profile: const UserProfile(), context: _context)!;

      final one = await controller.commit(recommendation, context: _context, fresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final two = await controller.commit(recommendation, context: _context, fresh: true);

      expect(one.id, isNot(two.id));
      expect(controller.history, hasLength(2));
      expect(one.proactive, isFalse, reason: "asked for, so it never uses up the day's unasked slot");
    });
  });

  group('doing it', () {
    Future<(SuggestionController, String)> started({DateTime? at, String? moodBefore}) async {
      final controller = _controller();
      await controller.load();
      await controller.warmUp();
      final recommendation = controller.peek(profile: const UserProfile(), context: _context)!;
      final record = await controller.commit(recommendation, context: _context, fresh: true);
      await controller.startDoing(record.id, moodBefore: moodBefore, now: at);
      return (controller, record.id);
    }

    test('stays in progress until it is finished, even after leaving the app for a while', () async {
      final at = DateTime(2026, 10, 1, 10);
      final (controller, id) = await started(at: at, moodBefore: 'Quiet');

      expect(controller.doingNow(now: at.add(const Duration(hours: 5)))?.id, id);
      expect(controller.doingNow(now: at.add(const Duration(hours: 5)))?.moodBefore, 'Quiet');
    });

    test('quietly stops being in progress if it was simply left, and nothing is concluded from that', () async {
      final at = DateTime(2026, 10, 1, 10);
      final (controller, id) = await started(at: at);

      expect(controller.doingNow(now: at.add(SuggestionController.doingExpiry)), isNull);
      final record = controller.history.single;
      expect(record.id, id);
      expect(record.done, isNull);
      expect(record.status, SuggestionStatus.shown);
    });

    test('finishing it records when, and it is no longer in progress', () async {
      final at = DateTime(2026, 10, 1, 10);
      final (controller, id) = await started(at: at);
      final finished = at.add(const Duration(minutes: 25));

      await controller.completeRecord(id, now: finished);

      final record = controller.history.single;
      expect(record.done, isTrue);
      expect(record.status, SuggestionStatus.completed);
      expect(record.completedAt, finished);
      expect(controller.doingNow(now: finished), isNull);
    });

    test('"something came up" ends it with no verdict, and it is no longer in progress', () async {
      final at = DateTime(2026, 10, 1, 10);
      final (controller, id) = await started(at: at);

      await controller.dismissRecord(id, reason: SuggestionSkipReason.notNow);

      final record = controller.history.single;
      expect(record.done, isNull);
      expect(record.skipReason, SuggestionSkipReason.notNow);
      expect(controller.doingNow(now: at.add(const Duration(minutes: 5))), isNull);
    });

    test('the latest one started is the one in progress', () async {
      final controller = _controller(['a', 'b']);
      await controller.load();
      await controller.warmUp();
      final a = await controller.commit(
        controller.peek(profile: const UserProfile(), context: _context)!,
        context: _context,
        fresh: true,
        now: DateTime(2026, 10, 1, 9),
      );
      await controller.startDoing(a.id, now: DateTime(2026, 10, 1, 9));
      final b = await controller.commit(
        controller.peek(profile: const UserProfile(), context: _context, excludeIds: {a.activityId})!,
        context: _context,
        fresh: true,
        now: DateTime(2026, 10, 1, 9, 30),
      );
      await controller.startDoing(b.id, now: DateTime(2026, 10, 1, 9, 30));

      expect(controller.doingNow(now: DateTime(2026, 10, 1, 10))?.id, b.id);
    });

    test('before and after are kept as a pair when it was finished soon after starting', () async {
      final at = DateTime(2026, 10, 1, 10);
      final (controller, id) = await started(at: at, moodBefore: 'Wobbly');
      await controller.completeRecord(id, now: at.add(const Duration(minutes: 30)));

      await controller.recordMoodAfter(recordId: id, moodAfter: 'Steady', moodBefore: 'Wobbly');

      final record = controller.history.single;
      expect(record.moodBefore, 'Wobbly');
      expect(record.moodAfter, 'Steady');
    });

    test('and not as a pair when it was finished hours later (the after is still kept as how they felt)', () async {
      final at = DateTime(2026, 10, 1, 10);
      final (controller, id) = await started(at: at, moodBefore: 'Wobbly');
      await controller.completeRecord(id, now: at.add(const Duration(hours: 6)));

      await controller.recordMoodAfter(recordId: id, moodAfter: 'Steady', moodBefore: 'Wobbly');

      final record = controller.history.single;
      expect(record.moodAfter, 'Steady');
      expect(record.moodBefore, isNull);
      expect(moodChange(record.moodBefore, record.moodAfter), isNull, reason: 'so it can teach nothing about the idea');
    });
  });
}
