import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/journal/journal_capture_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/safety/support_resources_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/providers/server/server_emotion_analyzer.dart';
import 'package:solace_mobile/services/journal_analysis_client.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';
import 'package:solace_mobile/services/video_frame_service.dart';

const _answer = <String, dynamic>{
  'transcript': 'I had a long day and I feel tired.',
  'safety': null,
  'confidence': 0.9,
  'duration_s': 3.0,
  'emotion': {
    'pattern': 'AT',
    'mood': 'low or tired',
    'tier': 'clear',
    'valence': -0.6,
    'arousal': -0.4,
    'model_version': 'test',
    'estimate': {
      'l7': {'sad': 0.5, 'neutral': 0.3, 'happy': 0.2},
      'lv': {'negative': 0.7, 'neutral': 0.2, 'positive': 0.1},
      'la': {'low': 0.6, 'mid': 0.3, 'high': 0.1},
    },
  },
};

/// A transport that records requests and answers like the companion server.
class _Server {
  bool reachable = true;
  Map<String, dynamic> body = _answer;
  int status = 200;
  final requests = <({String path, Map<String, String> query, int bytes})>[];

  Future<({int status, String body})> call({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int> body,
    required Duration timeout,
  }) async {
    if (!reachable) throw Exception('unreachable');
    requests.add((path: uri.path, query: uri.queryParameters, bytes: body.length));
    return (status: status, body: jsonEncode(this.body));
  }

  JournalAnalysisClient client() => JournalAnalysisClient(
        transport: call,
        baseUri: () async => reachable ? Uri.parse('http://x:8000') : null,
      );
}

class _NoSource implements FrameSource {
  @override
  Stream<Uint8List> get frames => const Stream.empty();
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
}

void main() {
  late ConsentController consent;
  late SessionController sessions;
  late SafetyController safety;
  late _Server server;

  setUp(() async {
    consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    server = _Server();
    sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: ServerEmotionAnalyzer(
        client: server.client(),
        consentGranted: () => consent.isGranted(ConsentKey.emotionEstimate),
      ),
    );
    safety = SafetyController(
      screener: const KeywordSafetyScreener(),
      repository: InMemorySafetyEventRepository(),
    );
  });

  group('the client', () {
    test('sends text and recordings to the journal endpoints and returns null when the server is away', () async {
      final c = server.client();
      final text = await c.analyzeText('s1', 'hello');
      expect(text!.transcript, 'I had a long day and I feel tired.');
      expect(server.requests.last.path, '/v1/journal/text');
      await c.analyzeAudio('s1', Uint8List(64000), face: true);
      expect(server.requests.last.path, '/v1/journal/audio');
      expect(server.requests.last.query, {'session_id': 's1', 'sample_rate': '16000', 'face': '1'});

      server.reachable = false;
      expect(await server.client().analyzeText('s1', 'hello'), isNull);
      server.reachable = true;
      server.status = 503;
      expect(await server.client().analyzeText('s1', 'hello'), isNull);
    });
  });

  group('typed entries', () {
    test('are read by the model only with the persons consent, and never invented', () async {
      final without = await sessions.saveSession(mode: CaptureMode.text, text: 'I feel tired.');
      expect(without.reading, isNull); // no consent: saved without a reading
      expect(server.requests, isEmpty);

      await consent.grant(ConsentKey.emotionEstimate);
      final withConsent = await sessions.saveSession(mode: CaptureMode.text, text: 'I feel tired.');
      expect(withConsent.reading?.mood, 'low or tired');
      expect(withConsent.effectiveMood, 'Tender');

      server.reachable = false;
      final offline = await sessions.saveSession(mode: CaptureMode.text, text: 'And again.');
      expect(offline.reading, isNull); // the server is away: no reading, no fake one
    });

    test('earlier entries can be read afterwards, one by one, and stop when the server goes away', () async {
      await sessions.saveSession(mode: CaptureMode.text, text: 'one');
      await Future<void>.delayed(const Duration(milliseconds: 2)); // entry ids are microsecond timestamps
      await sessions.saveSession(mode: CaptureMode.voice, text: 'two');
      expect(sessions.unread, hasLength(2));
      await consent.grant(ConsentKey.emotionEstimate);
      expect(await sessions.reanalyzeUnread(), 2);
      expect(sessions.unread, isEmpty);
      expect(sessions.sessions.every((s) => s.reading != null), isTrue);

      server.reachable = false;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await sessions.saveSession(mode: CaptureMode.text, text: 'three'); // saved while the server is away: no reading
      expect(await sessions.reanalyzeUnread(), 0); // unreachable: nothing changed, nothing broken
      expect(sessions.unread, hasLength(1));
    });
  });

  group('the voice journal', () {
    Future<void> pump(WidgetTester tester, {CaptureMode mode = CaptureMode.voice}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        home: JournalCapturePage(
          mode: mode,
          sessionController: sessions,
          safetyController: safety,
          consentController: consent,
          client: server.client(),
          recorder: PcmAudioRecorderService(isMock: true, mockSpeechMs: 600000, mockSilenceMs: 20),
          frameSource: _NoSource(),
        ),
      ));
      await tester.pump();
    }

    testWidgets('records, writes it down, saves it as a voice entry with its own reading, and nobody replies', (tester) async {
      await pump(tester);
      expect(find.text('Voice journal'), findsOneWidget);
      expect(find.textContaining('Nobody replies'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('emotion-consent-sheet')), findsOneWidget); // asked once, when it is needed
      await tester.tap(find.byKey(const ValueKey('consent-allow')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('journal-stop')), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('journal-saved')), findsOneWidget);
      expect(find.text('I had a long day and I feel tired.'), findsOneWidget);
      expect(sessions.sessions, hasLength(1));
      final saved = sessions.sessions.single;
      expect(saved.mode, CaptureMode.voice);
      expect(saved.reading?.pattern, 'AT');
      expect(server.requests.last.path, '/v1/journal/audio');
      expect(server.requests.last.bytes, greaterThan(16000)); // the whole recording went up, once
    });

    testWidgets('without the persons OK nothing is recorded or sent', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('consent-decline')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('journal-start')), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-message')), findsOneWidget);
      expect(server.requests, isEmpty);
      expect(sessions.sessions, isEmpty);
    });

    testWidgets('an unreachable server keeps the recording in memory for a retry and saves nothing', (tester) async {
      await consent.grant(ConsentKey.emotionEstimate);
      server.reachable = false;
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('journal-retry')), findsOneWidget);
      expect(sessions.sessions, isEmpty);

      server.reachable = true;
      await tester.tap(find.byKey(const ValueKey('journal-retry')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('journal-saved')), findsOneWidget);
      expect(sessions.sessions, hasLength(1));
    });

    testWidgets('crisis words in a recording open Support and still keep the entry', (tester) async {
      await consent.grant(ConsentKey.emotionEstimate);
      server.body = {..._answer, 'transcript': 'I want to die', 'safety': 'urgent_support'};
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SupportResourcesPage), findsOneWidget);
      expect(sessions.sessions, hasLength(1));
    });
  });
}
