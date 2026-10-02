import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/profile/permissions_page.dart';
import 'package:solace_mobile/services/app_permission_service.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

/// Android's usage access as a switch the test can flip at any time, the way a
/// person can in system settings.
class _FakeCollector implements UsageCollectorService {
  bool access = false;
  bool canOpenSettings = true;
  int settingsOpened = 0;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<bool> openAccessSettings() async {
    settingsOpened++;
    return canOpenSettings;
  }

  @override
  Future<List<UsageEvent>> events({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async =>
      const {};
}

class _NoPermissions extends AppPermissionService {
  @override
  Future<bool> notificationsGranted() async => false;

  @override
  Future<bool> microphoneGranted() async => false;
}

void main() {
  late _FakeCollector collector;
  late ConsentController consent;
  late InMemoryDailyFeaturesRepository repository;
  late PhonePatternsController controller;

  Future<void> addDays(int count, {bool withNames = false}) async {
    for (var day = 1; day <= count; day++) {
      await repository.upsert(
        DailyFeatures(
          dayKey: '2026-10-${day.toString().padLeft(2, '0')}',
          screenOnMinutes: 100,
          sources: const {'usage'},
          topApps: withNames ? const [AppUsage(name: 'Chrome', minutes: 40)] : null,
        ),
      );
    }
  }

  setUp(() async {
    collector = _FakeCollector();
    consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    repository = InMemoryDailyFeaturesRepository();
    controller = PhonePatternsController(
      consent: consent,
      collector: collector,
      repository: repository,
    );
  });

  group('PhonePatternsController', () {
    test('starts off and reads nothing', () async {
      await controller.refresh();

      expect(controller.status, PhonePatternsStatus.off);
      expect(controller.isCollecting, isFalse);
    });

    test('Android access alone is not consent', () async {
      collector.access = true;
      await controller.refresh();

      expect(controller.status, PhonePatternsStatus.off);
      expect(controller.isCollecting, isFalse);
    });

    test('consent alone is not access', () async {
      await consent.grant(ConsentKey.usageFootprint);
      await controller.refresh();

      expect(controller.status, PhonePatternsStatus.needsAndroidAccess);
      expect(controller.isCollecting, isFalse);
    });

    test('collecting needs both', () async {
      collector.access = true;
      await consent.grant(ConsentKey.usageFootprint);
      await controller.refresh();

      expect(controller.status, PhonePatternsStatus.on);
      expect(controller.isCollecting, isTrue);
    });

    test('turning on records consent and sends them to Android when needed', () async {
      final opened = await controller.turnOn();

      expect(opened, isTrue);
      expect(consent.isGranted(ConsentKey.usageFootprint), isTrue);
      expect(collector.settingsOpened, 1);
      expect(controller.status, PhonePatternsStatus.needsAndroidAccess);
    });

    test('turning on does not open settings when access is already there', () async {
      collector.access = true;

      await controller.turnOn();

      expect(collector.settingsOpened, 0);
      expect(controller.status, PhonePatternsStatus.on);
    });

    test('reports when Android settings could not be opened', () async {
      collector.canOpenSettings = false;

      expect(await controller.turnOn(), isFalse);
      // Consent was still given; only the system screen failed to open.
      expect(consent.isGranted(ConsentKey.usageFootprint), isTrue);
    });

    test('notices when access is removed in Android, without being told', () async {
      collector.access = true;
      await controller.turnOn();
      expect(controller.status, PhonePatternsStatus.on);

      collector.access = false;
      await controller.refresh();

      expect(controller.status, PhonePatternsStatus.needsAndroidAccess);
      expect(controller.isCollecting, isFalse);
    });

    test('listeners hear about a change in Android access', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      collector.access = true;
      await controller.refresh();
      await controller.refresh();

      expect(notifications, 1);
    });

    test('turning off stops reading and keeps the stored days by default', () async {
      collector.access = true;
      await controller.turnOn();
      await addDays(3);

      await controller.turnOff();

      expect(controller.status, PhonePatternsStatus.off);
      expect(consent.statusOf(ConsentKey.usageFootprint), ConsentStatus.revoked);
      expect(await controller.storedDayCount(), 3);
    });

    test('turning off can delete what was stored as well', () async {
      collector.access = true;
      await controller.turnOn();
      await addDays(3);

      await controller.turnOff(deleteStored: true);

      expect(await controller.storedDayCount(), 0);
    });

    test('turning off always drops app names, even when keeping the rest', () async {
      collector.access = true;
      await controller.turnOn();
      await consent.grant(ConsentKey.topAppNames);
      await addDays(2, withNames: true);

      await controller.turnOff();

      final rows = await repository.loadAll();
      expect(rows.every((row) => row.topApps == null), isTrue);
      expect(rows.every((row) => row.screenOnMinutes == 100), isTrue);
      expect(consent.statusOf(ConsentKey.topAppNames), ConsentStatus.revoked);
    });
  });

  group('app names', () {
    setUp(() async {
      collector.access = true;
      await controller.turnOn();
    });

    test('are kept only when separately agreed to', () async {
      expect(controller.keepsAppNames, isFalse);

      await controller.setKeepAppNames(true);
      expect(controller.keepsAppNames, isTrue);
    });

    test('stopping removes the stored names and keeps the rest', () async {
      await controller.setKeepAppNames(true);
      await addDays(2, withNames: true);

      await controller.setKeepAppNames(false);

      expect(controller.keepsAppNames, isFalse);
      final rows = await repository.loadAll();
      expect(rows.every((row) => row.topApps == null), isTrue);
      expect(rows.first.screenOnMinutes, 100);
    });

    test('never count without the main consent', () async {
      await controller.setKeepAppNames(true);

      await controller.turnOff();

      expect(controller.keepsAppNames, isFalse);
    });
  });

  group('the permissions page card', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PermissionsPage(
            permissions: _NoPermissions(),
            phonePatterns: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder key(String value) => find.byKey(ValueKey(value));

    testWidgets('is hidden when no controller is given', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PermissionsPage(permissions: _NoPermissions()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phone patterns'), findsNothing);
    });

    testWidgets('starts off, says nothing is read, and offers to turn on', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Phone patterns'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.textContaining('Nothing is read'), findsOneWidget);
      expect(key('phone-patterns-turn-on'), findsOneWidget);
      expect(key('phone-patterns-turn-off'), findsNothing);
    });

    testWidgets('says what turning on means before doing anything', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(key('phone-patterns-turn-on'));
      await tester.pumpAndSettle();

      expect(find.text('Notice your phone rhythm?'), findsOneWidget);
      expect(
        find.textContaining('never reads what is inside an app'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing is sent anywhere'), findsOneWidget);
      // Nothing has been agreed to yet.
      expect(consent.isGranted(ConsentKey.usageFootprint), isFalse);
    });

    testWidgets('"Not now" changes nothing', (tester) async {
      await pump(tester);

      await tester.tap(key('phone-patterns-turn-on'));
      await tester.pumpAndSettle();
      await tester.tap(key('phone-patterns-not-now'));
      await tester.pumpAndSettle();

      expect(consent.history, isEmpty);
      expect(collector.settingsOpened, 0);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('agreeing records consent and opens Android settings', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(key('phone-patterns-turn-on'));
      await tester.pumpAndSettle();
      await tester.tap(key('phone-patterns-agree'));
      await tester.pumpAndSettle();

      expect(consent.isGranted(ConsentKey.usageFootprint), isTrue);
      expect(collector.settingsOpened, 1);
      expect(find.text('Needs access'), findsOneWidget);
      expect(key('phone-patterns-open-settings'), findsOneWidget);
    });

    testWidgets('shows On only when Android access is really on', (
      tester,
    ) async {
      collector.access = true;
      await consent.grant(ConsentKey.usageFootprint);
      await pump(tester);

      expect(find.text('On'), findsOneWidget);
      expect(find.textContaining('keeping a few numbers a day'), findsOneWidget);
    });

    testWidgets('re-checks Android when the app returns to the foreground', (
      tester,
    ) async {
      await consent.grant(ConsentKey.usageFootprint);
      await pump(tester);
      expect(find.text('Needs access'), findsOneWidget);

      // The person switches it on in Android's settings and comes back.
      collector.access = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('turning off with stored days asks whether to delete them', (
      tester,
    ) async {
      collector.access = true;
      await consent.grant(ConsentKey.usageFootprint);
      await addDays(4);
      await pump(tester);

      await tester.tap(key('phone-patterns-turn-off'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete the 4 days'), findsOneWidget);

      await tester.tap(key('phone-patterns-keep'));
      await tester.pumpAndSettle();

      expect(find.text('Off'), findsOneWidget);
      expect(await controller.storedDayCount(), 4);
    });

    testWidgets('turning off and deleting removes the stored days', (
      tester,
    ) async {
      collector.access = true;
      await consent.grant(ConsentKey.usageFootprint);
      await addDays(4);
      await pump(tester);

      await tester.tap(key('phone-patterns-turn-off'));
      await tester.pumpAndSettle();
      await tester.tap(key('phone-patterns-delete-too'));
      await tester.pumpAndSettle();

      expect(await controller.storedDayCount(), 0);
      expect(key('phone-patterns-delete'), findsNothing);
    });

    testWidgets('cancelling the turn-off dialog leaves everything on', (
      tester,
    ) async {
      collector.access = true;
      await consent.grant(ConsentKey.usageFootprint);
      await addDays(2);
      await pump(tester);

      await tester.tap(key('phone-patterns-turn-off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('On'), findsOneWidget);
      expect(consent.isGranted(ConsentKey.usageFootprint), isTrue);
    });

    testWidgets('stored days can be deleted on their own, after confirming', (
      tester,
    ) async {
      collector.access = true;
      await consent.grant(ConsentKey.usageFootprint);
      await addDays(3);
      await pump(tester);

      expect(find.text('Delete stored patterns (3 days)'), findsOneWidget);
      await tester.tap(key('phone-patterns-delete'));
      await tester.pumpAndSettle();
      expect(await controller.storedDayCount(), 3);

      await tester.tap(key('phone-patterns-confirm-delete'));
      await tester.pumpAndSettle();

      expect(await controller.storedDayCount(), 0);
      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('no stored days means no delete button', (tester) async {
      collector.access = true;
      await consent.grant(ConsentKey.usageFootprint);
      await pump(tester);

      expect(key('phone-patterns-delete'), findsNothing);
    });
  });
}
