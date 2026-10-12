import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../core/widgets/page_back_button.dart';
import '../../services/journal_analysis_client.dart';
import '../../services/pcm_audio_recorder_service.dart';
import '../../services/platform_frame_source.dart';
import '../../services/video_frame_service.dart';
import '../consent/consent_controller.dart';
import '../consent/emotion_consent_sheets.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
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
    super.key,
  }) : assert(mode != CaptureMode.text);

  final CaptureMode mode;
  final SessionController sessionController;
  final SafetyController safetyController;
  final ConsentController consentController;
  final ProfileController? profileController;

  /// Replaceable for tests.
  final JournalAnalysisClient? client;
  final PcmAudioRecorderService? recorder;
  final FrameSource? frameSource;

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

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_audioSub?.cancel());
    unawaited(_frameSub?.cancel());
    unawaited(_levelSub?.cancel());
    unawaited(_recorder.stopRecording());
    unawaited(_frames.stop());
    if (widget.recorder == null) _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final consent = widget.consentController;
    if (!await askEmotionConsent(context, consent)) {
      setState(() => _message = 'Writing down a recording needs the companion server, so it needs your OK first.');
      return;
    }
    if (!mounted) return;
    _faceAllowed = false;
    if (_video) {
      _faceAllowed = consent.isGranted(ConsentKey.faceFeatures) || await askFaceConsent(context, consent);
      if (!mounted) return;
    }
    _recordingId = DateTime.now().microsecondsSinceEpoch.toString();
    _pcm.clear();
    _held = null;
    _seconds = 0;
    _message = '';
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
      unawaited(_client.sendFrame(_recordingId, jpeg).then((usable) {
        if (mounted && usable != null) setState(() => _faceUsable = usable);
      }));
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
    final analysis = await _client.analyzeAudio(_recordingId, pcm, face: _faceAllowed);
    if (!mounted) return;
    if (analysis == null) {
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

  void _reset() {
    setState(() {
      _phase = _Phase.ready;
      _held = null;
      _message = '';
      _saved = null;
      _transcript = '';
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
      body: SafeArea(
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
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.ready:
        return Center(child: _stage(idle: true));
      case _Phase.recording:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stage(idle: false),
              const SizedBox(height: 18),
              Text(_clockLabel, key: const ValueKey('journal-clock'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 6),
              Text(
                _video && _faceAllowed && _faceUsable == false ? "Can't see your face clearly" : 'Listening. Take your time.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _soft),
              ),
            ],
          ),
        );
      case _Phase.analysing:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _warm),
              SizedBox(height: 18),
              Text('Writing it down…', key: ValueKey('journal-analysing'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            ],
          ),
        );
      case _Phase.done:
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_video ? Icons.videocam_outlined : Icons.graphic_eq_rounded, size: 18, color: _warm),
                    const SizedBox(width: 8),
                    const Text('Saved to your journal', key: ValueKey('journal-saved'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF2ECDD))),
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

  /// The orb (voice) or the live self view (video).
  Widget _stage({required bool idle}) {
    if (_video) {
      return Container(
        width: 210,
        height: 280,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE0B2), Color(0xFFFFC79B)]),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: _preview == null
            ? const Center(child: Icon(Icons.videocam_outlined, size: 44, color: Color(0xFFB57A12)))
            : Image.memory(_preview!, key: const ValueKey('journal-preview'), fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    final size = 120 + 60 * _level;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [idle ? const Color(0xFFFFD98A) : const Color(0xFFFF9A6A), const Color(0xFFFFB534)]),
        boxShadow: const [BoxShadow(color: Color(0x55FFB534), blurRadius: 36)],
      ),
      child: const Icon(Icons.mic_rounded, size: 44, color: Colors.white),
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
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        key: key,
        style: ElevatedButton.styleFrom(
          backgroundColor: _warm,
          foregroundColor: const Color(0xFF3D2E14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
