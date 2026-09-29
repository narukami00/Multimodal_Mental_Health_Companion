import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/app_shell/living_atmosphere_card.dart';
import 'package:solace_mobile/services/ambient_audio_service.dart';

void main() {
  setUp(() async {
    await AmbientAudioService.instance.stop();
  });

  Future<void> pumpCard(WidgetTester tester, {required bool enabled}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LivingAtmosphereCard(ambientAudioEnabled: enabled),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sound shelf does not play when ambient audio is disabled', (
    tester,
  ) async {
    await pumpCard(tester, enabled: false);

    await tester.tap(find.text('Rainfall'));
    await tester.pumpAndSettle();

    expect(AmbientAudioService.instance.currentMode, SoundscapeMode.none);
    expect(find.text('Ambient audio is off in Settings.'), findsOneWidget);
  });

  testWidgets('sound shelf stays interactive when ambient audio is enabled', (
    tester,
  ) async {
    await pumpCard(tester, enabled: true);

    // The chip remains tappable; the shelf is not dimmed to a disabled look.
    expect(find.text('Rainfall'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Rainfall'),
        matching: find.byType(GestureDetector),
      ),
      findsWidgets,
    );
  });
}
