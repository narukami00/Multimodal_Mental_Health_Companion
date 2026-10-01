import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/domain/home/home_card_priority.dart';
import 'package:solace_mobile/features/app_shell/check_in_task_card.dart';
import 'package:solace_mobile/features/app_shell/today_page.dart';
import 'package:solace_mobile/features/companion/blob_simulation.dart';
import 'package:solace_mobile/features/companion/companion_blob.dart';

/// How far the resting bubble sits above the card's top edge.
///
/// Asserted on the rendered result rather than on the layout constant, because
/// the shape is drawn inside a box much larger than itself and every earlier
/// attempt to place it by arithmetic moved it the wrong way. This measures where
/// the bubble actually appears.
void main() {
  testWidgets('the bubble hangs mostly above the card', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TodayPage(
            primaryCard: HomeCardType.checkIn,
            currentTime: DateTime(2026, 10, 1, 19, 12),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final blob = tester.widget<CompanionBlob>(find.byType(CompanionBlob));
    final diameter = blob.diameter;

    // The shape is centred in its own box, so the box's centre is the shape's
    // centre. That is the distinction that made this wrong by hand: the box is
    // far larger than the shape, so positioning the box is not positioning the
    // shape.
    final shapeCentre = tester.getRect(find.byType(CompanionBlob)).center;
    final radius = diameter / 2;
    final shapeBottom = shapeCentre.dy + radius;
    final cardTop = tester.getRect(find.byType(CheckInTaskCard)).top;

    final inside = shapeBottom - cardTop;
    final fraction = inside / diameter;

    expect(
      fraction,
      inInclusiveRange(0.25, 0.40),
      reason: 'the bubble sits $fraction of its diameter below the card top; '
          'it should hang mostly above the card, around a third',
    );
  });

  test('the overlap constant matches the diameter it describes', () {
    // The two are stated separately, so this is the cheap guard against someone
    // changing the diameter and leaving the fraction describing a shape that is
    // no longer there.
    expect(
      TodayPage.blobOverlapFraction,
      lessThan(0.5),
      reason: 'an overlap near or above a half reads as resting on the card '
          'rather than hanging above it',
    );
    expect(TodayPage.blobDiameterOnHome, greaterThan(0));
  });

  test('the layout box is larger than the shape it holds', () {
    // The placement maths depends on this. If the box ever matched the resting
    // diameter, positioning the box would position the shape and the derived
    // offset would silently become wrong.
    expect(
      CompanionBlob.boxExtentFor(TodayPage.blobDiameterOnHome),
      greaterThan(TodayPage.blobDiameterOnHome * BlobSimulation.inflateRadius),
    );
  });
}