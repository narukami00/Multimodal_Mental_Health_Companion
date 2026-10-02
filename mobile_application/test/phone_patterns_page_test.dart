import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/profile/phone_patterns_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

class _FakeCollector implements UsageCollectorService {
  bool access = true;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<bool> openAccessSettings() async => true;

  @override
  Future<List<UsageEvent>> events({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async =>
      const {};
}

DailyFeatures _day(String key, {int screen = 205}) => DailyFeatures(
  dayKey: key,
  sources: const {'usage', 'usageFinal'},
  screenOnMinutes: screen,
  sessionCount: 64,
  longestSessionMinutes: 38,
  hourlyActiveMinutes: [for (var h = 0; h < 24; h++) h == 21 ? 40 : 3],
  estimatedSleepStartMinute: 23 * 60 + 30,
  estimatedSleepEndMinute: 7 * 60,
  estimatedSleepMinutes: 450,
  categoryMinutes: const {'social': 70, 'other': 30, 'video': 5},
);

void main() {
  // Saturday 3 October 2026, midday.
  final now = DateTime(2026, 10, 3, 12);
  late _FakeCollector collector;
  late ConsentController consent;
  late InMemoryDailyFeaturesRepository repository;
  late PhonePatternsController patterns;
  late ProfileController profile;

  setUp(() async {
    collector = _FakeCollector();
    consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    repository = InMemoryDailyFeaturesRepository();
    patterns = PhonePatternsController(
      consent: consent,
      collector: collector,
      repository: repository,
    );
    profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await patterns.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PhonePatternsPage(
          phonePatterns: patterns,
          profileController: profile,
          clock: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  testWidgets('says plainly that nothing has been read yet', (tester) async {
    await pump(tester);

    expect(find.text('Off'), findsOneWidget);
    expect(find.textContaining('Nothing is being read'), findsOneWidget);
    expect(key('patterns-empty'), findsOneWidget);
    expect(find.text('No days read yet.'), findsOneWidget);
    expect(key('patterns-delete-all'), findsNothing);
  });

  testWidgets('describes the latest finished day in plain words', (
    tester,
  ) async {
    await consent.grant(ConsentKey.usageFootprint);
    await repository.upsert(_day('2026-10-01'));
    await repository.upsert(_day('2026-10-02'));
    await repository.upsert(
      const DailyFeatures(
        dayKey: '2026-10-03',
        sources: {'usage'},
        screenOnMinutes: 15,
      ),
    );
    await pump(tester);

    expect(find.text('FRIDAY 2 OCTOBER'), findsOneWidget);
    expect(find.text('Screen on for about 3 h 25 min.'), findsOneWidget);
    expect(
      find.text('Picked up 64 times; the longest stretch was 38 min.'),
      findsOneWidget,
    );
    expect(find.text('Busiest around 9:00 PM.'), findsOneWidget);
    expect(
      find.text('Most time in social (1 h 10 min), then other (30 min).'),
      findsOneWidget,
    );
  });

  testWidgets('never describes a day still in progress', (tester) async {
    await repository.upsert(
      const DailyFeatures(
        dayKey: '2026-10-03',
        sources: {'usage'},
        screenOnMinutes: 15,
      ),
    );
    await pump(tester);

    expect(key('patterns-empty'), findsOneWidget);
    expect(find.textContaining('Screen on for about'), findsNothing);
  });

  testWidgets('labels sleep an estimate that can run long', (tester) async {
    await repository.upsert(_day('2026-10-02'));
    await pump(tester);

    expect(
      find.textContaining('Phone down around 11:30 PM and next picked up around '
          '7:00 AM, roughly 7 h 30 min.'),
      findsOneWidget,
    );
    expect(find.textContaining('an estimate'), findsOneWidget);
  });

  testWidgets('judges nothing: no good, bad, goal, or comparison', (
    tester,
  ) async {
    await repository.upsert(_day('2026-10-02'));
    await pump(tester);

    for (final word in [
      'too much',
      'too little',
      'healthy',
      'unhealthy',
      'goal',
      'target',
      'average',
      'better',
      'worse',
      'addict',
    ]) {
      expect(
        find.textContaining(RegExp(word, caseSensitive: false)),
        findsNothing,
        reason: '"$word" would be a judgement',
      );
    }
  });

  testWidgets('the week shows known days as bars and unread days as gaps', (
    tester,
  ) async {
    await repository.upsert(_day('2026-10-01', screen: 100));
    await repository.upsert(_day('2026-10-02', screen: 200));
    await pump(tester);

    final readBar = tester.getSize(key('week-bar-2')).height;
    final smallerBar = tester.getSize(key('week-bar-1')).height;
    final gap = tester.getSize(key('week-bar-3')).height;

    expect(readBar, greaterThan(smallerBar));
    expect(smallerBar, greaterThan(gap));
    expect(gap, 3);
  });

  group('controls', () {
    testWidgets('app names are off by default and need phone patterns on', (
      tester,
    ) async {
      await pump(tester);

      final tile = tester.widget<Switch>(key('patterns-keep-names'));
      expect(tile.value, isFalse);
      expect(tile.onChanged, isNull);
      expect(find.text('Turn phone patterns on first.'), findsOneWidget);
    });

    testWidgets('keeping app names is a real switch', (tester) async {
      await consent.grant(ConsentKey.usageFootprint);
      await pump(tester);

      await tester.tap(key('patterns-keep-names'));
      await tester.pumpAndSettle();

      expect(consent.isGranted(ConsentKey.topAppNames), isTrue);
      expect(patterns.keepsAppNames, isTrue);

      await tester.tap(key('patterns-keep-names'));
      await tester.pumpAndSettle();

      expect(patterns.keepsAppNames, isFalse);
    });

    testWidgets('switching names off removes the stored ones', (tester) async {
      await consent.grant(ConsentKey.usageFootprint);
      await consent.grant(ConsentKey.topAppNames);
      await repository.upsert(
        DailyFeatures(
          dayKey: '2026-10-02',
          sources: const {'usage'},
          screenOnMinutes: 100,
          topApps: const [AppUsage(name: 'Chrome', minutes: 30)],
        ),
      );
      await pump(tester);

      await tester.tap(key('patterns-keep-names'));
      await tester.pumpAndSettle();

      final row = (await repository.loadAll()).single;
      expect(row.topApps, isNull);
      expect(row.screenOnMinutes, 100);
    });

    testWidgets('retention starts at the default and can be changed', (
      tester,
    ) async {
      await pump(tester);

      expect(
        tester.widget<ChoiceChip>(key('retention-180')).selected,
        isTrue,
      );

      await tester.tap(key('retention-90'));
      await tester.pumpAndSettle();

      expect(profile.profile.featureRetentionDays, 90);
      expect(tester.widget<ChoiceChip>(key('retention-90')).selected, isTrue);
    });

    testWidgets('a shorter retention removes older days at once', (
      tester,
    ) async {
      await repository.upsert(_day('2026-06-01'));
      await repository.upsert(_day('2026-09-20'));
      await repository.upsert(_day('2026-10-02'));
      await pump(tester);

      await tester.tap(key('retention-30'));
      await tester.pumpAndSettle();

      // Thirty days ending 3 October starts on 4 September.
      expect((await repository.loadAll()).map((r) => r.dayKey), [
        '2026-09-20',
        '2026-10-02',
      ]);
    });

    testWidgets('deleting everything asks first and then does it', (
      tester,
    ) async {
      await repository.upsert(_day('2026-10-01'));
      await repository.upsert(_day('2026-10-02'));
      await pump(tester);

      expect(find.text('Delete all stored patterns (2 days)'), findsOneWidget);
      await tester.tap(key('patterns-delete-all'));
      await tester.pumpAndSettle();
      expect(await repository.loadAll(), hasLength(2));

      await tester.tap(key('patterns-confirm-delete'));
      await tester.pumpAndSettle();

      expect(await repository.loadAll(), isEmpty);
      expect(key('patterns-empty'), findsOneWidget);
    });

    testWidgets('cancelling the delete keeps everything', (tester) async {
      await repository.upsert(_day('2026-10-02'));
      await pump(tester);

      await tester.tap(key('patterns-delete-all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await repository.loadAll(), hasLength(1));
    });
  });
}
