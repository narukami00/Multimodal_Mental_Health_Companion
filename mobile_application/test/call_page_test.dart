import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/call/call_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';
import 'package:solace_mobile/services/tts_playback_service.dart';

void main() {
  SafetyController createSafety() => SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );

  Future<void> pumpCall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(home: CallPage(safetyController: createSafety())),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('renders session chrome and toggles mic state', (tester) async {
    await pumpCall(tester);

    expect(find.text('Solace Voice'), findsOneWidget);
    expect(find.text('MIC ON'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic_none_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MUTED'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.videocam_outlined).last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CAM ON'), findsOneWidget);
  });

  testWidgets('ending the session opens the care overlay', (tester) async {
    await pumpCall(tester);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Take good care'), findsOneWidget);
    expect(find.text('Start a new session'), findsOneWidget);
    expect(find.text('Return home'), findsOneWidget);
  });

  testWidgets('supports duplex call mode with WebSocket and audio recorder', (tester) async {
    final ws = CompanionWebSocketService();
    final recorder = PcmAudioRecorderService(isMock: true);
    final tts = TtsPlaybackService(webSocketService: ws, isMock: true);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tts.dispose();
      recorder.dispose();
      ws.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CallPage(
          safetyController: createSafety(),
          webSocketService: ws,
          audioRecorderService: recorder,
          ttsPlaybackService: tts,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Solace Voice'), findsOneWidget);
    expect(find.text('Take your time. Silence is welcome here.'), findsOneWidget);
  });
}
