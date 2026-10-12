import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/emergency_contact.dart';
import 'package:solace_mobile/core/models/safety_assessment.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/breathing_pattern.dart';
import 'package:solace_mobile/features/safety/care_contacts_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/safety/support_resources_page.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/dialer_service.dart';

/// Records hand-offs to the platform instead of opening a dialer.
class _RecordingDialer extends DialerService {
  _RecordingDialer({this.result = true});

  final bool result;
  final List<String> dialed = [];

  @override
  Future<bool> openDialer(String phone) async {
    dialed.add(phone);
    return result;
  }
}

void main() {
  group('BreathingPattern', () {
    const pattern = BreathingPattern();

    test('cycles in four, hold four, out six', () {
      expect(pattern.cycleMs, 14000);
      expect(pattern.inhaleMs, 4000);
      expect(pattern.holdMs, 4000);
      expect(pattern.exhaleMs, 6000);
    });

    test('maps progress to the right phase', () {
      expect(pattern.phaseAt(0.0), BreathPhase.inhale);
      expect(pattern.phaseAt(0.2), BreathPhase.inhale);
      expect(pattern.phaseAt(0.3), BreathPhase.hold);
      expect(pattern.phaseAt(0.55), BreathPhase.hold);
      expect(pattern.phaseAt(0.6), BreathPhase.exhale);
      expect(pattern.phaseAt(1.0), BreathPhase.exhale);
    });

    test('grows on the inhale, holds, then settles', () {
      expect(pattern.scaleAt(0.0), closeTo(BreathingPattern.minScale, 0.001));
      // End of the inhale and through the hold the circle is fully open.
      expect(pattern.scaleAt(4000 / 14000), closeTo(1.0, 0.001));
      expect(pattern.scaleAt(0.4), closeTo(1.0, 0.001));
      // Back to the smallest size at the end of the exhale.
      expect(pattern.scaleAt(1.0), closeTo(BreathingPattern.minScale, 0.001));

      // Monotonic growth during the inhale.
      expect(pattern.scaleAt(0.1), greaterThan(pattern.scaleAt(0.0)));
      expect(pattern.scaleAt(0.2), greaterThan(pattern.scaleAt(0.1)));
    });

    test('uses short cues', () {
      expect(pattern.cueFor(BreathPhase.inhale), 'Breathe in');
      expect(pattern.cueFor(BreathPhase.hold), 'Hold');
      expect(pattern.cueFor(BreathPhase.exhale), 'Breathe out');
    });
  });

  group('SupportResourcesPage', () {
    late SafetyController safetyController;
    late ProfileController profileController;

    setUp(() {
      safetyController = SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );
      profileController = ProfileController(
        repository: InMemoryProfileRepository(),
      );
    });

    Future<_RecordingDialer> pumpPage(
      WidgetTester tester, {
      bool withProfile = true,
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
          home: SupportResourcesPage(
            safetyController: safetyController,
            profileController: withProfile ? profileController : null,
            dialer: dialer,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return dialer;
    }

    testWidgets('shows no helpline directory and no US numbers', (
      tester,
    ) async {
      await pumpPage(tester);

      // Regression guard: the old hardcoded US numbers must never return.
      expect(find.textContaining('988'), findsNothing);
      expect(find.textContaining('741741'), findsNothing);

      // The one external number is the national emergency number.
      expect(find.textContaining('999'), findsOneWidget);
      expect(find.text('Solace is not an emergency service.'), findsOneWidget);
    });

    testWidgets('Bangladesh shows its one verified listening line and dials it', (
      tester,
    ) async {
      final dialer = await pumpPage(tester);

      expect(find.text('Kaan Pete Roi'), findsOneWidget);
      expect(find.textContaining('3 PM to 3 AM'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('call-helpline')));
      await tester.tap(find.byKey(const ValueKey('call-helpline')));
      await tester.pumpAndSettle();
      expect(dialer.dialed, ['09612119911']);
    });

    testWidgets('another country gets no invented numbers', (tester) async {
      await profileController.load();
      await profileController.setCountry('ZZ');
      final dialer = await pumpPage(tester);

      expect(find.text('Kaan Pete Roi'), findsNothing);
      expect(find.byKey(const ValueKey('call-helpline')), findsNothing);
      expect(
        find.text('In immediate danger? Call your local emergency number'),
        findsOneWidget,
      );
      expect(find.textContaining('999'), findsNothing);

      await tester.tap(find.textContaining('local emergency number'));
      await tester.pumpAndSettle();
      expect(dialer.dialed, isEmpty);
    });

    testWidgets('invites the user to save someone when none exists', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.text('Add someone you can call'), findsOneWidget);
      expect(find.byKey(const ValueKey('call-person')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('add-person')));
      await tester.pumpAndSettle();

      expect(find.byType(CareContactsPage), findsOneWidget);
    });

    testWidgets('surfaces the call-first contact and dials them', (
      tester,
    ) async {
      await profileController.load();
      await profileController.saveEmergencyContact(
        const EmergencyContact(
          id: 'c1',
          name: 'Ammu',
          phone: '01700000000',
        ),
      );
      await profileController.saveEmergencyContact(
        const EmergencyContact(
          id: 'c2',
          name: 'Dr. Rahman',
          phone: '01711111111',
          isIce: true,
        ),
      );

      final dialer = await pumpPage(tester);

      expect(find.text('YOUR CALL-FIRST PERSON'), findsOneWidget);
      expect(find.text('Dr. Rahman'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('call-person')));
      await tester.pumpAndSettle();

      expect(dialer.dialed, ['01711111111']);
    });

    testWidgets('dials the national emergency number', (tester) async {
      final dialer = await pumpPage(tester);

      await tester.tap(find.textContaining('Call 999'));
      await tester.pumpAndSettle();

      expect(dialer.dialed, ['999']);
    });

    testWidgets('explains when no dialer is available', (tester) async {
      await pumpPage(tester, dialerResult: false);

      await tester.tap(find.textContaining('Call 999'));
      await tester.pumpAndSettle();

      expect(
        find.text('No dialer available on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the first breathing cue', (tester) async {
      await pumpPage(tester);

      expect(find.text('BREATHE WITH ME'), findsOneWidget);
      expect(find.text('Breathe in'), findsOneWidget);
    });

    testWidgets('closing marks support as shown', (tester) async {
      await safetyController.assessSignal(
        source: 'test',
        assessment: const SafetyAssessment(
          level: SafetyLevel.urgentSupport,
          matchedSignals: ['test_signal'],
        ),
      );
      expect(safetyController.hasActiveFlag, isTrue);

      // The urgent flag moves the emergency row to the top of the page.
      await pumpPage(tester);
      expect(find.textContaining('Call 999'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(safetyController.hasActiveFlag, isFalse);
    });
  });
}
