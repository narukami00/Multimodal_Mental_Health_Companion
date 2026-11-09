import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/onboarding/onboarding_choices.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

class _Collector implements UsageCollectorService {
  bool opened = false;

  @override
  Future<bool> hasAccess() async => false;

  @override
  Future<bool> openAccessSettings() async {
    opened = true;
    return true;
  }

  @override
  Future<List<UsageEvent>> events({required DateTime from, required DateTime to}) async => const [];

  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async => const {};
}

void main() {
  Future<(ConsentController, PhonePatternsController, _Collector)> pump(WidgetTester tester, {bool showMedia = false}) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    final collector = _Collector();
    final patterns = PhonePatternsController(consent: consent, collector: collector, repository: InMemoryDailyFeaturesRepository());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ReadingChoices(consent: consent, phonePatterns: patterns, showMedia: showMedia))),
    ));
    return (consent, patterns, collector);
  }

  Finder phoneSwitch() => find.descendant(of: find.byKey(const ValueKey('onboarding-phone-patterns')), matching: find.byType(Switch));

  testWidgets('phone patterns start off, and the voice and face switches are left out for someone who chose text', (tester) async {
    final (consent, patterns, _) = await pump(tester);
    expect(tester.widget<Switch>(phoneSwitch()).value, isFalse);
    expect(patterns.status, PhonePatternsStatus.off);
    expect(consent.isGranted(ConsentKey.usageFootprint), isFalse);
    expect(find.byKey(const ValueKey('onboarding-consent-voice')), findsNothing);
  });

  testWidgets('switching it on records the choice and sends the person to Android usage access', (tester) async {
    final (consent, patterns, collector) = await pump(tester);
    await tester.tap(phoneSwitch());
    await tester.pumpAndSettle();

    expect(consent.isGranted(ConsentKey.usageFootprint), isTrue);
    expect(collector.opened, isTrue);
    expect(patterns.status, PhonePatternsStatus.needsAndroidAccess);
    expect(tester.widget<Switch>(phoneSwitch()).value, isTrue);
  });

  testWidgets('switching it off again withdraws the choice', (tester) async {
    final (consent, patterns, _) = await pump(tester);
    await tester.tap(phoneSwitch());
    await tester.pumpAndSettle();
    await tester.tap(phoneSwitch());
    await tester.pumpAndSettle();

    expect(consent.isGranted(ConsentKey.usageFootprint), isFalse);
    expect(patterns.status, PhonePatternsStatus.off);
  });

  testWidgets('someone who chose voice and video sees all three switches', (tester) async {
    await pump(tester, showMedia: true);
    expect(find.byKey(const ValueKey('onboarding-phone-patterns')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-consent-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-consent-face')), findsOneWidget);
  });
}
