import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/features/profile/permissions_page.dart';
import 'package:solace_mobile/services/app_permission_service.dart';

/// Answers from fixed state instead of the platform channel.
class _FakePermissions extends AppPermissionService {
  _FakePermissions({
    this.notifications = false,
    this.microphone = false,
    this.camera = false,
    this.canOpenSettings = true,
  });

  final bool notifications;
  final bool microphone;
  final bool camera;
  final bool canOpenSettings;
  int settingsOpened = 0;

  @override
  Future<bool> notificationsGranted() async => notifications;

  @override
  Future<bool> microphoneGranted() async => microphone;

  @override
  Future<bool> cameraGranted() async => camera;

  @override
  Future<bool> openSystemSettings() async {
    settingsOpened++;
    return canOpenSettings;
  }
}

void main() {
  Future<_FakePermissions> pumpPage(
    WidgetTester tester, {
    bool notifications = false,
    bool microphone = false,
    bool camera = false,
    bool canOpenSettings = true,
  }) async {
    final permissions = _FakePermissions(
      notifications: notifications,
      microphone: microphone,
      camera: camera,
      canOpenSettings: canOpenSettings,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PermissionsPage(permissions: permissions),
      ),
    );
    await tester.pumpAndSettle();
    return permissions;
  }

  testWidgets('reports a denied permission honestly', (tester) async {
    await pumpPage(tester);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Not allowed'), findsNWidgets(3));
    // Denied rows explain the consequence rather than nagging.
    expect(
      find.text('No reminders. Everything else still works.'),
      findsOneWidget,
    );
  });

  testWidgets('reports an allowed permission with what it buys', (
    tester,
  ) async {
    await pumpPage(tester, notifications: true, microphone: true);

    expect(find.text('Allowed'), findsNWidgets(2));
    expect(
      find.text('Gentle check-in reminders at the time you choose.'),
      findsOneWidget,
    );
  });

  testWidgets('the camera is reported like the other permissions, and location is never asked', (tester) async {
    await pumpPage(tester, camera: true);
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.textContaining('Frames are read live and never saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-location')), findsOneWidget);
    expect(find.text('Never asked'), findsOneWidget);
  });

  testWidgets('says plainly that the app cannot change these itself', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(
      find.textContaining('Android owns these settings'),
      findsOneWidget,
    );
    expect(
      find.text('Change in system settings'),
      findsNWidgets(3),
    );
  });

  testWidgets('opening settings is a real action', (tester) async {
    final permissions = await pumpPage(tester);

    await tester.tap(find.text('Change in system settings').first);
    await tester.pumpAndSettle();

    expect(permissions.settingsOpened, 1);
  });

  testWidgets('explains when settings cannot be opened', (tester) async {
    await pumpPage(tester, canOpenSettings: false);

    await tester.tap(find.text('Change in system settings').first);
    await tester.pumpAndSettle();

    expect(find.text('Could not open system settings.'), findsOneWidget);
  });

  testWidgets('states what leaves the device, including server processing', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('WHAT LEAVES THIS DEVICE'), findsOneWidget);
    // Audio genuinely leaves the device, so the page must not claim otherwise.
    expect(
      find.textContaining('send audio to the companion server'),
      findsOneWidget,
    );
    expect(
      find.textContaining('sends your chat text to the Solace companion'),
      findsOneWidget,
    );
    // Live camera frames genuinely leave the device when face reading is on, so it says so too.
    expect(find.textContaining('live camera frames'), findsOneWidget);
  });

  testWidgets('names what it deliberately does not collect', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('WHAT SOLACE DOES NOT COLLECT'), findsOneWidget);
    expect(
      find.textContaining('Your location, contacts, messages or call history'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Advertising identifiers'),
      findsOneWidget,
    );
  });

  testWidgets('never repeats the old unsupported privacy claims', (
    tester,
  ) async {
    await pumpPage(tester);

    // These were false and were removed. They must not come back.
    expect(find.textContaining('AES-256'), findsNothing);
    expect(find.textContaining('Zero telemetry'), findsNothing);
    expect(find.textContaining('zero telemetry'), findsNothing);
    expect(find.textContaining('Zero Third-Party Telemetry'), findsNothing);
    expect(find.textContaining('Local Enclave'), findsNothing);
    expect(find.textContaining('processed on-device whenever supported'),
        findsNothing);
  });
}
