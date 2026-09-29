import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/emergency_contact.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/care_contacts_page.dart';
import 'package:solace_mobile/services/dialer_service.dart';

/// Records hand-offs to the platform instead of opening a dialer.
class _RecordingDialer extends DialerService {
  _RecordingDialer({this.result = true});

  final bool result;
  final List<String> dialed = [];
  final List<String> texted = [];

  @override
  Future<bool> openDialer(String phone) async {
    dialed.add(phone);
    return result;
  }

  @override
  Future<bool> openSms(String phone, {String? body}) async {
    texted.add(phone);
    return result;
  }
}

void main() {
  group('EmergencyContact', () {
    test('normalises numbers for the dialer', () {
      const contact = EmergencyContact(
        id: 'c1',
        name: 'Ammu',
        phone: '+880 1700-000000',
      );

      expect(contact.dialableNumber, '+8801700000000');
    });

    test('round-trips through toMap/fromMap', () {
      const contact = EmergencyContact(
        id: 'c1',
        name: 'Ammu',
        phone: '+8801700000000',
        isIce: true,
      );

      final restored = EmergencyContact.fromMap(contact.toMap());

      expect(restored.id, 'c1');
      expect(restored.name, 'Ammu');
      expect(restored.phone, '+8801700000000');
      expect(restored.isIce, isTrue);
    });

    test('round-trips a contact list through the profile', () {
      const profile = UserProfile(
        emergencyContacts: [
          EmergencyContact(id: 'c1', name: 'Ammu', phone: '1700000000'),
          EmergencyContact(
            id: 'c2',
            name: 'Dr. Rahman',
            phone: '1711111111',
            isIce: true,
          ),
        ],
      );

      final restored = UserProfile.fromMap(profile.toMap());

      expect(restored.emergencyContacts.length, 2);
      expect(restored.emergencyContacts.last.name, 'Dr. Rahman');
      expect(restored.emergencyContacts.last.isIce, isTrue);
    });

    test('malformed stored contacts are skipped', () {
      final restored = UserProfile.fromMap({
        'emergencyContacts': [
          {'id': 'ok', 'name': 'Ammu', 'phone': '1700000000'},
          {'name': 'no id'},
          'not a map',
        ],
      });

      expect(restored.emergencyContacts.length, 1);
      expect(restored.emergencyContacts.single.id, 'ok');
    });
  });

  group('ProfileController contacts', () {
    late ProfileController controller;

    setUp(() async {
      controller = ProfileController(repository: InMemoryProfileRepository());
      await controller.load();
    });

    test('saves and replaces a contact by id', () async {
      await controller.saveEmergencyContact(
        const EmergencyContact(id: 'c1', name: 'Ammu', phone: '1700000000'),
      );
      await controller.saveEmergencyContact(
        const EmergencyContact(id: 'c1', name: 'Ammu', phone: '1799999999'),
      );

      expect(controller.profile.emergencyContacts.length, 1);
      expect(controller.profile.emergencyContacts.single.phone, '1799999999');
    });

    test('only one contact can be the call-first contact', () async {
      await controller.saveEmergencyContact(
        const EmergencyContact(
          id: 'c1',
          name: 'Ammu',
          phone: '1700000000',
          isIce: true,
        ),
      );
      await controller.saveEmergencyContact(
        const EmergencyContact(
          id: 'c2',
          name: 'Dr. Rahman',
          phone: '1711111111',
          isIce: true,
        ),
      );

      expect(controller.iceContact?.id, 'c2');
      final iceCount = controller.profile.emergencyContacts
          .where((contact) => contact.isIce)
          .length;
      expect(iceCount, 1);
    });

    test('removing an unknown contact changes nothing', () async {
      await controller.saveEmergencyContact(
        const EmergencyContact(id: 'c1', name: 'Ammu', phone: '1700000000'),
      );

      await controller.removeEmergencyContact('does-not-exist');

      expect(controller.profile.emergencyContacts.length, 1);
    });
  });

  group('CareContactsPage', () {
    late ProfileController controller;

    setUp(() async {
      controller = ProfileController(repository: InMemoryProfileRepository());
      await controller.load();
    });

    Future<_RecordingDialer> pumpPage(
      WidgetTester tester, {
      bool dialerResult = true,
    }) async {
      final dialer = _RecordingDialer(result: dialerResult);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: CareContactsPage(
            profileController: controller,
            dialer: dialer,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return dialer;
    }

    testWidgets('starts empty and explains what is kept', (tester) async {
      await pumpPage(tester);

      expect(find.text('No one saved yet'), findsOneWidget);
      expect(
        find.textContaining('nothing is called for you'),
        findsOneWidget,
      );
    });

    testWidgets('adds a contact and dials it on tap', (tester) async {
      final dialer = await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('add-contact')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('contact-name')),
        'Ammu',
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-phone')),
        '+880 1700-000000',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-contact')));
      await tester.pumpAndSettle();

      expect(find.text('Ammu'), findsOneWidget);
      expect(controller.profile.emergencyContacts.length, 1);

      final id = controller.profile.emergencyContacts.single.id;
      await tester.tap(find.byKey(ValueKey('call-$id')));
      await tester.pumpAndSettle();

      expect(dialer.dialed, ['+880 1700-000000']);
    });

    testWidgets('explains when no dialer can handle the call', (tester) async {
      final dialer = await pumpPage(tester, dialerResult: false);

      await controller.saveEmergencyContact(
        const EmergencyContact(id: 'c1', name: 'Ammu', phone: '1700000000'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('call-c1')));
      await tester.pumpAndSettle();

      expect(dialer.dialed, ['1700000000']);
      expect(
        find.text('No dialer available on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('marks a contact as call-first', (tester) async {
      await controller.saveEmergencyContact(
        const EmergencyContact(id: 'c1', name: 'Ammu', phone: '1700000000'),
      );
      await pumpPage(tester);

      await tester.tap(find.text('Make this my call-first contact'));
      await tester.pumpAndSettle();

      expect(controller.iceContact?.id, 'c1');
      expect(find.text('Call first'), findsOneWidget);
    });

    testWidgets('removes a contact after confirmation', (tester) async {
      await controller.saveEmergencyContact(
        const EmergencyContact(id: 'c1', name: 'Ammu', phone: '1700000000'),
      );
      await pumpPage(tester);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(controller.profile.emergencyContacts, isEmpty);
      expect(find.text('No one saved yet'), findsOneWidget);
    });
  });
}
