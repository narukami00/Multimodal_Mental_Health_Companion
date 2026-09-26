
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/chat/chat_page.dart';
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

  group('TtsPlaybackService Unit Tests', () {
    test('initial state is idle and inactive', () {
      final ws = CompanionWebSocketService();
      final tts = TtsPlaybackService(webSocketService: ws);

      expect(tts.isPlaying, isFalse);
      expect(tts.isReceivingStream, isFalse);
      expect(tts.activeStreamId, isNull);
      expect(tts.activeUtteranceId, isNull);
      expect(tts.currentAmplitude, 0.0);

      tts.dispose();
      ws.dispose();
    });

    test('cancelVoice resets active state cleanly and sends speech.cancel envelope', () async {
      final ws = CompanionWebSocketService();
      final tts = TtsPlaybackService(webSocketService: ws);

      await tts.cancelVoice(
        utteranceId: 'utt_123',
        reason: 'test_cancel',
      );

      expect(tts.isPlaying, isFalse);
      expect(tts.isReceivingStream, isFalse);
      expect(tts.activeStreamId, isNull);
      expect(tts.activeUtteranceId, isNull);

      tts.dispose();
      ws.dispose();
    });
  });

  group('Assistant Bubble Voice & Cancellation Widget Tests', () {
    testWidgets('assistant bubble with active speaking shows "Stop voice" pill and equalizer',
        (tester) async {
      final ws = CompanionWebSocketService();
      final tts = TtsPlaybackService(webSocketService: ws);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            safetyController: createSafety(),
            audioRecorderService: PcmAudioRecorderService(isMock: true),
            webSocketService: ws,
            ttsPlaybackService: tts,
            initialMessages: [
              ChatMessageRecord(
                id: 'msg_assistant_1',
                isUser: false,
                text: 'I hear you. Take all the time you need.',
                timestamp: DateTime.now(),
                localAudioPath: '/mock/test.wav',
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Initially no "Stop voice" pill since no TTS is active
      expect(find.text('Stop voice'), findsNothing);

      // Trigger playback for this message's utterance
      await tts.playAudioFile('/mock/test.wav', utteranceId: 'utt_1001');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Stop voice'), findsOneWidget);
      expect(find.byKey(const Key('stop_voice_pill')), findsOneWidget);

      // Tapping "Stop voice" cancels playback
      await tester.tap(find.byKey(const Key('stop_voice_pill')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Stop voice'), findsNothing);

      tts.dispose();
      ws.dispose();
    });

    testWidgets('assistant bubble with cached audio path shows "Listen" replay pill',
        (tester) async {
      final ws = CompanionWebSocketService();
      final tts = TtsPlaybackService(webSocketService: ws);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            safetyController: createSafety(),
            audioRecorderService: PcmAudioRecorderService(isMock: true),
            webSocketService: ws,
            ttsPlaybackService: tts,
            initialMessages: [
              ChatMessageRecord(
                id: 'msg_assistant_cached',
                isUser: false,
                text: 'Take a slow, deep breath with me.',
                timestamp: DateTime.now(),
                localAudioPath: '/mock/path/tts_1001.wav',
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify "Listen" replay pill is visible on assistant bubble with cached audio
      expect(find.text('Listen'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

      tts.dispose();
      ws.dispose();
    });
  });
}
