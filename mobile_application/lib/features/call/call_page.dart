import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/companion_websocket_service.dart';
import '../../services/pcm_audio_recorder_service.dart';
import '../../services/tts_playback_service.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';

class CallPage extends StatefulWidget {
  const CallPage({
    required this.safetyController,
    this.webSocketService,
    this.audioRecorderService,
    this.ttsPlaybackService,
    super.key,
  });

  final SafetyController safetyController;
  final CompanionWebSocketService? webSocketService;
  final PcmAudioRecorderService? audioRecorderService;
  final TtsPlaybackService? ttsPlaybackService;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CaptionLine {
  _CaptionLine({required this.aria, required this.words});

  final bool aria;
  final List<String> words;
  int shown = 0;
}

class _CallPageState extends State<CallPage> {
  static const _ink = Color(0xFF4A3B2A);
  static const _softInk = Color(0xFF6E5D49);
  static const _timerInk = Color(0xFF8E7E6A);
  static const _amber = Color(0xFFFFB534);
  static const _coral = Color(0xFFFF7F50);
  static const _line = Color(0x1F7A5D3A);

  // ponytail: fixed script loop instead of real audio pipeline; swap for live STT/TTS when available
  static const _script = <(bool, String)>[
    (true, "Hi, it's Aria. I'm really glad you came back today."),
    (false, "Hey… honestly, it's been a heavy week."),
    (true, 'That sounds like a lot to carry. Where would feel easiest to begin?'),
    (false, "I keep feeling like I'm behind on everything."),
    (true, "Behind is such an exhausting place to sit. Let's slow it down for a moment — just you and me."),
    (false, 'Okay. That already helps a little.'),
    (true, "It does, doesn't it? One breath at a time. I'm not going anywhere."),
    (false, 'Can we just stay here for a bit?'),
    (true, "Of course. However long you need — I'll keep the light on."),
  ];

  Timer? _ticker;
  Completer<void>? _delay;
  var _seconds = 0;
  var _lineIndex = 0;
  var _generation = 0;
  var _muted = false;
  var _camera = false;
  var _speaker = true;
  var _paused = false;
  var _ended = false;
  var _ariaSpeaking = false;
  final _lines = <_CaptionLine>[];

  CompanionWebSocketService? _wsService;
  PcmAudioRecorderService? _audioRecorder;
  TtsPlaybackService? _ttsPlayback;
  bool _ownsAudioRecorder = false;
  bool _ownsTtsPlayback = false;

  StreamSubscription<Uint8List>? _micAudioSub;
  StreamSubscription<double>? _micAmpSub;
  StreamSubscription<double>? _ttsAmpSub;
  StreamSubscription<bool>? _ttsPlayingSub;
  StreamSubscription<Map<String, dynamic>>? _ttsStartSub;
  StreamSubscription<Map<String, dynamic>>? _ttsEndSub;
  StreamSubscription<Map<String, dynamic>>? _llmStartSub;
  StreamSubscription<Map<String, dynamic>>? _llmChunkSub;
  StreamSubscription<Map<String, dynamic>>? _transcriptFinalSub;

  double _currentTtsAmplitude = 0.0;
  bool _isLiveCall = false;
  int _bargeInConsecutiveFrames = 0;

  bool get _isSpeaking => !_ended && !_paused && _ariaSpeaking;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ended || _paused || !mounted) return;
      setState(() => _seconds++);
    });

    _wsService = widget.webSocketService;
    _audioRecorder = widget.audioRecorderService;
    _ttsPlayback = widget.ttsPlaybackService;

    if (_wsService != null &&
        _wsService!.status == CompanionConnectionStatus.connected) {
      _startLiveDuplexCall();
    } else {
      final token = ++_generation;
      _runConversation(token);
    }
  }

  void _startLiveDuplexCall() {
    _isLiveCall = true;

    _wsService?.sendSessionConfigure(
      mode: 'duplex_call',
      ttsEnabled: true,
    );

    if (_ttsPlayback == null && _wsService != null) {
      _ttsPlayback = TtsPlaybackService(webSocketService: _wsService!);
      _ownsTtsPlayback = true;
    }

    if (_audioRecorder == null) {
      _audioRecorder = PcmAudioRecorderService();
      _ownsAudioRecorder = true;
    }

    _audioRecorder!.startRecording(sampleRate: 16000, frameMs: 100);

    _micAudioSub = _audioRecorder!.audioStream.listen((chunk) {
      if (!_muted && !_ended && !_paused && _isLiveCall) {
        _wsService?.sendAudioChunk(chunk);
      }
    });

    _micAmpSub = _audioRecorder!.amplitudeStream.listen((amp) {
      if (!mounted || _muted || _ended || _paused) return;
      if (_ariaSpeaking && amp > 0.16) {
        _bargeInConsecutiveFrames++;
        if (_bargeInConsecutiveFrames >= 2) {
          _triggerBargeIn();
        }
      } else {
        _bargeInConsecutiveFrames = 0;
      }
    });

    _ttsAmpSub = _ttsPlayback?.amplitudeStream.listen((amp) {
      if (!mounted) return;
      setState(() => _currentTtsAmplitude = amp);
    });

    _ttsPlayingSub = _ttsPlayback?.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() {
        _ariaSpeaking = playing || (_ttsPlayback?.isReceivingStream ?? false);
      });
    });

    _ttsStartSub = _wsService?.ttsStartStream.listen((data) {
      if (!mounted) return;
      setState(() => _ariaSpeaking = true);
    });

    _ttsEndSub = _wsService?.ttsEndStream.listen((data) {
      if (!mounted) return;
      final cancelled = data['cancelled'] as bool? ?? false;
      if (cancelled) {
        setState(() {
          _ariaSpeaking = false;
          _currentTtsAmplitude = 0.0;
        });
      }
    });

    _llmStartSub = _wsService?.llmStartStream.listen((_) {
      if (!mounted) return;
      setState(() {
        if (_lines.length >= 2) _lines.removeAt(0);
        _lines.add(_CaptionLine(aria: true, words: []));
      });
    });

    _llmChunkSub = _wsService?.llmChunkStream.listen((data) {
      if (!mounted) return;
      final delta = data['delta'] as String? ?? '';
      if (delta.trim().isNotEmpty && _lines.isNotEmpty && _lines.last.aria) {
        final newWords = delta.trim().split(' ');
        setState(() {
          _lines.last.words.addAll(newWords);
          _lines.last.shown = _lines.last.words.length;
        });
      }
    });

    _transcriptFinalSub = _wsService?.transcriptFinalStream.listen((data) {
      if (!mounted) return;
      final text = data['text'] as String? ?? '';
      if (text.isNotEmpty) {
        setState(() {
          if (_lines.length >= 2) _lines.removeAt(0);
          final words = text.split(' ');
          final line = _CaptionLine(aria: false, words: words);
          line.shown = words.length;
          _lines.add(line);
        });
      }
    });
  }

  void _triggerBargeIn() {
    _bargeInConsecutiveFrames = 0;
    if (!_ariaSpeaking) return;

    debugPrint('[CallPage] Barge-in triggered by user speech!');
    _ttsPlayback?.cancelVoice(reason: 'call_barge_in');
    _wsService?.sendCallBargeIn(reason: 'vad_speech_detected');

    setState(() {
      _ariaSpeaking = false;
      _currentTtsAmplitude = 0.0;
    });
  }

  @override
  void dispose() {
    _generation++;
    _releaseDelay();
    _ticker?.cancel();

    _micAudioSub?.cancel();
    _micAmpSub?.cancel();
    _ttsAmpSub?.cancel();
    _ttsPlayingSub?.cancel();
    _ttsStartSub?.cancel();
    _ttsEndSub?.cancel();
    _llmStartSub?.cancel();
    _llmChunkSub?.cancel();
    _transcriptFinalSub?.cancel();

    if (_isLiveCall) {
      _audioRecorder?.stopRecording();
      _ttsPlayback?.stopVoice();
      _wsService?.sendCallEnd(reason: 'page_disposed');
      _wsService?.sendSessionConfigure(mode: 'chat_voice_playback');
    }

    if (_ownsAudioRecorder) {
      _audioRecorder?.dispose();
    }
    if (_ownsTtsPlayback) {
      _ttsPlayback?.dispose();
    }

    super.dispose();
  }

  void _releaseDelay() {
    final delay = _delay;
    if (delay != null && !delay.isCompleted) delay.complete();
  }

  static String _fmt(int total) {
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _wait(int ms, int token) async {
    final completer = Completer<void>();
    _delay = completer;
    final timer = Timer(Duration(milliseconds: ms), completer.complete);
    await completer.future;
    timer.cancel();
    if (_delay == completer) _delay = null;
    if (!mounted || token != _generation) throw const _Stale();
  }

  Future<void> _runConversation(int token) async {
    try {
      while (mounted && token == _generation && !_ended) {
        if (_paused) {
          await _wait(220, token);
          continue;
        }

        final (aria, text) = _script[_lineIndex % _script.length];
        if (!aria && _muted) {
          _lineIndex++;
          await _wait(1100, token);
          continue;
        }

        final words = text.split(' ');
        setState(() {
          _ariaSpeaking = aria;
          if (_lines.length >= 2) _lines.removeAt(0);
          _lines.add(_CaptionLine(aria: aria, words: words));
        });

        for (var i = 0; i < words.length; i++) {
          while (_paused && token == _generation && !_ended) {
            await _wait(200, token);
          }
          if (token != _generation || _ended) return;

          var beat = aria ? 96 : 82;
          if (words[i].length > 7) beat += 34;
          if (RegExp(r'[,.;:—?!]$').hasMatch(words[i])) beat += 210;
          await _wait(beat, token);
          if (!mounted) return;
          setState(() => _lines.last.shown = i + 1);
        }

        _lineIndex++;
        await _wait(aria ? 1500 : 1150, token);
        if (mounted && token == _generation) {
          setState(() => _ariaSpeaking = false);
        }
        await _wait(500, token);
      }
    } on _Stale {
      // conversation superseded or widget disposed
    }
  }

  void _toggleMic() {
    if (_ended) return;
    setState(() => _muted = !_muted);
  }

  void _toggleCamera() {
    if (_ended) return;
    setState(() => _camera = !_camera);
  }

  void _toggleSpeaker() {
    setState(() => _speaker = !_speaker);
  }

  void _endSession() {
    if (_ended) return;
    setState(() {
      _ended = true;
      _paused = false;
      _generation++;
      _ariaSpeaking = false;
    });
    _releaseDelay();

    if (_isLiveCall) {
      _audioRecorder?.stopRecording();
      _ttsPlayback?.stopVoice();
      _wsService?.sendCallEnd(reason: 'user_ended_call');
      _wsService?.sendSessionConfigure(mode: 'chat_voice_playback');
    }
  }

  void _restart() {
    setState(() {
      _ended = false;
      _seconds = 0;
      _lineIndex = 0;
      _lines.clear();
      _generation++;
    });
    _releaseDelay();
    if (_isLiveCall) {
      _startLiveDuplexCall();
    } else {
      _runConversation(_generation);
    }
  }

  Future<void> _confirmLeave() async {
    if (_ended) return;
    setState(() => _paused = true);
    final leave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _LeaveSheet(
        onStay: () => Navigator.of(sheetContext).pop(false),
        onLeave: () => Navigator.of(sheetContext).pop(true),
      ),
    );
    if (!mounted) return;
    setState(() => _paused = false);
    if (leave == true) _endSession();
  }

  Future<void> _openSupport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportResourcesPage(
          safetyController: widget.safetyController,
          regionCode: Localizations.localeOf(context).countryCode ?? 'GLOBAL',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFCE8),
      body: ClipRect(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 392),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.45,
                        stops: [0, 0.42, 0.72, 1],
                        colors: [
                          Color(0xFFFFF7DE),
                          Color(0xFFFEFCE8),
                          Color(0xFFFDF6E4),
                          Color(0xFFFBF1DC),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: -40,
                  left: -60,
                  child: _Pool(color: Color(0x38FFB534), size: 300),
                ),
                const Positioned(
                  bottom: 80,
                  right: -70,
                  child: _Pool(color: Color(0x29FF7F50), size: 280),
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: _buildStage()),
                        _buildCaptions(),
                        _buildModeChip(),
                        _buildDock(),
                        const SizedBox(height: 4),
                        Container(
                          width: 120,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: _ink.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                if (_ended)
                  Positioned.fill(
                    child: _EndOverlay(
                      seconds: _seconds,
                      camera: _camera,
                      onRestart: _restart,
                      onHome: () => Navigator.of(context).maybePop(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          _GlassButton(
            size: 40,
            radius: 14,
            onTap: _confirmLeave,
            tooltip: 'Minimize',
            child: const Icon(Icons.chevron_left_rounded, size: 22, color: _ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Solace Voice',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isSpeaking
                            ? _coral
                            : (_muted ? _softInk : _amber),
                        boxShadow: [
                          BoxShadow(
                            color: (_isSpeaking ? _coral : _amber).withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _isSpeaking
                            ? 'Aria speaking'
                            : (_muted ? 'Microphone muted' : 'Listening · take your time'),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _softInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
            ),
            child: Text(
              _fmt(_seconds),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _timerInk,
                letterSpacing: 0.4,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _GlassButton(
            size: 40,
            radius: 14,
            onTap: _openSupport,
            tooltip: 'Support resources',
            child: const Icon(Icons.health_and_safety_outlined, size: 21, color: _coral),
          ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    return Stack(
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BreathingOrb(
                  muted: _muted,
                  isSpeaking: _isSpeaking,
                  amplitude: _currentTtsAmplitude,
                ),
                const SizedBox(height: 16),
                _AcousticWaveform(isSpeaking: _isSpeaking),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Take your time. Silence is welcome here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _softInk,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 16,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            opacity: _camera ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_camera,
              child: const _SelfView(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptions() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 104),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 0, 30, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _coral.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE TRANSCRIPT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: _ink.withValues(alpha: 0.30),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _lines.length; i++)
              _CaptionText(line: _lines[i], past: i < _lines.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: _camera
              ? _amber.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 13,
              color: _camera ? const Color(0xC7966014) : _ink.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                _camera ? 'CAMERA ON · YOU ARE VISIBLE' : 'VOICE ONLY · CAMERA OFF',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _camera ? const Color(0xC7966014) : _ink.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2ED68A20),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Ctrl(
              label: _muted ? 'Muted' : 'Mic on',
              active: !_muted,
              onTap: _toggleMic,
              icon: Icons.mic_none_rounded,
              slashed: _muted,
            ),
            _Ctrl(
              label: _speaker ? 'Speaker' : 'Earpiece',
              active: _speaker,
              onTap: _toggleSpeaker,
              icon: _speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
              slashed: !_speaker,
            ),
            _Ctrl(
              label: _camera ? 'Cam on' : 'Cam off',
              active: _camera,
              onTap: _toggleCamera,
              icon: Icons.videocam_outlined,
              slashed: !_camera,
            ),
            _EndCtrl(onTap: _endSession),
          ],
        ),
      ),
    );
  }
}

class _Stale implements Exception {
  const _Stale();
}

class _Pool extends StatelessWidget {
  const _Pool({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.size,
    required this.radius,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final double size;
  final double radius;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x38A06E28),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          ),
          child: child,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _AcousticWaveform extends StatefulWidget {
  const _AcousticWaveform({required this.isSpeaking});

  final bool isSpeaking;

  @override
  State<_AcousticWaveform> createState() => _AcousticWaveformState();
}

class _AcousticWaveformState extends State<_AcousticWaveform>
    with SingleTickerProviderStateMixin {
  AnimationController? _waveCtrl;

  static bool get _isTestEnv =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static const _delays = [0.0, 0.14, 0.28, 0.42, 0.56, 0.34, 0.20];

  @override
  void initState() {
    super.initState();
    if (!_isTestEnv) {
      _waveCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1150),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _waveCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      opacity: widget.isSpeaking ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        offset: widget.isSpeaking ? Offset.zero : const Offset(0, -0.25),
        child: SizedBox(
          height: 22,
          child: _isTestEnv || _waveCtrl == null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(7, (i) {
                    final h = 5.0 + 15.0 * (0.5 + 0.5 * math.sin(i.toDouble()));
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: 3.5,
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _CallPageState._amber,
                            _CallPageState._coral,
                          ],
                        ),
                      ),
                    );
                  }),
                )
              : AnimatedBuilder(
                  animation: _waveCtrl!,
                  builder: (_, __) {
                    final t = _waveCtrl!.value * 2 * math.pi;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(7, (i) {
                        final delay = _delays[i] * 2 * math.pi;
                        final h =
                            5.0 + 15.0 * (0.5 + 0.5 * math.sin(t + delay));
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: 3.5,
                          height: h,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _CallPageState._amber,
                                _CallPageState._coral,
                              ],
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _FluidRipple {
  _FluidRipple({
    required this.angle,
    required this.maxAmp,
  });

  final double angle;
  final double maxAmp;
  double age = 0.0;
}

class _BreathingOrb extends StatefulWidget {
  const _BreathingOrb({
    required this.muted,
    required this.isSpeaking,
    this.amplitude = 0.0,
  });

  final bool muted;
  final bool isSpeaking;
  final double amplitude;

  @override
  State<_BreathingOrb> createState() => _BreathingOrbState();
}

class _BreathingOrbState extends State<_BreathingOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;

  // Continuous monotonic time (seconds) — NEVER wraps, guarantees 0 discontinuities or snapping
  double _time = 0.0;

  // Smooth continuous factors (exponential smoothing prevents abrupt pops on speaking state change)
  double _speechFactor = 0.0;
  double _muteFactor = 0.0;

  // Interactive touch & elastic gel physics
  Offset _dragOffset = Offset.zero;
  Offset _dragVelocity = Offset.zero;
  bool _isDragging = false;
  double _touchSquish = 1.0;
  final List<_FluidRipple> _ripples = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_lastElapsed != null) {
      final dt = ((elapsed - _lastElapsed!).inMicroseconds / 1000000.0).clamp(0.001, 0.05);
      _updatePhysics(dt);
    }
    _lastElapsed = elapsed;
    setState(() {});
  }

  void _updatePhysics(double dt) {
    // 1. Advance continuous time: slightly faster harmonic flux when speaking
    final timeSpeed = 1.0 + _speechFactor * 0.35 - _muteFactor * 0.4;
    _time += dt * timeSpeed;

    // 2. Smooth speech factor (exponential approach over ~260ms), modulated by voice amplitude
    final targetSpeech = widget.isSpeaking
        ? (0.6 + 0.4 * widget.amplitude.clamp(0.0, 1.0))
        : 0.0;
    _speechFactor += (targetSpeech - _speechFactor) * (1.0 - math.exp(-7.0 * dt));

    // 3. Smooth mute factor
    final targetMute = widget.muted ? 1.0 : 0.0;
    _muteFactor += (targetMute - _muteFactor) * (1.0 - math.exp(-6.0 * dt));

    // 4. Elastic spring rebound for drag offset
    if (!_isDragging && _dragOffset != Offset.zero) {
      const stiffness = 180.0;
      const damping = 16.0;
      final springForce = -_dragOffset * stiffness;
      final dampingForce = -_dragVelocity * damping;
      final accel = springForce + dampingForce;
      _dragVelocity += accel * dt;
      _dragOffset += _dragVelocity * dt;
      if (_dragOffset.distance < 0.25 && _dragVelocity.distance < 0.25) {
        _dragOffset = Offset.zero;
        _dragVelocity = Offset.zero;
      }
    }

    // 5. Elastic touch squish rebound
    if (!_isDragging && _touchSquish < 1.0) {
      _touchSquish += (1.0 - _touchSquish) * (1.0 - math.exp(-14.0 * dt));
    }

    // 6. Propagate and decay ripples
    for (var i = _ripples.length - 1; i >= 0; i--) {
      _ripples[i].age += dt;
      if (_ripples[i].age > 1.2) {
        _ripples.removeAt(i);
      }
    }
  }

  void _triggerRipple(Offset localPos, {required bool isTap}) {
    const size = 220.0;
    const center = Offset(size / 2, size / 2);
    final delta = localPos - center;
    final angle = math.atan2(delta.dy, delta.dx);
    if (_ripples.length < 6) {
      _ripples.add(
        _FluidRipple(
          angle: angle,
          maxAmp: isTap ? 0.085 : 0.045,
        ),
      );
    }
    if (isTap) {
      _touchSquish = 0.94;
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    const center = Offset(size / 2, size / 2);

    // Continuous breath modulation (never wraps abruptly)
    final breathRate = 1.1 + _speechFactor * 0.5;
    final breathAmp = 0.040 +
        (_speechFactor * 0.035 + widget.amplitude.clamp(0.0, 1.0) * 0.045) -
        _muteFactor * 0.020;
    final breathScale = (1.0 + breathAmp * math.sin(_time * breathRate)) * _touchSquish;

    return GestureDetector(
      onPanStart: (details) {
        _isDragging = true;
        _touchSquish = 0.96;
        _triggerRipple(details.localPosition, isTap: false);
      },
      onPanUpdate: (details) {
        final delta = details.localPosition - center;
        const maxDist = 45.0;
        final dist = delta.distance;
        if (dist > maxDist) {
          _dragOffset = delta / dist * maxDist;
        } else {
          _dragOffset = delta;
        }
        _dragVelocity = Offset.zero;
      },
      onPanEnd: (details) {
        _isDragging = false;
        // Inject spring impulse from fling velocity
        _dragVelocity = details.velocity.pixelsPerSecond * 0.35;
        _triggerRipple(center + _dragOffset, isTap: true);
      },
      onPanCancel: () {
        _isDragging = false;
      },
      onTapDown: (details) {
        _triggerRipple(details.localPosition, isTap: true);
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Smooth continuous radiating harmonic rings
            for (var i = 0; i < 3; i++)
              _ContinuousRing(
                time: _time,
                index: i,
                speechFactor: _speechFactor,
                muteFactor: _muteFactor,
              ),
            Transform.scale(
              scale: breathScale,
              child: CustomPaint(
                size: const Size(size, size),
                painter: _LivingFluidOrbPainter(
                  time: _time,
                  speechFactor: _speechFactor,
                  muteFactor: _muteFactor,
                  dragOffset: _dragOffset,
                  ripples: List.unmodifiable(_ripples),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinuousRing extends StatelessWidget {
  const _ContinuousRing({
    required this.time,
    required this.index,
    required this.speechFactor,
    required this.muteFactor,
  });

  final double time;
  final int index;
  final double speechFactor;
  final double muteFactor;

  @override
  Widget build(BuildContext context) {
    const base = 170.0;
    // Ring phase cycles smoothly [0.0 -> 1.0] with offset per ring
    final speed = 0.28 + speechFactor * 0.12;
    final phase = (time * speed + index * (1.0 / 3.0)) % 1.0;

    // Radius expands from 0.82 to 1.70
    final scale = 0.82 + (0.88 + speechFactor * 0.25) * phase;

    // Opacity fades in from 0, peaks at phase 0.35, and cleanly fades to 0 at phase 1.0
    // Because sin(pi * phase) is 0 at phase=0 and phase=1, the loop is 100% SEAMLESS and invisible!
    final window = math.sin(math.pi * phase);
    final maxOpacity = (0.42 + speechFactor * 0.30) * (1.0 - muteFactor * 0.85);
    final opacity = (window * maxOpacity).clamp(0.0, 1.0);

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: base,
          height: base,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Color.lerp(
                const Color(0x66FFB534),
                const Color(0x44FF7F50),
                phase,
              )!,
              width: 1.4 + speechFactor * 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _LivingFluidOrbPainter extends CustomPainter {
  _LivingFluidOrbPainter({
    required this.time,
    required this.speechFactor,
    required this.muteFactor,
    required this.dragOffset,
    required this.ripples,
  });

  final double time;
  final double speechFactor;
  final double muteFactor;
  final Offset dragOffset;
  final List<_FluidRipple> ripples;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bounds = Offset.zero & size;
    final baseRadius = size.width * 0.38;

    // Closed midpoint quadratic B-spline guaranteeing C^1 smooth curvature with ZERO seam kink
    Path buildClosedFluidSpline(List<Offset> points) {
      final path = Path();
      final count = points.length;
      if (count < 3) return path;

      final midPoints = List<Offset>.generate(count, (i) {
        final p0 = points[i];
        final p1 = points[(i + 1) % count];
        return Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      });

      path.moveTo(midPoints[count - 1].dx, midPoints[count - 1].dy);
      for (var i = 0; i < count; i++) {
        path.quadraticBezierTo(
          points[i].dx,
          points[i].dy,
          midPoints[i].dx,
          midPoints[i].dy,
        );
      }
      path.close();
      return path;
    }

    Path generateFluidBlob({
      required double radius,
      required double phase1,
      required double phase2,
      required double phase3,
      required double phase4,
      required double amp1,
      required double amp2,
      required double amp3,
      required double amp4,
      double rotation = 0.0,
      Offset stretchOffset = Offset.zero,
    }) {
      const numPoints = 64;
      final points = <Offset>[];

      final stretchDist = stretchOffset.distance;
      final stretchAngle =
          stretchDist > 0.01 ? math.atan2(stretchOffset.dy, stretchOffset.dx) : 0.0;
      final stretchNorm = (stretchDist / 45.0).clamp(0.0, 1.0);

      for (var i = 0; i < numPoints; i++) {
        final theta = (i / numPoints) * 2 * math.pi;

        // 1. Multi-harmonic organic fluid displacement (coprime harmonics 2θ, 3θ, 5θ, 7θ)
        var harmR = 1.0 +
            amp1 * math.sin(2 * theta + phase1) +
            amp2 * math.cos(3 * theta + phase2) +
            amp3 * math.sin(5 * theta + phase3) +
            amp4 * math.cos(7 * theta + phase4);

        // 2. Interactive touch ripples traveling along perimeter
        for (final ripple in ripples) {
          final diffAngle = theta - ripple.angle;
          final decay = math.exp(-ripple.age * 3.8);
          final wave = math.cos(5 * diffAngle - ripple.age * 18.0);
          harmR += ripple.maxAmp * decay * wave;
        }

        // 3. Elastic directional stretch / teardrop bulge toward finger
        if (stretchDist > 0.01) {
          final cosDiff = math.cos(theta - stretchAngle);
          final sinDiff = math.sin(theta - stretchAngle);
          // Volume-preserving teardrop elongation: extends along drag, pinches perpendicularly
          final stretchEffect = stretchNorm * 0.28 * (cosDiff - 0.45 * sinDiff * sinDiff);
          harmR += stretchEffect;
        }

        final r = radius * harmR;
        final rotTheta = theta + rotation;
        // Center gently shifts toward drag
        final x = center.dx + r * math.cos(rotTheta) + stretchOffset.dx * 0.32;
        final y = center.dy + r * math.sin(rotTheta) + stretchOffset.dy * 0.32;
        points.add(Offset(x, y));
      }

      return buildClosedFluidSpline(points);
    }

    // Continuous smoothly-lerped amplitudes
    // No instant step function — everything is a smooth function of speechFactor & muteFactor
    double lerp3(double calm, double speaking, double mutedVal) {
      final active = calm + (speaking - calm) * speechFactor;
      return active + (mutedVal - active) * muteFactor;
    }

    final amp1 = lerp3(0.068, 0.138, 0.028);
    final amp2 = lerp3(0.044, 0.088, 0.018);
    final amp3 = lerp3(0.024, 0.048, 0.010);
    final amp4 = lerp3(0.012, 0.024, 0.005);

    // 1. Outer radiant chromatic aura glow
    final auraAlpha1 = lerp3(0.40, 0.58, 0.18);
    final auraAlpha2 = lerp3(0.20, 0.34, 0.07);
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _CallPageState._amber.withValues(alpha: auraAlpha1),
          _CallPageState._coral.withValues(alpha: auraAlpha2),
          _CallPageState._coral.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.46, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: center + dragOffset * 0.2,
          radius: baseRadius * 1.58,
        ),
      );
    canvas.drawCircle(center + dragOffset * 0.2, baseRadius * 1.58, auraPaint);

    // Save layer for optical compositing
    canvas.saveLayer(bounds, Paint());

    // 2. Layer 1: Golden Amber Primary Fluid Blob
    final path1 = generateFluidBlob(
      radius: baseRadius *
          (1.0 + lerp3(0.04, 0.07, 0.02) * math.sin(time * 1.4)),
      phase1: time * 0.95,
      phase2: time * 1.54 + 0.8,
      phase3: time * 2.31 + 1.6,
      phase4: time * 3.08 + 2.4,
      amp1: amp1,
      amp2: amp2,
      amp3: amp3,
      amp4: amp4,
      rotation: time * 0.14,
      stretchOffset: dragOffset,
    );

    // Deep warm volumetric shadow
    canvas.drawShadow(
      path1,
      const Color(0xFFD68A20).withValues(alpha: lerp3(0.60, 0.72, 0.30)),
      28,
      true,
    );

    final paint1 = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFE8B5),
          Color(0xFFFFB534),
          Color(0xFFFF954E),
          Color(0xFFFF7F50),
        ],
        stops: [0.0, 0.36, 0.70, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: center + dragOffset * 0.3,
          radius: baseRadius,
        ),
      );
    canvas.drawPath(path1, paint1);

    // 3. Layer 2: Coral Harmonic Counter-Fluid Blob with BlendMode.multiply
    final path2 = generateFluidBlob(
      radius: baseRadius *
          (0.95 + lerp3(0.025, 0.042, 0.015) * math.cos(time * 1.25)),
      phase1: -time * 1.15 + 1.2,
      phase2: time * 1.76 + 2.4,
      phase3: -time * 2.48 + 0.5,
      phase4: time * 3.25 + 1.8,
      amp1: lerp3(0.058, 0.118, 0.024),
      amp2: lerp3(0.038, 0.078, 0.016),
      amp3: lerp3(0.020, 0.040, 0.008),
      amp4: lerp3(0.010, 0.020, 0.004),
      rotation: -time * 0.11,
      stretchOffset: dragOffset * 0.85,
    );

    final paint2 = Paint()
      ..blendMode = BlendMode.multiply
      ..shader = RadialGradient(
        center: const Alignment(0.25, 0.28),
        radius: 0.95,
        colors: [
          const Color(0xFFFF8E6B).withValues(alpha: lerp3(0.80, 0.90, 0.45)),
          const Color(0xFFFF7F50).withValues(alpha: lerp3(0.88, 0.96, 0.55)),
          const Color(0xFFFFB534).withValues(alpha: 0.35),
        ],
        stops: const [0.0, 0.60, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: center + dragOffset * 0.25,
          radius: baseRadius,
        ),
      );
    canvas.drawPath(path2, paint2);

    // 4. Layer 3: Organic Upper-Left Specular Sheen with BlendMode.screen
    final sheenPath = generateFluidBlob(
      radius: baseRadius * 0.54,
      phase1: time * 0.82,
      phase2: time * 1.08 + 1.0,
      phase3: time * 0.58 + 2.0,
      phase4: time * 1.36 + 0.5,
      amp1: 0.042,
      amp2: 0.032,
      amp3: 0.022,
      amp4: 0.014,
      stretchOffset: dragOffset * 0.45,
    );

    final sheenCenter = Offset(
      center.dx - baseRadius * 0.22 + dragOffset.dx * 0.15,
      center.dy - baseRadius * 0.26 + dragOffset.dy * 0.15,
    );
    final sheenPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: lerp3(0.90, 0.98, 0.55)),
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.40, 1.0],
      ).createShader(
        Rect.fromCircle(center: sheenCenter, radius: baseRadius * 0.55),
      );

    canvas.save();
    canvas.translate(-baseRadius * 0.10, -baseRadius * 0.12);
    canvas.drawPath(sheenPath, sheenPaint);
    canvas.restore();

    // 5. Layer 4: Luminous Inner Pulsing Energy Core with BlendMode.plus
    final corePulse = 1.0 +
        lerp3(0.09, 0.18, 0.04) * math.sin(time * 1.7);
    final coreRadius = baseRadius * 0.28 * corePulse;
    final coreCenter = center + dragOffset * 0.25;
    final corePaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: lerp3(0.95, 1.0, 0.65)),
          const Color(0xFFFFF2D4).withValues(alpha: 0.65),
          const Color(0xFFFFB534).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: coreCenter, radius: coreRadius));
    canvas.drawCircle(coreCenter, coreRadius, corePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LivingFluidOrbPainter oldDelegate) {
    return true; // Continuously animated at 60fps
  }
}


class _CaptionText extends StatelessWidget {
  const _CaptionText({required this.line, required this.past});

  final _CaptionLine line;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final revealed = line.words.take(line.shown).join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: past ? 0.34 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.aria ? 'ARIA' : 'YOU',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.9,
                color: line.aria
                    ? const Color(0x9ED66E34)
                    : _CallPageState._ink.withValues(alpha: 0.34),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              revealed,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: past ? FontWeight.w400 : FontWeight.w600,
                height: 1.5,
                color: _CallPageState._ink.withValues(alpha: 0.74),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelfView extends StatelessWidget {
  const _SelfView();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      height: 116,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE0B2), Color(0xFFFFC79B), Color(0xFFFFB08A)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99965A28),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.9), blurRadius: 8),
                ],
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                'YOU',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: Color(0xBF5A3A1E),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ctrl extends StatelessWidget {
  const _Ctrl({
    required this.label,
    required this.active,
    required this.onTap,
    required this.icon,
    required this.slashed,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  final bool slashed;

  @override
  Widget build(BuildContext context) {
    final fg = active ? _CallPageState._ink : const Color(0xFF8A5A1E);
    return Column(
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0xFFFFFBEA)],
                      )
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFE9C4), Color(0xFFFFD79A)],
                      ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xB3A06E28),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 23, color: fg),
                  Opacity(
                    opacity: slashed ? 1 : 0,
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: Container(
                        width: 2.2,
                        height: 26,
                        decoration: BoxDecoration(
                          color: fg,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: active
                ? _CallPageState._ink.withValues(alpha: 0.42)
                : const Color(0xB8966014),
          ),
        ),
      ],
    );
  }
}

class _EndCtrl extends StatelessWidget {
  const _EndCtrl({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _CallPageState._coral.withValues(alpha: 0.28)),
                  ),
                ),
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF7F50), Color(0xFFF06030)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xBF9C3A18),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_end_rounded, size: 26, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'END',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: const Color(0xFFD9562C).withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

class _LeaveSheet extends StatelessWidget {
  const _LeaveSheet({required this.onStay, required this.onLeave});

  final VoidCallback onStay;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF2), Color(0xFFFDF7E6)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: _CallPageState._ink.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Leave this session?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xF04A3B2A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'You can end now or keep talking. Your reflections stay saved either way.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              fontWeight: FontWeight.w600,
              color: Color(0x9E4A3B2A),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onStay,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC861), Color(0xFFFFB534)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xE6D69632),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Keep talking',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5A3B10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onLeave,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _CallPageState._coral.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _CallPageState._coral.withValues(alpha: 0.28)),
                  ),
                  child: const Text(
                    'End session',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD9562C),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndOverlay extends StatelessWidget {
  const _EndOverlay({
    required this.seconds,
    required this.camera,
    required this.onRestart,
    required this.onHome,
  });

  final int seconds;
  final bool camera;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  String get _meta {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return 'Session $m:$s · ${camera ? 'Voice + camera' : 'Voice only'}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0FEFCE8), Color(0xF7FFF4E2)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(46),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD07A), Color(0xFFFF9E5C)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xB38C8C3C),
                      blurRadius: 40,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(46),
                    gradient: RadialGradient(
                      center: const Alignment(-0.25, -0.35),
                      colors: [Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0)],
                      stops: const [0, 0.68],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Take good care',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xF24A3B2A),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "You showed up for yourself today — that matters. I'll be right here whenever you want to talk again.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  fontWeight: FontWeight.w600,
                  color: Color(0x9E4A3B2A),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _CallPageState._line),
                ),
                child: Text(
                  _meta.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: _CallPageState._ink.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onRestart,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC861), Color(0xFFFFB534)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xF2D69632),
                            blurRadius: 30,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Start a new session',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5A3B10),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onHome,
                child: const Text(
                  'Return home',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0x804A3B2A),
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0x404A3B2A),
                    decorationThickness: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
