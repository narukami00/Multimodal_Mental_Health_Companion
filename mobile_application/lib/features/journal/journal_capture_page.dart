import '../camera/self_view.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../core/widgets/page_back_button.dart';
import '../../services/journal_analysis_client.dart';
import '../../services/face_reader.dart';
import '../../services/face_reading_choice.dart';
import '../../services/pcm_audio_recorder_service.dart';
import '../../services/phone_speech.dart';
import '../../services/phone_transcriber.dart';
import '../../services/platform_frame_source.dart';
import '../../services/stt_model_store.dart';
import '../models/on_device_model_widgets.dart';
import '../../services/video_frame_service.dart';
import '../consent/consent_controller.dart';
import '../consent/emotion_consent_sheets.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
import 'journal_ui.dart';
import 'session_detail_page.dart';

enum _Phase { ready, recording, analysing, done, failed }

/// A voice or video journal entry: the person talks to themselves, nobody
/// answers. The recording is written down and read for emotion by the
/// companion server, then saved to the journal as a transcript marked with its
/// medium. The recording itself is kept only in memory (so a failed upload can
/// be retried) and never saved.
class JournalCapturePage extends StatefulWidget {
  const JournalCapturePage({
    required this.mode,
    required this.sessionController,
    required this.safetyController,
    required this.consentController,
    this.profileController,
    this.client,
    this.recorder,
    this.frameSource,
    this.modelStore,
    this.faceModelStore,
    this.transcriberFor,
    this.faceReader,
    this.phoneFaceDirectory,
    super.key,
  }) : assert(mode != CaptureMode.text);

  /// Replaceable for tests: where the offline speech and camera models live, and how to get a transcriber from them.
  final SttModelStore? modelStore;
  final FaceModelStore? faceModelStore;
  final Future<PhoneTranscriber?> Function()? transcriberFor;

  final CaptureMode mode;
  final SessionController sessionController;
  final SafetyController safetyController;
  final ConsentController consentController;
  final ProfileController? profileController;

  /// Replaceable for tests.
  final JournalAnalysisClient? client;
  final PcmAudioRecorderService? recorder;
  final FrameSource? frameSource;

  /// Replaceable for tests: the on-phone face reader, and where its models are (null: the server reads the face).
  final FaceReader? faceReader;
  final Future<String?> Function()? phoneFaceDirectory;

  @override
  State<JournalCapturePage> createState() => _JournalCapturePageState();
}

class _JournalCapturePageState extends State<JournalCapturePage> {
  static const _ink = Color(0xFF3A3125);
  static const _soft = Color(0xFF8A7A61);
  static const _warm = Color(0xFFFFB534);
  static const _maxSeconds = 170; // the server reads up to 180 s

  late final JournalAnalysisClient _client = widget.client ?? JournalAnalysisClient();
  late final PcmAudioRecorderService _recorder = widget.recorder ?? PcmAudioRecorderService();
  late final FrameSource _frames = widget.frameSource ?? PlatformFrameSource();

  _Phase _phase = _Phase.ready;
  bool get _video => widget.mode == CaptureMode.video;

  final _pcm = BytesBuilder(copy: false);
  Uint8List? _held; // the finished recording, in memory only, so a failed upload can be retried
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<double>? _levelSub;
  Timer? _clock;
  int _seconds = 0;
  double _level = 0;
  Uint8List? _preview;
  bool _faceAllowed = false;
  bool? _faceUsable;
  DateTime _lastFrameSent = DateTime.fromMillisecondsSinceEpoch(0);
  late String _recordingId;
  String _message = '';
  SessionRecord? _saved;
  String _transcript = '';
  bool _waiting = false; // saved while the server was away: the server reads how it sounded later
  bool _waitingFace = false; // ...and, when the phone read the face itself, how the person looked (numbers only)

  // The person said no to emotion reading, so this entry is only written down, on this phone: nothing is sent anywhere.
  bool _privateOnly = false;

  // Reading the face on the phone (only when the person chose that and the camera models are installed).
  bool _phoneFace = false;
  Float32List? _faceVector; // the pooled 1,400 numbers for the recording being held
  bool _readingFrame = false;
  FaceReader get _faceReader => widget.faceReader ?? PhoneFace.reader;

  SttModelStore get _store => widget.modelStore ?? PhoneSpeech.store;

  String? _heldWords; // what the phone wrote for the recording being held (asked once, kept for a retry)
  bool _heldWordsTried = false;

  Future<String?> _phoneWordsFor(Uint8List pcm) async {
    if (!_heldWordsTried) {
      _heldWords = await _writeDownOnPhone(pcm);
      _heldWordsTried = true;
    }
    return _heldWords;
  }

  /// What the phone can write down by itself, or null when its speech model is not installed or heard nothing.
  Future<String?> _writeDownOnPhone(Uint8List pcm) async {
    final transcriber = await (widget.transcriberFor ?? PhoneSpeech.transcriber)();
    return transcriber?.transcribe(pcm);
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_audioSub?.cancel());
    unawaited(_frameSub?.cancel());
    unawaited(_levelSub?.cancel());
    unawaited(_recorder.stopRecording());
    unawaited(_frames.stop());
    if (_phoneFace) unawaited(_faceReader.close()); // the camera models are only held while a video journal is open
    if (widget.recorder == null) _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final consent = widget.consentController;
    final emotionAllowed = await askEmotionConsent(context, consent);
    if (!mounted) return;
    // Saying no to emotion reading must not stop someone journaling: a phone that can write the words down itself still
    // can, and then nothing at all is sent to the server.
    final phoneCanWrite = await (widget.transcriberFor ?? PhoneSpeech.transcriber)() != null;
    if (!mounted) return;
    if (!emotionAllowed && !phoneCanWrite) {
      setState(() => _message = 'To write a recording down, Solace needs either your OK to send it to your companion server, '
          'or the offline transcription model on this phone (you can get it below).');
      return;
    }
    _privateOnly = !emotionAllowed;
    _faceAllowed = false;
    if (_video && !_privateOnly) {
      _faceAllowed = consent.isGranted(ConsentKey.faceFeatures) || await askFaceConsent(context, consent);
      if (!mounted) return;
    }
    // The person may have chosen to read their face on the phone. That needs the camera models and an Android that can
    // run them; if the models cannot be opened the server reads the face, exactly as before (and the person is told).
    _phoneFace = false;
    _faceVector = null;
    var faceNote = '';
    if (_video && _faceAllowed) {
      final directory = await (widget.phoneFaceDirectory ?? PhoneFace.directoryForPhoneReading)();
      if (directory != null) {
        _phoneFace = await _faceReader.start(directory);
        if (!_phoneFace) faceNote = "Couldn't start reading your face on this phone, so your companion server will read it instead.";
      }
      if (!mounted) return;
    }
    _recordingId = DateTime.now().microsecondsSinceEpoch.toString();
    _pcm.clear();
    _held = null;
    _heldWords = null;
    _heldWordsTried = false;
    _seconds = 0;
    _message = faceNote;
    _preview = null;
    _faceUsable = null;
    if (!await _recorder.startRecording()) {
      setState(() => _message = 'The microphone could not be opened. Check the microphone permission and try again.');
      return;
    }
    _audioSub = _recorder.audioStream.listen(_pcm.add);
    _levelSub = _recorder.amplitudeStream.listen((value) {
      if (mounted) setState(() => _level = value.clamp(0.0, 1.0));
    });
    if (_video) {
      if (await _frames.start()) {
        _frameSub = _frames.frames.listen(_onFrame);
      } else {
        _message = 'The camera could not be opened, so this will be a voice entry.';
      }
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= _maxSeconds) unawaited(_stop());
    });
    setState(() => _phase = _Phase.recording);
  }

  void _onFrame(Uint8List jpeg) {
    if (!mounted) return;
    setState(() => _preview = jpeg);
    final now = DateTime.now();
    if (_faceAllowed && now.difference(_lastFrameSent) >= const Duration(seconds: 1)) {
      _lastFrameSent = now;
      if (_phoneFace) {
        // Read on the phone: the picture goes no further than this call; only numbers are kept.
        if (!_readingFrame) {
          _readingFrame = true;
          unawaited(_faceReader.addJpeg(jpeg).then((reading) {
            if (mounted && reading != null) setState(() => _faceUsable = reading.usable);
          }).whenComplete(() => _readingFrame = false));
        }
        if (kFaceCompareWithServer) unawaited(_client.sendFrame(_recordingId, jpeg)); // testing builds only
      } else {
        unawaited(_client.sendFrame(_recordingId, jpeg).then((usable) {
          if (mounted && usable != null) setState(() => _faceUsable = usable);
        }));
      }
    }
  }

  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    _clock?.cancel();
    unawaited(_audioSub?.cancel());
    unawaited(_frameSub?.cancel());
    unawaited(_levelSub?.cancel());
    await _recorder.stopRecording();
    await _frames.stop();
    _held = _pcm.takeBytes();
    if (_phoneFace) {
      for (var i = 0; i < 20 && _readingFrame; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50)); // let a frame that is being read finish
      }
      _faceVector = _faceReader.pooled();
    }
    if (!mounted) return;
    if (_held!.length < 16000 * 2) {
      setState(() {
        _phase = _Phase.failed;
        _message = 'That was too short to write down. Try again and say a little more.';
        _held = null;
      });
      return;
    }
    setState(() => _phase = _Phase.analysing);
    await _analyse();
  }

  Future<void> _analyse() async {
    final pcm = _held;
    if (pcm == null) return;
    setState(() => _phase = _Phase.analysing);
    if (_privateOnly) return _finishPrivately(pcm);
    // A phone with its own speech model always writes the words itself (server up or not); the server then only
    // reads the recording for emotion. Without the model, the server writes the words down as before.
    final phoneWords = await _phoneWordsFor(pcm);
    if (!mounted) return;
    // A face the phone read itself goes first, as numbers only, so the server reads voice, words and face together.
    final faceVector = _faceVector;
    if (faceVector != null) await _client.sendFaceFeatures(_recordingId, faceVector);
    if (!mounted) return;
    final analysis = await _client.analyzeAudio(_recordingId, pcm, face: _faceAllowed && (!_phoneFace || kFaceCompareWithServer), words: phoneWords);
    if (!mounted) return;
    if (analysis == null) {
      // The server is not there right now. Journaling must not wait for it: keep the recording on the
      // phone, save the entry as "waiting", and let the app read it for emotion when the server answers.
      final waiting = await widget.sessionController.savePendingRecording(mode: widget.mode, pcm: pcm, text: phoneWords, faceVector: faceVector);
      if (!mounted) return;
      if (waiting != null) {
        _held = null;
        setState(() {
          _phase = _Phase.done;
          _saved = waiting;
          _transcript = waiting.text ?? '';
          _waiting = true;
          _waitingFace = waiting.awaitingFace;
        });
        if (waiting.text != null) await _screenWords(waiting.text!);
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _message = "Couldn't reach the companion server, so nothing was written down. "
            'Your recording is still held here, not saved anywhere. Try again.';
      });
      return;
    }
    if (analysis.transcript.isEmpty) {
      setState(() {
        _phase = _Phase.failed;
        _held = null;
        _message = "I couldn't make out any words. Try again a little closer to the microphone.";
      });
      return;
    }
    final session = await widget.sessionController.saveAnalyzed(
      mode: widget.mode,
      text: analysis.transcript,
      emotionResults: (id) => analysis.toResults(sessionId: id),
    );
    _held = null; // the recording is gone for good
    if (!mounted) return;
    setState(() {
      _phase = _Phase.done;
      _saved = session;
      _transcript = analysis.transcript;
    });
    final level = switch (analysis.safety) {
      'urgent_support' => SafetyLevel.urgentSupport,
      'support_suggested' => SafetyLevel.supportSuggested,
      _ => null,
    };
    if (level != null) {
      final assessment = await widget.safetyController.assessSignal(
        source: 'journal',
        assessment: SafetyAssessment(level: level, matchedSignals: const ['server_safety_gate']),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportResourcesPage(
            safetyController: widget.safetyController,
            profileController: widget.profileController,
            assessment: assessment,
          ),
        ),
      );
    }
  }

  /// Writes the recording down on the phone and keeps only the words: no emotion reading, and nothing sent anywhere.
  Future<void> _finishPrivately(Uint8List pcm) async {
    final words = await _phoneWordsFor(pcm);
    if (!mounted) return;
    if (words == null) {
      setState(() {
        _phase = _Phase.failed;
        _held = null;
        _message = "I couldn't make out any words. Try again a little closer to the microphone.";
      });
      return;
    }
    final session = await widget.sessionController.saveAnalyzed(mode: widget.mode, text: words, emotionResults: (_) => const []);
    _held = null; // the recording is gone for good
    if (!mounted) return;
    setState(() {
      _phase = _Phase.done;
      _saved = session;
      _transcript = words;
    });
    await _screenWords(words);
  }

  /// The same words check the server does, but on the phone, so a person in distress is met at once even offline.
  Future<void> _screenWords(String words) async {
    final assessment = await widget.safetyController.assessText(source: 'journal', text: words);
    if (assessment.level == SafetyLevel.clear || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportResourcesPage(
          safetyController: widget.safetyController,
          profileController: widget.profileController,
          assessment: assessment,
        ),
      ),
    );
  }

  void _reset() {
    setState(() {
      _phase = _Phase.ready;
      _held = null;
      _message = '';
      _saved = null;
      _transcript = '';
      _waiting = false;
      _waitingFace = false;
      _faceVector = null;
      _preview = null;
    });
  }

  String get _clockLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final title = _video ? 'Video journal' : 'Voice journal';
    return Scaffold(
      backgroundColor: const Color(0xFFFEFCE8),
      body: JournalBackdrop(
        tint: _video ? JournalTint.video : JournalTint.voice,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        PageBackButton(key: const ValueKey('journal-back')),
                        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Just you. Nobody replies. It is written down and kept in your journal.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4, color: _soft),
                    ),
                    Expanded(child: _body()),
                    if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _message,
                          key: const ValueKey('journal-message'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.4, color: Color(0xFFB4522C)),
                        ),
                      ),
                    _controls(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.ready:
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stage(idle: true),
                const SizedBox(height: 22),
                const TalkPromptLine(),
                const SizedBox(height: 14),
                _offlineModelCard(),
              ],
            ),
          ),
        );
      case _Phase.recording:
        final trouble = _video && _faceAllowed && _faceUsable == false;
        final line = encouragement(seconds: _seconds, faceTrouble: trouble);
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stage(idle: false),
                const SizedBox(height: 14),
                Text(_clockLabel, key: const ValueKey('journal-clock'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _ink)),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Text(
                    line,
                    key: ValueKey(line),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, color: trouble ? const Color(0xFFB4522C) : _soft),
                  ),
                ),
              ],
            ),
          ),
        );
      case _Phase.analysing:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SoftDots(),
              SizedBox(height: 22),
              Text('Writing it down…', key: ValueKey('journal-analysing'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            ],
          ),
        );
      case _Phase.done:
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: SettleCheck()),
                const SizedBox(height: 14),
                const Center(
                  child: Text('Saved to your journal', key: ValueKey('journal-saved'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    _privateOnly
                        ? 'Written down on this phone. Nothing was sent anywhere.'
                        : _waiting && _transcript.isNotEmpty
                        ? (_waitingFace
                            ? 'Written down on this phone. How you sounded and looked is read when the companion server is back.'
                            : 'Written down on this phone. How it sounded is read when the companion server is back.')
                        : 'That was a moment for yourself. Thank you for showing up.',
                    key: const ValueKey('journal-saved-note'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: _soft),
                  ),
                ),
                const SizedBox(height: 18),
                if (_waiting && _transcript.isEmpty)
                  Container(
                    key: const ValueKey('journal-waiting'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFF2ECDD)),
                    ),
                    child: Text(
                      _waitingFace
                          ? "The companion server isn't reachable right now, so your recording is kept safely on this phone. "
                              'Your face was read on this phone: only numbers about it are kept, never pictures. Your voice, '
                              'words and face are read together when the server is back, then the recording is deleted.'
                          : _video && _faceAllowed
                              ? "The companion server isn't reachable right now, so your recording is kept safely on this phone. "
                                  'It will be written down and read when the server is back. The camera is not read for an entry '
                                  'made like this, only your voice.'
                              : "The companion server isn't reachable right now, so your recording is kept safely on this phone. "
                                  'It will be written down and read when the server is back, then the recording is deleted.',
                      style: const TextStyle(fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w600, color: _ink),
                    ),
                  )
                else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFF2ECDD)),
                    boxShadow: const [BoxShadow(color: Color(0x14B0782A), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 8))],
                  ),
                  child: Text(_transcript, key: const ValueKey('journal-transcript'), style: const TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w600, color: _ink)),
                ),
              ],
            ),
          ),
        );
      case _Phase.failed:
        return const Center(child: Icon(Icons.cloud_off_rounded, size: 52, color: Color(0xFFC9B79A)));
    }
  }

  /// Small hints for the on-device models, shown before recording. Each says what the model is for and offers it; the
  /// fuller explanation, sizes and removal live in Permissions & privacy. Downloaded once from the person's own
  /// companion server, never a third party.
  Widget _offlineModelCard() {
    return OnDeviceModelsPanel(
      rows: [
        OnDeviceModelRow(
          store: _store,
          keyPrefix: 'offline-model',
          icon: Icons.graphic_eq_rounded,
          color: const Color(0xFFD9674A),
          title: 'Offline transcription',
          offer: 'Writes your recording down on this phone, with no server. About ${SttModelStore.approximateMegabytes} MB, '
              'downloaded once from your own server (best on Wi-Fi).',
          onText: () => 'This phone can write your recording down by itself, even without the server.',
          removeTitle: 'Remove offline transcription?',
          removeBody: 'Voice and video journals will then wait for the companion server to be written down. '
              'You can download it again any time.',
        ),
        if (_video && PhoneFace.pipelineReady)
          OnDeviceModelRow(
            store: widget.faceModelStore ?? PhoneFace.store,
            keyPrefix: 'face-model',
            icon: Icons.face_retouching_natural_rounded,
            color: const Color(0xFF6E73C8),
            title: 'Read my face on this phone',
            offer: 'Only numbers about your face ever leave the phone, never pictures. About '
                '${FaceModelStore.approximateMegabytes} MB, from your own server.',
            onText: () => PhoneFace.choice.place == FaceReadingPlace.phone
                ? 'Your face is read on this phone: only numbers leave it. You can change this in Permissions & privacy.'
                : 'On this phone. Your face is still read by the server: choose the phone in Permissions & privacy.',
            removeTitle: 'Remove the camera models?',
            removeBody: 'Your face will then be read by the companion server, with the video frames sent to it, '
                'as before. You can download the models again any time.',
            onInstalled: () => PhoneFace.choice.set(FaceReadingPlace.phone), // they downloaded it to use it
            onRemoved: () => PhoneFace.choice.set(FaceReadingPlace.server),
          ),
      ],
    );
  }

  /// The warm voice orb, or the live self view in a soft frame with a guide for the face.
  Widget _stage({required bool idle}) {
    if (!_video) return VoiceOrb(recording: !idle, level: _level);

    final trouble = !idle && _faceAllowed && _faceUsable == false;
    final ring = trouble ? const Color(0xFFE5896A) : Colors.white;
    return Container(
      width: 236,
      height: 312,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: [BoxShadow(color: (trouble ? const Color(0xFFE5896A) : _warm).withValues(alpha: idle ? 0.28 : 0.4), blurRadius: 38, spreadRadius: 2)],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Container(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE0B2), Color(0xFFFFC79B)])),
              child: SelfView(
                source: _frames,
                active: _phase == _Phase.recording,
                fallbackFrame: _preview,
                fallbackKey: const ValueKey('journal-preview'),
                placeholder: const Center(child: Icon(Icons.videocam_outlined, size: 44, color: Color(0xFFB57A12))),
              ),
            ),
          ),
          IgnorePointer(child: CustomPaint(painter: _FaceGuidePainter(color: ring.withValues(alpha: idle ? 0.85 : 0.5), dashed: idle || trouble))),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(34), border: Border.all(color: ring, width: 2.5)),
            ),
          ),
          if (idle)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Text(
                'Centre your face in the oval',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    switch (_phase) {
      case _Phase.ready:
        return _primary(_video ? 'Start video journal' : 'Start recording', Icons.fiber_manual_record_rounded, _start, const ValueKey('journal-start'));
      case _Phase.recording:
        return _primary('Stop and save', Icons.stop_rounded, _stop, const ValueKey('journal-stop'));
      case _Phase.analysing:
        return const SizedBox(height: 52);
      case _Phase.done:
        return Column(
          children: [
            if (!_waiting && !_privateOnly)
            _primary('See how it read', Icons.insights_rounded, () {
              final saved = _saved;
              if (saved == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionDetailPage(
                    session: saved,
                    onDelete: (s) => widget.sessionController.deleteSession(s.id),
                    onReanalyze: widget.sessionController.reanalyze,
                  ),
                ),
              );
            }, const ValueKey('journal-see-reading')),
            TextButton(key: const ValueKey('journal-another'), onPressed: _reset, child: const Text('Record another')),
          ],
        );
      case _Phase.failed:
        return Column(
          children: [
            if (_held != null) _primary('Try again', Icons.refresh_rounded, _analyse, const ValueKey('journal-retry')),
            TextButton(key: const ValueKey('journal-new'), onPressed: _reset, child: const Text('Start over')),
          ],
        );
    }
  }

  Widget _primary(String label, IconData icon, VoidCallback onTap, Key key) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_warm, Color(0xFFFF8F5A)]),
        borderRadius: BorderRadius.circular(27),
        boxShadow: const [BoxShadow(color: Color(0x40FF8F5A), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          key: key,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// A soft oval to line a face up with, dashed while getting ready.
class _FaceGuidePainter extends CustomPainter {
  _FaceGuidePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.45), width: size.width * 0.6, height: size.height * 0.58);
    final path = Path()..addOval(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 15) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 8, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter old) => old.color != color || old.dashed != dashed;
}
