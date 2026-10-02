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
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/insights/insights_page.dart';
import 'package:solace_mobile/features/insights/phone_patterns_section.dart';
import 'package:solace_mobile/features/profile/phone_patterns_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

class _Collector implements UsageCollectorService {
  bool access = true;
  @override
  Future<bool> hasAccess() async => access;
  @override
  Future<bool> openAccessSettings() async => true;
  @override
  Future<List<UsageEvent>> events({required DateTime from, required DateTime to}) async =>
      const [];
  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async =>
      const {};
}

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

final _now = DateTime(2026, 10, 31, 9);

DailyFeatures _day(int back) {
  final day = DateTime(2026, 10, 31 - back);
  return DailyFeatures(
    dayKey: _key(day),
    sources: const {'usage', 'usageFinal'},
    screenOnMinutes: 200,
    categoryMinutes: const {'social': 90, 'video': 20},
    estimatedSleepStartMinute: 23 * 60 + 30,
    estimatedSleepEndMinute: 7 * 60,
    estimatedSleepMinutes: 450,
  );
}

void main() {
  late _Collector collector;
  late ConsentController consent;
  late InMemoryDailyFeaturesRepository repository;
  late PhonePatternsController patterns;
  late ProfileController profile;

  setUp(() async {
    collector = _Collector();
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

  Future<void> pump(WidgetTester tester, {bool withSection = true}) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await patterns.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: withSection
            ? Scaffold(
                body: SingleChildScrollView(
                  child: PhonePatternsSection(
                    phonePatterns: patterns,
                    profileController: profile,
                    clock: () => _now,
                  ),
                ),
              )
            : InsightsPage(
                sessionController: SessionController(
                  repository: InMemorySessionRepository(),
                  emotionAnalyzer: const MockEmotionAnalyzer(),
                ),
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  testWidgets('off and empty: a quiet invitation, no numbers', (tester) async {
    await pump(tester);

    expect(find.text('PHONE PATTERNS'), findsOneWidget);
    expect(key('phone-section-off'), findsOneWidget);
    expect(find.textContaining('nothing is being read'), findsOneWidget);
    expect(key('phone-section-learning'), findsNothing);
    expect(find.textContaining('usually'), findsNothing);
  });

  testWidgets('the invitation opens My phone patterns', (tester) async {
    await pump(tester);

    await tester.tap(key('phone-section-open'));
    await tester.pumpAndSettle();

    expect(find.byType(PhonePatternsPage), findsOneWidget);
  });

  testWidgets('on but still learning: says how many days, and claims nothing', (
    tester,
  ) async {
    await consent.grant(ConsentKey.usageFootprint);
    for (var back = 1; back <= 6; back++) {
      await repository.upsert(_day(back));
    }
    await pump(tester);

    expect(find.text('Still getting to know your usual.'), findsOneWidget);
    expect(find.textContaining('6 of 14 days read'), findsOneWidget);
    expect(find.textContaining('usually'), findsNothing);
  });

  testWidgets('with enough days: plain statements about their own usual', (
    tester,
  ) async {
    await consent.grant(ConsentKey.usageFootprint);
    for (var back = 1; back <= 28; back++) {
      await repository.upsert(_day(back));
    }
    await pump(tester);

    expect(find.text('YOUR USUAL SCREEN TIME'), findsOneWidget);
    expect(
      find.text('Your screen is usually on for about 3 h 20 min a day.'),
      findsOneWidget,
    );
    expect(find.text('YOUR USUAL NIGHT'), findsOneWidget);
    expect(find.text('WHERE TIME WENT THIS WEEK'), findsOneWidget);
    expect(key('phone-section-learning'), findsNothing);
  });

  testWidgets('turned off later but with days still stored: shows them, not an invitation', (
    tester,
  ) async {
    for (var back = 1; back <= 28; back++) {
      await repository.upsert(_day(back));
    }
    await pump(tester);

    expect(key('phone-section-off'), findsNothing);
    expect(find.text('YOUR USUAL SCREEN TIME'), findsOneWidget);
  });

  testWidgets('the details link opens My phone patterns', (tester) async {
    await consent.grant(ConsentKey.usageFootprint);
    for (var back = 1; back <= 28; back++) {
      await repository.upsert(_day(back));
    }
    await pump(tester);

    await tester.tap(key('phone-section-details'));
    await tester.pumpAndSettle();

    expect(find.byType(PhonePatternsPage), findsOneWidget);
  });

  testWidgets('updates when new days arrive', (tester) async {
    await consent.grant(ConsentKey.usageFootprint);
    for (var back = 1; back <= 6; back++) {
      await repository.upsert(_day(back));
    }
    await pump(tester);
    expect(find.textContaining('6 of 14 days read'), findsOneWidget);

    for (var back = 7; back <= 10; back++) {
      await repository.upsert(_day(back));
    }
    patterns.dataChanged();
    await tester.pumpAndSettle();

    expect(find.textContaining('10 of 14 days read'), findsOneWidget);
  });

  testWidgets('the Insights page without the controllers shows no such section', (
    tester,
  ) async {
    await pump(tester, withSection: false);

    expect(find.text('PHONE PATTERNS'), findsNothing);
    expect(find.text('Insights'), findsOneWidget);
  });
}
