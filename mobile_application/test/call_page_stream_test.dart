import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/call/call_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';
import 'package:solace_mobile/services/tts_playback_service.dart';

/// A connected-looking socket that records what the call page puts on the wire
/// and lets the test play the server's part.
class _CallWs extends CompanionWebSocketService {
  final List<String> sent = <String>[];
  final List<Uint8List> frames = <Uint8List>[];

  CompanionConnectionStatus _fakeStatus = CompanionConnectionStatus.connected;
  final _statusCtl = StreamController<CompanionConnectionStatus>.broadcast();
  final _turnStarted = StreamController<Map<String, dynamic>>.broadcast();
  final _endpointed = StreamController<Map<String, dynamic>>.broadcast();
  final _discarded = StreamController<Map<String, dynamic>>.broadcast();
  final _interrupted = StreamController<Map<String, dynamic>>.broadcast();
  final _callState = StreamController<Map<String, dynamic>>.broadcast();
  final _ttsEnd = StreamController<Map<String, dynamic>>.broadcast();

  @override
  CompanionConnectionStatus get status => _fakeStatus;
  @override
  Stream<CompanionConnectionStatus> get statusStream => _statusCtl.stream;
  @override
  Stream<Map<String, dynamic>> get turnStartedStream => _turnStarted.stream;
  @override
  Stream<Map<String, dynamic>> get turnEndpointedStream => _endpointed.stream;
  @override
  Stream<Map<String, dynamic>> get turnDiscardedStream => _discarded.stream;
  @override
  Stream<Map<String, dynamic>> get turnInterruptedStream => _interrupted.stream;
  @override
  Stream<Map<String, dynamic>> get callStateStream => _callState.stream;
  @override
  Stream<Map<String, dynamic>> get ttsEndStream => _ttsEnd.stream;

  void setStatus(CompanionConnectionStatus next) {
    _fakeStatus = next;
    _statusCtl.add(next);
  }

  void serverHeardSpeech() => _turnStarted.add({'turn_id': 'srv_1'});
  void serverEndedTurn() => _endpointed.add({'turn_id': 'srv_1', 'speech_ms': 900});
  void serverDiscarded() =>
      _discarded.add({'turn_id': 'srv_1', 'reason': 'unintelligible'});
  void serverInterrupted() =>
      _interrupted.add({'turn_id': 'srv_1', 'played_ms': 800});
  void serverState(String state) => _callState.add({'state': state});
  void serverEndedAudio({bool cancelled = false}) =>
      _ttsEnd.add({'cancelled': cancelled});

  @override
  Future<void> sendSessionConfigure({
    required String mode,
    bool ttsEnabled = true,
    String voiceId = 'af_heart',
    double speed = 0.96,
    int micSampleRate = 16000,
    int playbackSampleRate = 24000,
    String codec = 'pcm_s16le',
    Map<String, dynamic>? vad,
    Map<String, Object?>? resume,
  }) async {
    sent.add('configure:$mode');
  }

  @override
  Future<void> sendCallListen({bool bargeIn = false}) async =>
      sent.add('listen:$bargeIn');

  @override
  Future<void> sendCallMute({required bool muted}) async =>
      sent.add('mute:$muted');

  @override
  Future<void> sendCallConfig({required bool bargeIn}) async =>
      sent.add('config:$bargeIn');

  @override
  Future<void> sendCallBargeIn({
    String? turnId,
    String? utteranceId,
    String reason = 'vad_speech_detected',
  }) async =>
      sent.add('barge_in:$reason');

  @override
  Future<void> sendCallEnd({String reason = 'user_ended_call'}) async =>
      sent.add('end:$reason');

  @override
  void sendAudioChunk(Uint8List chunk, {bool framed = false}) {
    frames.add(chunk);
    sent.add('frame');
  }

  @override
  void dispose() {
    _statusCtl.close();
    _turnStarted.close();
    _endpointed.close();
    _discarded.close();
    _interrupted.close();
    _callState.close();
    _ttsEnd.close();
    super.dispose();
  }
}

/// A recorder whose every frame is loud, so a frame that arrives silent was
/// silenced on purpose.
class _LoudRecorder extends PcmAudioRecorderService {
  _LoudRecorder({this.headset = false})
      : super(isMock: true, mockSpeechMs: 600000, mockSilenceMs: 20);

  final bool headset;

  @override
  Future<bool> isHeadsetConnected() async => headset;
}

bool _silent(Uint8List frame) => frame.every((b) => b == 0);

void main() {
  SafetyController createSafety() => SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );

  late _CallWs ws;
  late _LoudRecorder recorder;
  late TtsPlaybackService tts;

  Future<void> startCall(
    WidgetTester tester, {
    bool headset = false,
  }) async {
    ws = _CallWs();
    recorder = _LoudRecorder(headset: headset);
    tts = TtsPlaybackService(webSocketService: ws, isMock: true);
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
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the call announces itself, then streams every frame', (tester) async {
    await startCall(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(ws.sent.first, 'configure:duplex_call');
    expect(ws.sent, contains('listen:false'));
    expect(ws.sent.indexOf('listen:false'), lessThan(ws.sent.indexOf('frame')),
        reason: 'the server must know a call began before it gets audio');
    expect(ws.frames.length, greaterThan(10),
        reason: 'no turn is opened by the phone: audio simply flows');
    expect(ws.frames.every((f) => !_silent(f)), isTrue,
        reason: 'with nothing playing, the server gets the real microphone');
  });

  testWidgets('on a loudspeaker the server hears silence while Sol is audible',
      (tester) async {
    await startCall(tester);
    await tester.pump(const Duration(milliseconds: 100));
    ws.frames.clear();

    await tts.playAudioFile('/mock/a.wav', utteranceId: 'u1');
    await tester.pump(const Duration(milliseconds: 400));
    expect(ws.frames, isNotEmpty);
    expect(ws.frames.every(_silent), isTrue,
        reason: 'her own voice would come straight back in');
    // Silence, not a gap: the server counts samples, so the timeline stays whole.
    expect(ws.frames.first.length, 640);

    await tts.stopVoice(fadeMs: 0);
    ws.frames.clear();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ws.frames.every(_silent), isTrue,
        reason: 'the room still rings for ~300 ms after she stops');

    await tester.pump(const Duration(milliseconds: 400));
    ws.frames.clear();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ws.frames, isNotEmpty);
    expect(ws.frames.every((f) => !_silent(f)), isTrue,
        reason: 'then the person is heard again');
  });

  testWidgets('on headphones the microphone stays open and talking over Sol is allowed',
      (tester) async {
    await startCall(tester, headset: true);
    expect(ws.sent, contains('listen:true'));

    await tts.playAudioFile('/mock/a.wav', utteranceId: 'u1');
    ws.frames.clear();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ws.frames, isNotEmpty);
    expect(ws.frames.every((f) => !_silent(f)), isTrue);
  });

  testWidgets('muting tells the server and stops the audio; unmuting resumes it',
      (tester) async {
    await startCall(tester);
    await tester.tap(find.byIcon(Icons.mic_none_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ws.sent, contains('mute:true'));

    ws.frames.clear();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ws.frames, isEmpty);

    await tester.tap(find.byIcon(Icons.mic_none_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ws.sent.last, isNot('mute:true'));
    expect(ws.sent, contains('mute:false'));
    expect(ws.frames, isNotEmpty);
  });

  testWidgets('raise hand silences Sol, tells the server, and opens the microphone at once',
      (tester) async {
    await startCall(tester);
    await tts.playAudioFile('/mock/a.wav', utteranceId: 'u1');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tts.isPlaying, isTrue);

    await tester.tap(find.byIcon(Icons.front_hand_rounded), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tts.isPlaying, isFalse);
    expect(ws.sent, contains('barge_in:user_raised_hand'));

    ws.frames.clear();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ws.frames, isNotEmpty);
    expect(ws.frames.every((f) => !_silent(f)), isTrue,
        reason: 'no echo tail for someone who asked for the floor');
    expect(find.text('LISTENING'), findsOneWidget);
  });

  testWidgets('the header follows what the server and the speaker report',
      (tester) async {
    await startCall(tester);
    expect(find.text('Listening · take your time'), findsOneWidget);

    ws.serverHeardSpeech();
    await tester.pump();
    expect(find.text('Listening to you...'), findsOneWidget);

    ws.serverEndedTurn();
    await tester.pump();
    expect(find.text('Thinking...'), findsOneWidget);

    await tts.playAudioFile('/mock/a.wav', utteranceId: 'u1');
    await tester.pump();
    expect(find.text('Solace speaking'), findsOneWidget,
        reason: 'speaking means the speaker is making sound');

    await tts.stopVoice(fadeMs: 0);
    await tester.pump();
    expect(find.text('Listening · take your time'), findsOneWidget);
  });

  testWidgets('a turn the server could not make out hands the floor back',
      (tester) async {
    await startCall(tester);
    ws.serverHeardSpeech();
    ws.serverEndedTurn();
    await tester.pump();
    expect(find.text('Thinking...'), findsOneWidget);

    ws.serverDiscarded();
    await tester.pump();
    expect(find.text('Listening · take your time'), findsOneWidget);
  });

  testWidgets('a server that settles back to listening ends a stale thinking state',
      (tester) async {
    await startCall(tester);
    ws.serverHeardSpeech();
    ws.serverEndedTurn();
    await tester.pump();
    expect(find.text('Thinking...'), findsOneWidget);

    ws.serverState('idle');
    await tester.pump();
    expect(find.text('Listening · take your time'), findsOneWidget);
  });

  testWidgets('server-side barge-in stops Sol mid-word', (tester) async {
    await startCall(tester, headset: true);
    await tts.playAudioFile('/mock/a.wav', utteranceId: 'u1');
    await tester.pump(const Duration(milliseconds: 100));
    expect(tts.isPlaying, isTrue);

    ws.serverInterrupted();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tts.isPlaying, isFalse);
    expect(find.text('Listening to you...'), findsOneWidget);
  });

  testWidgets('a dropped connection stops the audio and resumes the call on return',
      (tester) async {
    await startCall(tester);
    ws.setStatus(CompanionConnectionStatus.connecting);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Reconnecting...'), findsOneWidget,
        reason: 'a call that cannot hear must say so, not look fine');

    ws.sent.clear();
    ws.frames.clear();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ws.frames, isEmpty, reason: 'audio sent into a dead socket is lost');

    ws.setStatus(CompanionConnectionStatus.connected);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ws.sent.take(2).toList(), ['configure:duplex_call', 'listen:false'],
        reason: 'the server session is new: call and configuration come first');
    expect(ws.sent, contains('frame'));
    expect(find.text('Reconnecting...'), findsNothing);
  });

  testWidgets('hanging up ends the call on the server', (tester) async {
    await startCall(tester);
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump(const Duration(milliseconds: 600));
    expect(ws.sent.any((e) => e.startsWith('end:')), isTrue);
    expect(ws.sent, contains('configure:chat_voice_playback'));
  });
}
