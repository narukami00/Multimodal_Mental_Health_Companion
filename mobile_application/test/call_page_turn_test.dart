import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/call/call_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/audio_processor.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';
import 'package:solace_mobile/services/tts_playback_service.dart';

/// Looks connected and records what the page puts on the wire instead of
/// touching a socket.
class _RecordingWs extends CompanionWebSocketService {
  final List<String> events = <String>[];

  @override
  CompanionConnectionStatus get status => CompanionConnectionStatus.connected;

  @override
  Future<void> sendInputStart({
    required String turnId,
    int preRollMs = 600,
    bool framed = true,
    int sampleRate = 16000,
    int channels = 1,
    int frameMs = 20,
    String mode = 'duplex_call',
  }) async {
    events.add('input_start');
  }

  @override
  void sendAudioChunk(Uint8List chunk, {bool framed = false}) {
    events.add('frame');
  }

  @override
  Future<void> sendInputEnd({
    required String turnId,
    int durationMs = 0,
    String reason = 'client_endpoint',
  }) async {
    events.add('input_end:$reason');
  }
}

void main() {
  SafetyController createSafety() => SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );

  testWidgets(
      'gate onset opens a turn, the silence deadline closes it, and the next '
      'utterance opens another', (tester) async {
    final ws = _RecordingWs();
    var nowMs = 0;
    // 400 ms of speech, then 1600 ms of quiet: long enough for the 700 ms
    // endpoint deadline to land inside the gap, and long enough to prove the
    // following burst starts a second turn rather than reviving the first.
    final recorder = PcmAudioRecorderService(
      isMock: true,
      mockSpeechMs: 400,
      mockSilenceMs: 1600,
      processor: AudioProcessor(clockMs: () => nowMs),
    );
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

    // Gate deadlines read wall time, so the test steps that clock alongside
    // the pumped timers.
    Future<void> advance(int ms) async {
      nowMs += ms;
      await tester.pump(Duration(milliseconds: ms));
    }

    await advance(300);
    expect(ws.events, contains('input_start'),
        reason: 'the first loud frame must open a turn');
    expect(ws.events, contains('frame'),
        reason: 'the pre-roll must leave with input.start');
    expect(find.text('Listening to you...'), findsOneWidget);

    while (nowMs < 1600) {
      await advance(100);
    }
    expect(
      ws.events.where((e) => e.startsWith('input_end')),
      hasLength(1),
      reason: 'the silence deadline must close the turn exactly once',
    );
    expect(ws.events, contains('input_end:client_endpoint'));

    while (nowMs < 2400) {
      await advance(100);
    }
    expect(
      ws.events.where((e) => e == 'input_start'),
      hasLength(2),
      reason: 'the next utterance must open its own turn',
    );
  });
}
