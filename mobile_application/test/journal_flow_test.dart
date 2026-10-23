import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:solace_mobile/services/face_reader.dart';
import 'package:solace_mobile/services/journal_analysis_client.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';
import 'package:solace_mobile/services/pending_recordings.dart';
import 'package:solace_mobile/services/phone_transcriber.dart';
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
    if (uri.path == '/v1/journal/face_features') return (status: status, body: jsonEncode({'accepted': body.length == 5600}));
    // like the real server: words sent by a phone with its own speech model are used as they are
    final given = uri.queryParameters['words'];
    final answer = given == null || given.isEmpty ? this.body : {...this.body, 'transcript': given};
    return (status: status, body: jsonEncode(answer));
  }

  JournalAnalysisClient client() => JournalAnalysisClient(
        transport: call,
        baseUri: () async => reachable ? Uri.parse('http://x:8000') : null,
      );
}

/// A phone that "hears" a fixed sentence, standing in for the real speech model.
class _FakePhone extends PhoneTranscriber {
  _FakePhone(this.words) : super(files: const WhisperModelFiles('none'));
  final String? words;
  @override
  Future<String?> transcribe(Uint8List pcm16) async => words;
}

/// A camera that hands over frames when the test says so.
class _Camera implements FrameSource {
  final _controller = StreamController<Uint8List>.broadcast();

  /// A real (1 x 1 pixel) image: the page shows each frame as a preview.
  static final _png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
  void shoot() => _controller.add(_png);
  @override
  Stream<Uint8List> get frames => _controller.stream;
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
}

/// A phone that reads the face itself: every frame counts, and the pooled numbers are all 0.5.
class _FakeFaceReader extends FaceReader {
  _FakeFaceReader({this.startWorks = true, this.enoughFrames = true}) : super(runner: _NoRunner());

  final bool startWorks;
  final bool enoughFrames;
  int frames = 0;
  int starts = 0;
  int closes = 0;

  @override
  Future<bool> start(String directory) async {
    starts++;
    return startWorks;
  }

  @override
  Future<FaceReading?> addJpeg(Uint8List jpeg) async {
    frames++;
    return const FaceReading(found: true, usable: true);
  }

  @override
  Float32List? pooled() => enoughFrames ? Float32List.fromList(List.filled(1400, 0.5)) : null;

  @override
  Future<void> close() async => closes++;
}

class _NoRunner implements FaceModelRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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
    Future<void> pump(
      WidgetTester tester, {
      CaptureMode mode = CaptureMode.voice,
      PhoneTranscriber? phone,
      FrameSource? frames,
      FaceReader? faceReader,
      Future<String?> Function()? phoneFaceDirectory,
    }) async {
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
          frameSource: frames ?? _NoSource(),
          transcriberFor: phone == null ? null : () async => phone,
          faceReader: faceReader,
          phoneFaceDirectory: phoneFaceDirectory ?? (faceReader == null ? null : () async => null),
        ),
      ));
      await tester.pump();
    }

    /// Stops a mock recording while the server is away, and waits for the phone to keep it.
    Future<void> recordWhileServerIsAway(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 20 && find.byKey(const ValueKey('journal-saved')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    SessionController withPendingStore() {
      final dir = Directory.systemTemp.createTempSync('journal_phone_');
      addTearDown(() => dir.deleteSync(recursive: true));
      return SessionController(
        repository: InMemorySessionRepository(),
        emotionAnalyzer: ServerEmotionAnalyzer(client: server.client(), consentGranted: () => true),
        pendingRecordings: PendingRecordings(directory: () async => dir),
      );
    }

    testWidgets('with its own speech model the phone writes the words down while the server is away, and the server reads them later', (tester) async {
      sessions = withPendingStore();
      await consent.grant(ConsentKey.emotionEstimate);
      server.reachable = false;
      await pump(tester, phone: _FakePhone('I had a long day and I feel tired.'));
      await recordWhileServerIsAway(tester);

      expect(find.byKey(const ValueKey('journal-transcript')), findsOneWidget);
      expect(find.text('I had a long day and I feel tired.'), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-waiting')), findsNothing);
      final entry = sessions.sessions.single;
      expect(entry.text, 'I had a long day and I feel tired.');
      expect(entry.awaitingRecording, isTrue); // the server will still read how it sounded
      expect(sessions.unread, isEmpty);

      server.reachable = true;
      server.body = {..._answer, 'transcript': 'the server would have written this differently'};
      final done = await tester.runAsync(() => sessions.processPending(analyze: (id, pcm, words, face) => server.client().analyzeAudio(id, pcm, words: words)));
      expect(done, 1);
      expect(server.requests.last.query['words'], 'I had a long day and I feel tired.'); // the phone's words go to the server
      expect(sessions.sessions.single.text, 'I had a long day and I feel tired.'); // and stay: the phone's model wrote them
      expect(sessions.sessions.single.reading, isNotNull);
      expect(sessions.sessions.single.awaitingRecording, isFalse);
    });

    testWidgets('with the phone model installed and the server UP, the phone writes the words and the server only reads for emotion', (tester) async {
      await consent.grant(ConsentKey.emotionEstimate);
      await pump(tester, phone: _FakePhone('Phone words. Properly punctuated.'));
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 20 && find.byKey(const ValueKey('journal-saved')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(server.requests.last.query['words'], 'Phone words. Properly punctuated.');
      expect(find.text('Phone words. Properly punctuated.'), findsOneWidget);
      expect(sessions.sessions.single.text, 'Phone words. Properly punctuated.');
      expect(sessions.sessions.single.reading, isNotNull); // the server still read it
      expect(sessions.sessions.single.awaitingRecording, isFalse);
    });

    testWidgets('without a phone model the server writes the words, as before', (tester) async {
      await consent.grant(ConsentKey.emotionEstimate);
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 20 && find.byKey(const ValueKey('journal-saved')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(server.requests.last.query.containsKey('words'), isFalse);
      expect(sessions.sessions.single.text, 'I had a long day and I feel tired.');
    });

    testWidgets('declining the emotion reading still lets the phone write the words down privately: nothing is sent', (tester) async {
      await pump(tester, phone: _FakePhone('Just for me.'));
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 20 && find.byKey(const ValueKey('consent-decline')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('consent-decline')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      for (var i = 0; i < 20 && find.byKey(const ValueKey('journal-stop')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      for (var i = 0; i < 20 && find.text('Written down on this phone. Nothing was sent anywhere.').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Written down on this phone. Nothing was sent anywhere.'), findsOneWidget);
      expect(server.requests, isEmpty);
      expect(sessions.sessions.single.text, 'Just for me.');
      expect(sessions.sessions.single.reading, isNull);
    });

    testWidgets('crisis words the phone wrote down open Support at once, even with no server', (tester) async {
      sessions = withPendingStore();
      await consent.grant(ConsentKey.emotionEstimate);
      server.reachable = false;
      await pump(tester, phone: _FakePhone('I want to die'));
      await recordWhileServerIsAway(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SupportResourcesPage), findsOneWidget);
      expect(sessions.sessions.single.text, 'I want to die'); // and the entry is still kept
    });

    testWidgets('a phone that heard nothing still keeps the recording for the server', (tester) async {
      sessions = withPendingStore();
      await consent.grant(ConsentKey.emotionEstimate);
      server.reachable = false;
      await pump(tester, phone: _FakePhone(null));
      await recordWhileServerIsAway(tester);

      expect(find.byKey(const ValueKey('journal-waiting')), findsOneWidget);
      expect(sessions.sessions.single.text, isNull);
      expect(sessions.awaitingRecordings, hasLength(1));
    });

    testWidgets('the voice page offers the speech model; the video page groups the speech and camera models in one panel', (tester) async {
      for (final mode in [CaptureMode.voice, CaptureMode.video]) {
        await pump(tester, mode: mode);
        for (var i = 0; i < 10 && find.byKey(const ValueKey('offline-model-card')).evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byKey(const ValueKey('models-panel')), findsOneWidget, reason: '$mode'); // one panel, never two hints
        expect(find.byKey(const ValueKey('offline-model-card')), findsOneWidget, reason: '$mode');
        expect(find.byKey(const ValueKey('face-model-card')), mode == CaptureMode.video ? findsOneWidget : findsNothing, reason: '$mode');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a video journal read on the phone sends only numbers: no pictures, the face numbers first, then the audio', (tester) async {
      await consent.grant(ConsentKey.emotionEstimate);
      await consent.grant(ConsentKey.faceFeatures);
      final camera = _Camera();
      final reader = _FakeFaceReader();
      await pump(tester, mode: CaptureMode.video, frames: camera, faceReader: reader, phoneFaceDirectory: () async => '/models');
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      for (var i = 0; i < 20 && reader.starts == 0; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));
      camera.shoot();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      for (var i = 0; i < 30 && find.byKey(const ValueKey('journal-saved')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(reader.starts, 1);
      expect(reader.frames, 1); // the frame was read on the phone...
      expect(server.requests.where((r) => r.path == '/v1/journal/frame'), isEmpty); // ...and never sent
      final paths = server.requests.map((r) => r.path).toList();
      expect(paths, contains('/v1/journal/face_features'));
      expect(paths.indexOf('/v1/journal/face_features'), lessThan(paths.indexOf('/v1/journal/audio'))); // numbers first
      expect(server.requests.firstWhere((r) => r.path == '/v1/journal/face_features').bytes, 5600);
      expect(server.requests.firstWhere((r) => r.path == '/v1/journal/audio').query['face'], '0'); // the server is not asked to read frames
      expect(find.byKey(const ValueKey('journal-saved')), findsOneWidget);
    });

    testWidgets('when the camera models cannot be opened the server reads the face from frames, exactly as before', (tester) async {
      await consent.grant(ConsentKey.emotionEstimate);
      await consent.grant(ConsentKey.faceFeatures);
      final camera = _Camera();
      final reader = _FakeFaceReader(startWorks: false);
      await pump(tester, mode: CaptureMode.video, frames: camera, faceReader: reader, phoneFaceDirectory: () async => '/models');
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      for (var i = 0; i < 20 && reader.starts == 0; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));
      camera.shoot();
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      for (var i = 0; i < 30 && find.byKey(const ValueKey('journal-saved')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(reader.frames, 0);
      expect(server.requests.where((r) => r.path == '/v1/journal/frame'), isNotEmpty);
      expect(server.requests.where((r) => r.path == '/v1/journal/face_features'), isEmpty);
      expect(server.requests.firstWhere((r) => r.path == '/v1/journal/audio').query['face'], '1');
    });

    testWidgets('with the server away, a video journal keeps the face NUMBERS with the recording, and says so honestly', (tester) async {
      sessions = withPendingStore();
      await consent.grant(ConsentKey.emotionEstimate);
      await consent.grant(ConsentKey.faceFeatures);
      server.reachable = false;
      final camera = _Camera();
      final reader = _FakeFaceReader();
      await pump(tester, mode: CaptureMode.video, frames: camera, faceReader: reader, phoneFaceDirectory: () async => '/models');
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      for (var i = 0; i < 20 && reader.starts == 0; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));
      camera.shoot();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      for (var i = 0; i < 30 && find.byKey(const ValueKey('journal-waiting')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      final entry = sessions.sessions.single;
      expect(entry.awaitingRecording, isTrue);
      expect(entry.awaitingFace, isTrue); // the numbers wait with the audio
      final waiting = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('journal-waiting')), matching: find.byType(Text))).data!;
      expect(waiting, contains('Your face was read on this phone'));
      expect(waiting, contains('never pictures'));
      expect(waiting, isNot(contains('camera is not read')));

      // when the server is back, the numbers go first, then the audio
      server.reachable = true;
      final sentFirst = <String>[];
      await tester.runAsync(() => sessions.processPending(analyze: (id, pcm, words, face) async {
            if (face != null) {
              expect(await server.client().sendFaceFeatures(id, face), isTrue);
              sentFirst.add('face');
            }
            sentFirst.add('audio');
            return server.client().analyzeAudio(id, pcm, words: words);
          }));
      expect(sentFirst, ['face', 'audio']);
      expect(sessions.awaitingRecordings, isEmpty);
    });

    testWidgets('a video journal with too few clear frames carries no face numbers, and says nothing false about them', (tester) async {
      sessions = withPendingStore();
      await consent.grant(ConsentKey.emotionEstimate);
      await consent.grant(ConsentKey.faceFeatures);
      server.reachable = false;
      final reader = _FakeFaceReader(enoughFrames: false);
      await pump(tester, mode: CaptureMode.video, frames: _Camera(), faceReader: reader, phoneFaceDirectory: () async => '/models');
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      for (var i = 0; i < 20 && reader.starts == 0; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      for (var i = 0; i < 30 && find.byKey(const ValueKey('journal-waiting')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sessions.sessions.single.awaitingFace, isFalse);
      final waiting = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('journal-waiting')), matching: find.byType(Text))).data!;
      expect(waiting, isNot(contains('Your face was read on this phone')));
    });

    testWidgets('before starting it offers something to talk about, not a blank screen', (tester) async {
      await pump(tester);

      expect(find.text('YOU COULD START WITH'), findsOneWidget);
    });

    testWidgets('the video page guides the face into the frame', (tester) async {
      await pump(tester, mode: CaptureMode.video);

      expect(find.text('Centre your face in the oval'), findsOneWidget);
    });

    testWidgets('records, writes it down, saves it as a voice entry with its own reading, and nobody replies', (tester) async {
      await pump(tester);
      expect(find.text('Voice journal'), findsOneWidget);
      expect(find.textContaining('Nobody replies'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('emotion-consent-sheet')), findsOneWidget); // asked once, when it is needed
      await tester.tap(find.byKey(const ValueKey('consent-allow')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('journal-stop')), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      for (var i = 0; i < 20 && find.byKey(const ValueKey('journal-saved')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the page first looks for a phone speech model
        await tester.pump(const Duration(milliseconds: 100));
      }

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
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('consent-decline')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
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
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 20 && find.byKey(const ValueKey('journal-retry')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the page first looks for a phone speech model
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('journal-retry')), findsOneWidget);
      expect(sessions.sessions, isEmpty);

      server.reachable = true;
      await tester.tap(find.byKey(const ValueKey('journal-retry')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('journal-saved')), findsOneWidget);
      expect(sessions.sessions, hasLength(1));
    });

    testWidgets('an unreachable server does not stop the journal: the recording waits on the phone and is written down later', (tester) async {
      final dir = Directory.systemTemp.createTempSync('journal_wait_');
      addTearDown(() => dir.deleteSync(recursive: true));
      sessions = SessionController(
        repository: InMemorySessionRepository(),
        emotionAnalyzer: ServerEmotionAnalyzer(client: server.client(), consentGranted: () => true),
        pendingRecordings: PendingRecordings(directory: () async => dir),
      );
      await consent.grant(ConsentKey.emotionEstimate);
      server.reachable = false;
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      // Saving the recording is real file I/O in several steps: give it real time, then let the page catch up.
      for (var i = 0; i < 20 && find.byKey(const ValueKey('journal-waiting')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(const ValueKey('journal-waiting')), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-retry')), findsNothing);
      expect(sessions.awaitingRecordings, hasLength(1));
      expect(dir.listSync(), hasLength(1)); // the recording is on the phone

      server.reachable = true;
      final done = await tester.runAsync(() => sessions.processPending(analyze: (id, pcm, words, face) => server.client().analyzeAudio(id, pcm, words: words)));
      expect(done, 1);
      expect(sessions.awaitingRecordings, isEmpty);
      expect(server.requests.last.query['words'], isNull); // this entry had no phone words, so the server wrote them
      expect(sessions.sessions.single.text, 'I had a long day and I feel tired.');
      expect(sessions.sessions.single.reading, isNotNull);
      expect(dir.listSync(), isEmpty); // deleted once the server has read it
    });

    testWidgets('crisis words in a recording open Support and still keep the entry', (tester) async {
      await consent.grant(ConsentKey.emotionEstimate);
      server.body = {..._answer, 'transcript': 'I want to die', 'safety': 'urgent_support'};
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('journal-start')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80))); // the page first looks for a phone speech model
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('journal-stop')));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 20 && find.byType(SupportResourcesPage).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(SupportResourcesPage), findsOneWidget);
      expect(sessions.sessions, hasLength(1));
    });
  });
}
