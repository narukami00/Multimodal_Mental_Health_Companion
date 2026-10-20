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
import '../../services/pcm_audio_recorder_service.dart';
import '../../services/platform_frame_source.dart';
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
                const Center(
                  child: Text(
                    'That was a moment for yourself. Thank you for showing up.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: _soft),
                  ),
                ),
                const SizedBox(height: 18),
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
