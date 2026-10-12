import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/call/call_page.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';
import 'package:solace_mobile/services/tts_playback_service.dart';

/// Connected-looking socket whose server events the test drives by hand.
class _FakeCallWs extends CompanionWebSocketService {
  final _transcript = StreamController<Map<String, dynamic>>.broadcast();
  final _llmStart = StreamController<Map<String, dynamic>>.broadcast();
  final _llmChunk = StreamController<Map<String, dynamic>>.broadcast();
  final _ttsEnd = StreamController<Map<String, dynamic>>.broadcast();

  @override
  CompanionConnectionStatus get status => CompanionConnectionStatus.connected;

  @override
  Stream<Map<String, dynamic>> get transcriptFinalStream => _transcript.stream;

  @override
  Stream<Map<String, dynamic>> get llmStartStream => _llmStart.stream;

  @override
  Stream<Map<String, dynamic>> get llmChunkStream => _llmChunk.stream;

  @override
  Stream<Map<String, dynamic>> get ttsEndStream => _ttsEnd.stream;

  void say(String text) => _transcript.add({'text': text});

  void beginReply() => _llmStart.add(const {});

  void replyChunk(String delta) => _llmChunk.add({'delta': delta});

  void endReply({required bool cancelled}) =>
      _ttsEnd.add({'cancelled': cancelled});

  @override
  void dispose() {
    _transcript.close();
    _llmStart.close();
    _llmChunk.close();
    _ttsEnd.close();
    super.dispose();
  }
}

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

    // Unmute restores clean mic state
    await tester.tap(find.byIcon(Icons.mic_none_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MIC ON'), findsOneWidget);

    // The offline demo has Sol speaking, so the raise-hand button is available and toggles to listening
    expect(find.text('RAISE HAND'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.front_hand_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('LISTENING'), findsOneWidget);

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

  testWidgets('call speech and Sol replies are recorded in the chat history',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ws = _FakeCallWs();
    final recorder = PcmAudioRecorderService(isMock: true);
    final tts = TtsPlaybackService(webSocketService: ws, isMock: true);
    final chat = ChatController();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tts.dispose();
      recorder.dispose();
      ws.dispose();
      chat.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CallPage(
          safetyController: createSafety(),
          webSocketService: ws,
          audioRecorderService: recorder,
          ttsPlaybackService: tts,
          chatController: chat,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    List<String> userTexts() => chat.activeConversation!.messages
        .where((m) => m.isUser)
        .map((m) => m.text)
        .toList();
    List<String> solTexts() => chat.activeConversation!.messages
        .where((m) => !m.isUser)
        .map((m) => m.text)
        .toList();

    ws.say('I feel stretched thin today');
    await tester.pump();
    expect(userTexts(), ['I feel stretched thin today']);

    ws.beginReply();
    ws.replyChunk('Hello ');
    ws.replyChunk('there.');
    await tester.pump();
    expect(solTexts(), isNot(contains('Hello there.')),
        reason: 'the reply is only recorded once its speech lands');
    ws.endReply(cancelled: false);
    await tester.pump();
    expect(solTexts().last, 'Hello there.');

    // A barge-in tears the reply down: its half-spoken text stays out.
    ws.beginReply();
    ws.replyChunk('never finished');
    ws.endReply(cancelled: true);
    await tester.pump();
    expect(solTexts(), hasLength(2), reason: 'greeting + the finished reply');

    // Leaving the call mid-reply still keeps what Sol had said.
    ws.beginReply();
    ws.replyChunk('left hanging');
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(solTexts().last, 'left hanging');

    // The conversation has a user turn, so history pruning keeps it.
    chat.pruneEmptyConversations();
    expect(chat.conversations, isNotEmpty);
    expect(userTexts(), ['I feel stretched thin today']);
  });
}
