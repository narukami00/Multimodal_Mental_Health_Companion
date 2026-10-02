import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/data/contracts/daily_features_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/data/repositories/shared_preferences_daily_features_repository.dart';

DailyFeatures _usageDay(String key) => DailyFeatures(
  dayKey: key,
  sources: const {'usage'},
  screenOnMinutes: 212,
  unlockCount: 64,
  sessionCount: 51,
  longestSessionMinutes: 38,
  appSwitchRate: 14.5,
  hourlyActiveMinutes: List.generate(24, (hour) => hour == 22 ? 40 : 5),
  firstPickupMinute: 7 * 60 + 12,
  lastUseMinute: 23 * 60 + 40,
  estimatedSleepStartMinute: 23 * 60 + 55,
  estimatedSleepEndMinute: 7 * 60 + 5,
  estimatedSleepMinutes: 430,
  screenMinutesInSleepWindow: 18,
  lastUseDelayVsStatedBedtimeMinutes: 40,
  categoryMinutes: const {'social': 80, 'video': 60, 'other': 72},
);

void main() {
  group('DailyFeatures', () {
    test('a row with nothing collected says nothing, not zero', () {
      const row = DailyFeatures(dayKey: '2026-10-01');

      expect(row.screenOnMinutes, isNull);
      expect(row.hasUsage, isFalse);
      expect(row.toMap().keys, containsAll(['dayKey', 'schemaVersion']));
      expect(row.toMap().containsKey('screenOnMinutes'), isFalse);
    });

    test('round-trips every field', () {
      final row = _usageDay('2026-10-01').mergedWith(
        const DailyFeatures(
          dayKey: '2026-10-01',
          sources: {'inApp'},
          checkInCount: 2,
          firstCheckInMinute: 9 * 60,
          checkInLatencyMinutes: -15,
          selfMoodMedian: 3.5,
          journalWordCount: 120,
          chatMinutes: 12,
          topApps: [AppUsage(name: 'Chrome', minutes: 40)],
        ),
      );

      final restored = DailyFeatures.fromMap(row.toMap())!;

      expect(restored.dayKey, '2026-10-01');
      expect(restored.sources, {'usage', 'inApp'});
      expect(restored.screenOnMinutes, 212);
      expect(restored.hourlyActiveMinutes, hasLength(24));
      expect(restored.hourlyActiveMinutes![22], 40);
      expect(restored.estimatedSleepMinutes, 430);
      expect(restored.lastUseDelayVsStatedBedtimeMinutes, 40);
      expect(restored.categoryMinutes, {'social': 80, 'video': 60, 'other': 72});
      expect(restored.firstCheckInMinute, 9 * 60);
      expect(restored.checkInLatencyMinutes, -15);
      expect(restored.selfMoodMedian, 3.5);
      expect(restored.topApps!.single.name, 'Chrome');
    });

    test('merging keeps both sources and lets the newer value win', () {
      final usage = _usageDay('2026-10-01');
      const inApp = DailyFeatures(
        dayKey: '2026-10-01',
        sources: {'inApp'},
        checkInCount: 1,
        screenOnMinutes: 999,
      );

      final merged = usage.mergedWith(inApp);

      expect(merged.sources, {'usage', 'inApp'});
      expect(merged.unlockCount, 64);
      expect(merged.checkInCount, 1);
      expect(merged.screenOnMinutes, 999);
    });

    test('a source with no value for a field does not erase it', () {
      final merged = _usageDay(
        '2026-10-01',
      ).mergedWith(const DailyFeatures(dayKey: '2026-10-01'));

      expect(merged.screenOnMinutes, 212);
      expect(merged.categoryMinutes, isNotNull);
    });

    test('withoutUsage keeps what the app recorded and drops what the phone gave', () {
      final row = _usageDay('2026-10-01').mergedWith(
        const DailyFeatures(
          dayKey: '2026-10-01',
          sources: {'inApp', 'usageFinal'},
          checkInCount: 2,
          journalWordCount: 80,
          selfMoodMedian: 0.25,
        ),
      );

      final stripped = row.withoutUsage();

      expect(stripped.sources, {'inApp'});
      expect(stripped.checkInCount, 2);
      expect(stripped.journalWordCount, 80);
      expect(stripped.selfMoodMedian, 0.25);
      expect(stripped.screenOnMinutes, isNull);
      expect(stripped.hourlyActiveMinutes, isNull);
      expect(stripped.estimatedSleepMinutes, isNull);
      expect(stripped.categoryMinutes, isNull);
    });

    test('a row of only device data has no sources left once stripped', () {
      expect(_usageDay('2026-10-01').withoutUsage().sources, isEmpty);
    });

    test('withoutAppNames drops only the names', () {
      const row = DailyFeatures(
        dayKey: '2026-10-01',
        categoryMinutes: {'social': 30},
        topApps: [AppUsage(name: 'Chrome', minutes: 40)],
        screenOnMinutes: 100,
      );

      final stripped = row.withoutAppNames();

      expect(stripped.topApps, isNull);
      expect(stripped.categoryMinutes, {'social': 30});
      expect(stripped.screenOnMinutes, 100);
    });

    test('implausible stored values read as not collected', () {
      final row = DailyFeatures.fromMap({
        'dayKey': '2026-10-01',
        'screenOnMinutes': 99999,
        'unlockCount': -3,
        'firstPickupMinute': 5000,
        'hourlyActiveMinutes': [1, 2, 3],
        'appSwitchRate': double.nan,
        'categoryMinutes': {'social': 30, 'bad': -5, 7: 10},
        'topApps': [
          {'name': 'Chrome', 'minutes': 10},
          {'name': '', 'minutes': 5},
          'junk',
        ],
      })!;

      expect(row.screenOnMinutes, isNull);
      expect(row.unlockCount, isNull);
      expect(row.firstPickupMinute, isNull);
      expect(row.hourlyActiveMinutes, isNull);
      expect(row.appSwitchRate, isNull);
      expect(row.categoryMinutes, {'social': 30});
      expect(row.topApps, hasLength(1));
    });

    test('a row without a valid day key is rejected', () {
      expect(DailyFeatures.fromMap({'screenOnMinutes': 10}), isNull);
      expect(DailyFeatures.fromMap({'dayKey': 'yesterday'}), isNull);
    });

    test('date reads back the calendar day', () {
      expect(
        const DailyFeatures(dayKey: '2026-03-08').date,
        DateTime(2026, 3, 8),
      );
    });
  });

  group('retentionCutoffDayKey', () {
    test('keeps exactly the requested number of days, today included', () {
      expect(retentionCutoffDayKey(DateTime(2026, 10, 10, 15), 1), '2026-10-10');
      expect(retentionCutoffDayKey(DateTime(2026, 10, 10, 15), 7), '2026-10-04');
    });

    test('crosses month and year boundaries', () {
      expect(retentionCutoffDayKey(DateTime(2027, 1, 3), 5), '2026-12-30');
    });

    test('counts calendar days across a daylight-saving change', () {
      // A 24-hour subtraction could land a day off around a clock change.
      expect(retentionCutoffDayKey(DateTime(2026, 3, 9, 0, 30), 3), '2026-03-07');
    });
  });

  void repositoryContract(
    String name,
    Future<DailyFeaturesRepository> Function() create,
  ) {
    group(name, () {
      late DailyFeaturesRepository repository;

      setUp(() async => repository = await create());

      test('starts empty', () async {
        expect(await repository.loadAll(), isEmpty);
      });

      test('returns rows oldest first', () async {
        await repository.upsert(_usageDay('2026-10-03'));
        await repository.upsert(_usageDay('2026-10-01'));
        await repository.upsert(_usageDay('2026-10-02'));

        expect((await repository.loadAll()).map((row) => row.dayKey), [
          '2026-10-01',
          '2026-10-02',
          '2026-10-03',
        ]);
      });

      test('upserting the same day merges instead of replacing', () async {
        await repository.upsert(_usageDay('2026-10-01'));
        await repository.upsert(
          const DailyFeatures(
            dayKey: '2026-10-01',
            sources: {'inApp'},
            checkInCount: 2,
          ),
        );

        final rows = await repository.loadAll();
        expect(rows, hasLength(1));
        expect(rows.single.screenOnMinutes, 212);
        expect(rows.single.checkInCount, 2);
        expect(rows.single.sources, {'usage', 'inApp'});
      });

      test('prunes rows older than the cutoff and reports how many', () async {
        for (final key in ['2026-09-28', '2026-09-29', '2026-10-01']) {
          await repository.upsert(_usageDay(key));
        }

        final removed = await repository.deleteBefore('2026-09-30');

        expect(removed, 2);
        expect((await repository.loadAll()).map((row) => row.dayKey), [
          '2026-10-01',
        ]);
        expect(await repository.deleteBefore('2026-09-30'), 0);
      });

      test('removeAppNames strips names and keeps everything else', () async {
        await repository.upsert(
          const DailyFeatures(
            dayKey: '2026-10-01',
            screenOnMinutes: 120,
            categoryMinutes: {'social': 40},
            topApps: [AppUsage(name: 'Chrome', minutes: 40)],
          ),
        );
        await repository.upsert(const DailyFeatures(dayKey: '2026-10-02'));

        await repository.removeAppNames();

        final rows = await repository.loadAll();
        expect(rows, hasLength(2));
        expect(rows.first.topApps, isNull);
        expect(rows.first.screenOnMinutes, 120);
        expect(rows.first.categoryMinutes, {'social': 40});
      });

      test('removeUsageData keeps in-app days and removes device-only ones', () async {
        await repository.upsert(_usageDay('2026-10-01'));
        await repository.upsert(
          const DailyFeatures(
            dayKey: '2026-10-02',
            sources: {'inApp'},
            checkInCount: 1,
          ),
        );
        await repository.upsert(_usageDay('2026-10-03'));
        await repository.upsert(
          const DailyFeatures(
            dayKey: '2026-10-03',
            sources: {'inApp'},
            checkInCount: 3,
          ),
        );

        await repository.removeUsageData();

        final rows = await repository.loadAll();
        // The device-only day is gone; the in-app day and the mixed day stay,
        // the mixed one without anything read from the phone.
        expect(rows.map((r) => r.dayKey), ['2026-10-02', '2026-10-03']);
        expect(rows.last.checkInCount, 3);
        expect(rows.last.screenOnMinutes, isNull);
        expect(rows.last.sources, {'inApp'});
        expect(rows.every((r) => !r.hasUsage), isTrue);
      });

      test('deleteAll removes everything', () async {
        await repository.upsert(_usageDay('2026-10-01'));
        await repository.upsert(_usageDay('2026-10-02'));

        await repository.deleteAll();

        expect(await repository.loadAll(), isEmpty);
      });
    });
  }

  repositoryContract(
    'InMemoryDailyFeaturesRepository',
    () async => InMemoryDailyFeaturesRepository(),
  );

  repositoryContract('SharedPreferencesDailyFeaturesRepository', () async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferencesDailyFeaturesRepository(
      await SharedPreferences.getInstance(),
    );
  });

  test('stored rows survive reopening the preferences repository', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await SharedPreferencesDailyFeaturesRepository(
      preferences,
    ).upsert(_usageDay('2026-10-01'));

    final reopened = await SharedPreferencesDailyFeaturesRepository(
      preferences,
    ).loadAll();

    expect(reopened.single.screenOnMinutes, 212);
  });

  test('unreadable stored data is dropped instead of blocking startup', () async {
    SharedPreferences.setMockInitialValues({
      'footprint.dailyFeatures': '{not json',
    });
    final preferences = await SharedPreferences.getInstance();

    final rows = await SharedPreferencesDailyFeaturesRepository(
      preferences,
    ).loadAll();

    expect(rows, isEmpty);
  });
}
