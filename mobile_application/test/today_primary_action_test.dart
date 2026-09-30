import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/domain/home/home_card_priority.dart';
import 'package:solace_mobile/features/app_shell/today_page.dart';

/// Every one of these cards used to run the check-in flow, whatever its own
/// label said. These tests check each card does what it promises.
Future<void> _pump(
  WidgetTester tester,
  HomeCardType type, {
  VoidCallback? onStartCheckIn,
  VoidCallback? onOpenSupport,
  VoidCallback? onOpenChat,
  VoidCallback? onContinueSetup,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: TodayPage(
          primaryCard: type,
          onStartCheckIn: onStartCheckIn,
          onOpenSupport: onOpenSupport,
          onOpenChat: onOpenChat,
          onContinueSetup: onContinueSetup,
        ),
      ),
    ),
  );
  // The page has ambient animations, so settle by pumping rather than waiting
  // for stillness.
  await tester.pump();
}

void main() {
  testWidgets('the check-in card starts a check-in', (tester) async {
    var checkIn = false;
    await _pump(
      tester,
      HomeCardType.checkIn,
      onStartCheckIn: () => checkIn = true,
      onOpenChat: () {},
    );

    await tester.tap(find.text('Check in now'));
    await tester.pump();

    expect(checkIn, isTrue);
  });

  testWidgets('the setup card continues setup, not a check-in', (tester) async {
    var setup = false;
    var checkIn = false;
    await _pump(
      tester,
      HomeCardType.onboarding,
      onContinueSetup: () => setup = true,
      onStartCheckIn: () => checkIn = true,
    );

    await tester.tap(find.text('Continue setup'));
    await tester.pump();

    expect(setup, isTrue);
    // The bug: this used to open the check-in flow.
    expect(checkIn, isFalse);
  });

  testWidgets('the support card opens support, not a check-in', (tester) async {
    var support = false;
    var checkIn = false;
    await _pump(
      tester,
      HomeCardType.support,
      onOpenSupport: () => support = true,
      onStartCheckIn: () => checkIn = true,
    );

    await tester.tap(find.text('View support'));
    await tester.pump();

    expect(support, isTrue);
    expect(checkIn, isFalse);
  });

  testWidgets('the default card opens a conversation', (tester) async {
    var chat = false;
    var checkIn = false;
    await _pump(
      tester,
      HomeCardType.defaultAction,
      onOpenChat: () => chat = true,
      onStartCheckIn: () => checkIn = true,
    );

    await tester.tap(find.text('Open journal'));
    await tester.pump();

    expect(chat, isTrue);
    expect(checkIn, isFalse);
  });
}
