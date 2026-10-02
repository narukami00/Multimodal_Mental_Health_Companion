import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/day_rhythm_card.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/profile/phone_patterns_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

class _Collector implements UsageCollectorService {
  @override
  Future<bool> hasAccess() async => true;
  @override
  Future<bool> openAccessSettings() async => true;
  @override
  Future<List<UsageEvent>> events({required DateTime from, required DateTime to}) async =>
      const [];
  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async =>
      const {};
}

void main() {
  final now = DateTime(2026, 10, 31, 9);
  late InMemoryDailyFeaturesRepository repository;
  late PhonePatternsController patterns;
  late ProfileController profile;

  setUp(() async {
    final consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    repository = InMemoryDailyFeaturesRepository();
    patterns = PhonePatternsController(
      consent: consent,
      collector: _Collector(),
      repository: repository,
    );
    profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DayRhythmCard(
            phonePatterns: patterns,
            profileController: profile,
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows nothing when there is no finished day', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('day-rhythm-card')), findsNothing);
  });

  testWidgets('describes yesterday and opens My phone patterns', (tester) async {
    await repository.upsert(
      DailyFeatures(
        dayKey: '2026-10-30',
        sources: const {'usage', 'usageFinal'},
        screenOnMinutes: 200,
        hourlyActiveMinutes: [for (var h = 0; h < 24; h++) h == 21 ? 40 : 5],
        estimatedSleepStartMinute: 23 * 60 + 30,
        estimatedSleepEndMinute: 7 * 60,
      ),
    );
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('YESTERDAY ON YOUR PHONE'), findsOneWidget);
    expect(find.text('3h 20m'), findsOneWidget);
    expect(find.textContaining('Busiest around 9 PM'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-rhythm-card')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(PhonePatternsPage), findsOneWidget);
  });
}
