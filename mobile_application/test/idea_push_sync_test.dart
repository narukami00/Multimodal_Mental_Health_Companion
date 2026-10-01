import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/features/suggestions/idea_push_sync.dart';

void main() {
  final now = DateTime(2026, 9, 22, 8);
  const on = UserProfile(ideaPushEnabled: true);

  test('never touches the OS for someone who never turned pushes on', () async {
    final calls = <List<DateTime>>[];
    final sync = IdeaPushSync(sink: (t) async {
      calls.add(t);
      return true;
    });

    await sync.sync(
      profile: const UserProfile(),
      history: const [],
      lastCheckInAt: now,
      now: now,
    );

    expect(calls, isEmpty);
  });

  test('schedules once, and again only when the plan moves', () async {
    final calls = <List<DateTime>>[];
    final sync = IdeaPushSync(sink: (t) async {
      calls.add(t);
      return true;
    });

    Future<void> run({List<SuggestionRecord> history = const []}) =>
        sync.sync(profile: on, history: history, lastCheckInAt: now, now: now);

    await run();
    await run();
    expect(calls, hasLength(1));
    expect(calls.single, hasLength(3));

    // Today's idea has now been shown, so today's push drops out.
    await run(
      history: [
        SuggestionRecord(
          id: 'a',
          activityId: 'x',
          shownAt: now,
          contextTags: const [],
          proactive: true,
        ),
      ],
    );
    expect(calls, hasLength(2));
    expect(calls.last, hasLength(2));
  });

  test('clears what was scheduled when pushes are turned off', () async {
    final calls = <List<DateTime>>[];
    final sync = IdeaPushSync(sink: (t) async {
      calls.add(t);
      return true;
    });

    await sync.sync(profile: on, history: const [], lastCheckInAt: now, now: now);
    await sync.sync(
      profile: const UserProfile(),
      history: const [],
      lastCheckInAt: now,
      now: now,
    );

    expect(calls.last, isEmpty);
  });
}
