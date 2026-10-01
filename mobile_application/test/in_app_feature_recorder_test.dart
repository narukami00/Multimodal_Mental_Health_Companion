import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/features/footprint/in_app_feature_recorder.dart';

SessionRecord _session(DateTime at, {String? mood, String? text}) =>
    SessionRecord(
      id: at.microsecondsSinceEpoch.toString(),
      createdAt: at,
      mode: CaptureMode.text,
      mood: mood,
      text: text,
    );

void main() {
  final now = DateTime(2026, 10, 10, 15);
  late InMemoryDailyFeaturesRepository repository;
  late List<SessionRecord> sessions;
  late UserProfile profile;

  InAppFeatureRecorder build({Duration debounce = Duration.zero}) =>
      InAppFeatureRecorder(
        repository: repository,
        sessions: () => sessions,
        conversations: () => const <ChatConversationRecord>[],
        profile: () => profile,
        clock: () => now,
        debounce: debounce,
      );

  setUp(() {
    repository = InMemoryDailyFeaturesRepository();
    sessions = [];
    profile = UserProfile(firstRunAt: DateTime(2026, 9, 1));
  });

  test('records a row for the day it is asked about', () async {
    sessions = [_session(DateTime(2026, 10, 10, 9), mood: 'Bright')];

    await build().recordDay(DateTime(2026, 10, 10));

    final rows = await repository.loadAll();
    expect(rows.single.dayKey, '2026-10-10');
    expect(rows.single.checkInCount, 1);
    expect(rows.single.sources, {'inApp'});
  });

  test('recording again after a change updates the row in place', () async {
    final recorder = build();
    await recorder.recordDay(DateTime(2026, 10, 10));
    sessions = [_session(DateTime(2026, 10, 10, 9))];
    await recorder.recordDay(DateTime(2026, 10, 10));

    final rows = await repository.loadAll();
    expect(rows, hasLength(1));
    expect(rows.single.checkInCount, 1);
  });

  test('keeps device-usage fields another source already stored', () async {
    await repository.upsert(
      const DailyFeatures(
        dayKey: '2026-10-10',
        sources: {'usage'},
        screenOnMinutes: 180,
      ),
    );

    await build().recordDay(DateTime(2026, 10, 10));

    final row = (await repository.loadAll()).single;
    expect(row.screenOnMinutes, 180);
    expect(row.checkInCount, 0);
    expect(row.sources, {'usage', 'inApp'});
  });

  test('recordRecent covers today and the days before it', () async {
    await build().recordRecent(days: 3);

    expect((await repository.loadAll()).map((row) => row.dayKey), [
      '2026-10-08',
      '2026-10-09',
      '2026-10-10',
    ]);
  });

  test('does not record days before the app was first opened', () async {
    profile = UserProfile(firstRunAt: DateTime(2026, 10, 9, 20));

    await build().recordRecent(days: 3);

    expect((await repository.loadAll()).map((row) => row.dayKey), [
      '2026-10-09',
      '2026-10-10',
    ]);
  });

  test('the reminder only counts while it is switched on', () async {
    sessions = [_session(DateTime(2026, 10, 10, 21, 0))];

    profile = UserProfile(
      firstRunAt: DateTime(2026, 9, 1),
      reminderEnabled: false,
    );
    await build().recordDay(DateTime(2026, 10, 10));
    expect((await repository.loadAll()).single.checkInLatencyMinutes, isNull);

    profile = UserProfile(
      firstRunAt: DateTime(2026, 9, 1),
      reminderEnabled: true,
      reminderMinutes: 20 * 60 + 30,
    );
    await build().recordDay(DateTime(2026, 10, 10));
    expect((await repository.loadAll()).single.checkInLatencyMinutes, 30);
  });

  test('prune keeps exactly the chosen number of days', () async {
    for (var day = 1; day <= 10; day++) {
      await repository.upsert(
        DailyFeatures(dayKey: '2026-10-${day.toString().padLeft(2, '0')}'),
      );
    }
    profile = UserProfile(
      firstRunAt: DateTime(2026, 9, 1),
      featureRetentionDays: 7,
    );

    final removed = await build().prune();

    expect(removed, 3);
    final kept = (await repository.loadAll()).map((row) => row.dayKey);
    expect(kept.first, '2026-10-04');
    expect(kept.last, '2026-10-10');
  });

  group('scheduleToday', () {
    testWidgets('waits for activity to settle and then writes once', (
      tester,
    ) async {
      final recorder = build(debounce: const Duration(seconds: 2));

      recorder.scheduleToday();
      await tester.pump(const Duration(seconds: 1));
      recorder.scheduleToday();
      await tester.pump(const Duration(seconds: 1));
      recorder.scheduleToday();
      await tester.pump(const Duration(milliseconds: 1500));

      // Still inside the debounce window of the last call.
      expect(await repository.loadAll(), isEmpty);

      await tester.pump(const Duration(seconds: 1));
      final rows = await repository.loadAll();
      expect(rows, hasLength(1));
      expect(rows.single.dayKey, '2026-10-10');
      recorder.dispose();
    });

    testWidgets('dispose cancels a write that has not happened yet', (
      tester,
    ) async {
      final recorder = build(debounce: const Duration(seconds: 2));

      recorder.scheduleToday();
      recorder.dispose();
      await tester.pump(const Duration(seconds: 5));

      expect(await repository.loadAll(), isEmpty);
    });
  });
}
