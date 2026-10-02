import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/footprint/usage_collection_runner.dart';
import 'package:solace_mobile/features/footprint/usage_recorder.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

/// Plays back a fixed list of events, and remembers what it was asked for.
class _FakeCollector implements UsageCollectorService {
  _FakeCollector(this.script);

  final List<UsageEvent> script;
  bool access = true;
  final queries = <({DateTime from, DateTime to})>[];
  final described = <String, AppDescription>{
    'chat.app': const AppDescription(label: 'Chat'),
    'feed.app': const AppDescription(label: 'Feed', category: 'social'),
  };

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<bool> openAccessSettings() async => true;

  @override
  Future<List<UsageEvent>> events({
    required DateTime from,
    required DateTime to,
  }) async {
    queries.add((from: from, to: to));
    return [
      for (final event in script)
        if (!event.time.isBefore(from) && event.time.isBefore(to)) event,
    ];
  }

  @override
  Future<Map<String, AppDescription>> describeApps(
    List<String> packages,
  ) async => {
    for (final package in packages)
      if (described[package] != null) package: described[package]!,
  };
}

UsageEvent _on(DateTime at) =>
    UsageEvent(time: at, type: UsageEventType.screenOn);
UsageEvent _off(DateTime at) =>
    UsageEvent(time: at, type: UsageEventType.screenOff);
UsageEvent _open(DateTime at, String pkg) =>
    UsageEvent(time: at, type: UsageEventType.appForeground, package: pkg);

DateTime _d(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

/// Three days of use: the evening of the 1st, all of the 2nd, the morning of the
/// 3rd.
List<UsageEvent> _script() => [
  _on(_d(1, 22)),
  _open(_d(1, 22), 'feed.app'),
  _off(_d(1, 23, 30)),
  _on(_d(2, 7)),
  _open(_d(2, 7), 'chat.app'),
  _off(_d(2, 7, 30)),
  _on(_d(2, 20)),
  _open(_d(2, 20), 'feed.app'),
  _off(_d(2, 21)),
  _on(_d(3, 8)),
  _open(_d(3, 8), 'chat.app'),
  _off(_d(3, 8, 30)),
];

void main() {
  late _FakeCollector collector;
  late InMemoryDailyFeaturesRepository repository;
  var collecting = true;
  var keepNames = false;
  var profile = const UserProfile();
  var now = _d(3, 12);

  UsageRecorder build() => UsageRecorder(
    collector: collector,
    repository: repository,
    profile: () => profile,
    isCollecting: () => collecting,
    keepsAppNames: () => keepNames,
    clock: () => now,
  );

  setUp(() {
    collector = _FakeCollector(_script());
    repository = InMemoryDailyFeaturesRepository();
    collecting = true;
    keepNames = false;
    profile = const UserProfile();
    now = _d(3, 12);
  });

  group('collectDay', () {
    test('reduces a finished day and marks it complete', () async {
      expect(await build().collectDay(_d(2, 0)), isTrue);

      final row = (await repository.loadAll()).single;
      expect(row.dayKey, '2026-10-02');
      expect(row.screenOnMinutes, 90);
      expect(row.sessionCount, 2);
      expect(row.sources, containsAll(['usage', usageFinalSource]));
    });

    test('a day still in progress is not marked complete', () async {
      await build().collectDay(_d(3, 0));

      final row = (await repository.loadAll()).single;
      expect(row.dayKey, '2026-10-03');
      expect(row.screenOnMinutes, 30);
      expect(row.sources, {'usage'});
    });

    test('adds the night\'s sleep estimate to the morning it ended on', () async {
      await build().collectDay(_d(2, 0));

      final row = (await repository.loadAll()).single;
      // Phone down 23:30, picked up 07:00.
      expect(row.estimatedSleepMinutes, 450);
      expect(row.estimatedSleepStartMinute, 23 * 60 + 30);
    });

    test('uses the stated sleep hours when there are some', () async {
      await build().collectDay(_d(2, 0));
      expect((await repository.loadAll()).single.screenMinutesInSleepWindow, isNull);

      repository = InMemoryDailyFeaturesRepository();
      profile = const UserProfile(
        sleepStartMinutes: 23 * 60,
        sleepEndMinutes: 7 * 60,
      );
      await build().collectDay(_d(2, 0));
      // 23:00 to 23:30 on the 1st does not count for the 2nd; 20:00 to 21:00 is
      // before bedtime. Nothing on the 2nd falls inside the window.
      expect((await repository.loadAll()).single.screenMinutesInSleepWindow, 0);
    });

    test('groups foreground time by category', () async {
      await build().collectDay(_d(2, 0));

      final row = (await repository.loadAll()).single;
      // 30 minutes of chat (other) and 60 of the feed (social).
      expect(row.categoryMinutes, {'other': 30, 'social': 60});
    });

    test('app names are kept only when agreed to', () async {
      await build().collectDay(_d(2, 0));
      expect((await repository.loadAll()).single.topApps, isNull);

      keepNames = true;
      await build().collectDay(_d(2, 0));
      final names = (await repository.loadAll()).single.topApps!.map((a) => a.name);
      expect(names, ['Feed', 'Chat']);
    });

    test('keeps in-app fields written by another source', () async {
      await repository.upsert(
        const DailyFeatures(
          dayKey: '2026-10-02',
          sources: {'inApp'},
          checkInCount: 2,
          journalWordCount: 80,
        ),
      );

      await build().collectDay(_d(2, 0));

      final row = (await repository.loadAll()).single;
      expect(row.checkInCount, 2);
      expect(row.journalWordCount, 80);
      expect(row.screenOnMinutes, 90);
      expect(row.sources, containsAll(['inApp', 'usage']));
    });

    test('reads nothing when not collecting', () async {
      collecting = false;

      expect(await build().collectDay(_d(2, 0)), isFalse);
      expect(collector.queries, isEmpty);
      expect(await repository.loadAll(), isEmpty);
    });

    test('no events at all is no data, never a day of zeros', () async {
      expect(await build().collectDay(_d(1, 0).subtract(const Duration(days: 9))), isFalse);
      expect(await repository.loadAll(), isEmpty);
    });

    test('a day that has not started has nothing to read', () async {
      expect(await build().collectDay(_d(4, 0)), isFalse);
      expect(collector.queries, isEmpty);
    });

    test('looks back to noon the day before for state carried in', () async {
      await build().collectDay(_d(2, 0));

      expect(collector.queries.single.from, _d(1, 12));
      expect(collector.queries.single.to, _d(3, 0));
    });
  });

  group('catchUp', () {
    test('fills in the days that have data, oldest first', () async {
      final written = await build().catchUp();

      expect(written, 3);
      expect((await repository.loadAll()).map((r) => r.dayKey), [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
      ]);
    });

    test('does not read finished days again', () async {
      await build().catchUp();
      collector.queries.clear();

      await build().catchUp();

      final fromDays = collector.queries.map((q) => q.from.day).toSet();
      // Days with no data are retried, today is re-read, finished days are not.
      expect(fromDays, isNot(contains(30)));
      expect(
        collector.queries.where((q) => q.to == _d(3, 12)).length,
        1,
        reason: 'today is read again exactly once',
      );
      expect(
        collector.queries.any((q) => q.to == _d(2, 0)),
        isFalse,
        reason: 'the 1st was already complete',
      );
      expect(
        collector.queries.any((q) => q.to == _d(3, 0)),
        isFalse,
        reason: 'the 2nd was already complete',
      );
    });

    test('a day first read while still in progress is completed later', () async {
      now = _d(2, 12);
      await build().catchUp();
      expect(
        (await repository.loadAll()).last.sources,
        isNot(contains(usageFinalSource)),
      );

      now = _d(3, 12);
      await build().catchUp();

      final second = (await repository.loadAll()).firstWhere(
        (row) => row.dayKey == '2026-10-02',
      );
      expect(second.sources, contains(usageFinalSource));
      expect(second.screenOnMinutes, 90);
    });

    test('does nothing when not collecting', () async {
      collecting = false;

      expect(await build().catchUp(), 0);
      expect(collector.queries, isEmpty);
    });

    test('only reaches back the requested number of days', () async {
      await build().catchUp(days: 2);

      expect(collector.queries, hasLength(2));
    });
  });

  group('UsageCollectionRunner', () {
    late ConsentController consent;
    late PhonePatternsController patterns;

    setUp(() async {
      consent = ConsentController(repository: InMemoryConsentRepository());
      await consent.load();
      patterns = PhonePatternsController(
        consent: consent,
        collector: collector,
        repository: repository,
      );
    });

    UsageCollectionRunner runner() => UsageCollectionRunner(
      patterns: patterns,
      recorder: UsageRecorder(
        collector: collector,
        repository: repository,
        profile: () => profile,
        isCollecting: () => patterns.isCollecting,
        keepsAppNames: () => patterns.keepsAppNames,
        clock: () => now,
      ),
    );

    test('reads nothing until phone patterns is on', () async {
      await runner().run();

      expect(collector.queries, isEmpty);
    });

    test('catches up once both consent and access are there', () async {
      await consent.grant(ConsentKey.usageFootprint);

      await runner().run();

      expect((await repository.loadAll()), isNotEmpty);
    });

    test('Android access without consent still reads nothing', () async {
      collector.access = true;

      await runner().run();

      expect(collector.queries, isEmpty);
    });

    test('tells listeners when new days have been written', () async {
      await consent.grant(ConsentKey.usageFootprint);
      var changes = 0;
      patterns.addListener(() => changes++);

      await runner().run();
      final afterFirst = changes;
      expect(afterFirst, greaterThan(0));
      expect(await repository.loadAll(), isNotEmpty);
    });

    test('says nothing when nothing was written', () async {
      await consent.grant(ConsentKey.usageFootprint);
      collector.script.clear();
      await patterns.refresh();
      var changes = 0;
      patterns.addListener(() => changes++);

      await runner().run();

      expect(changes, 0);
    });

    test('a failure is swallowed rather than reaching the person', () async {
      await consent.grant(ConsentKey.usageFootprint);
      final failing = UsageCollectionRunner(
        patterns: patterns,
        recorder: UsageRecorder(
          collector: _ThrowingCollector(),
          repository: repository,
          profile: () => profile,
          isCollecting: () => true,
          keepsAppNames: () => false,
          clock: () => now,
        ),
      );

      await failing.run();
    });

    testWidgets('switching it on backfills straight away', (tester) async {
      final started = runner()..start();
      addTearDown(started.dispose);
      await patterns.refresh();
      expect(collector.queries, isEmpty);

      await consent.grant(ConsentKey.usageFootprint);
      await tester.pump();
      await tester.pump();

      expect(await repository.loadAll(), isNotEmpty);
    });

    testWidgets('returning to the app catches up', (tester) async {
      await consent.grant(ConsentKey.usageFootprint);
      await patterns.refresh();
      final started = runner()..start();
      addTearDown(started.dispose);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(collector.queries, isNotEmpty);
    });

    testWidgets('overlapping triggers fold into one more run', (tester) async {
      await consent.grant(ConsentKey.usageFootprint);
      await patterns.refresh();
      final started = runner();

      final first = started.run();
      final second = started.run();
      final third = started.run();
      await Future.wait([first, second, third]);

      // Seven days per pass; a pass for the first call and one folded re-run.
      // Never three concurrent passes.
      expect(collector.queries.length, lessThanOrEqualTo(14));
    });
  });
}

class _ThrowingCollector implements UsageCollectorService {
  @override
  Future<bool> hasAccess() async => true;

  @override
  Future<bool> openAccessSettings() async => true;

  @override
  Future<List<UsageEvent>> events({
    required DateTime from,
    required DateTime to,
  }) async => throw StateError('boom');

  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async =>
      throw StateError('boom');
}
