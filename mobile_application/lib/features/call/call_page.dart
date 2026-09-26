import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/chat_message_record.dart';
import '../../services/audio_processor.dart';
import '../../services/companion_websocket_service.dart';
import '../../services/pcm_audio_recorder_service.dart';
import '../../services/tts_playback_service.dart';
import '../chat/chat_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import 'call_turn_controller.dart';

class CallPage extends StatefulWidget {
  const CallPage({
    required this.safetyController,
    this.webSocketService,
    this.audioRecorderService,
    this.ttsPlaybackService,
    this.chatController,
    super.key,
  });

  final SafetyController safetyController;
  final CompanionWebSocketService? webSocketService;
  final PcmAudioRecorderService? audioRecorderService;
  final TtsPlaybackService? ttsPlaybackService;

  /// When present, the call's transcripts and Sol's replies are written into
  /// the chat history instead of vanishing with the page.
  final ChatController? chatController;

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
  bool _ownsWsService = false;
  bool _ownsAudioRecorder = false;
  bool _ownsTtsPlayback = false;

  /// Every live-call subscription in one list: one owner, one cancel site.
  final _subs = <StreamSubscription<dynamic>>[];

  /// The connection handshake lives outside [_subs]: it must survive the
  /// duplex restart, which clears and rebuilds that list.
  StreamSubscription<CompanionConnectionStatus>? _wsStatusSub;

  /// Single owner of conversational and orb state (spec 7.5). Nothing else in
  /// this file is allowed to decide what phase the call is in.
  final _turn = CallTurnController();

  // SNR-gate edge tracking. The gate itself (hysteresis, echo filter, hangover,
  // adaptive endpoint deadline) lives in [AudioProcessor]; this is only the
  // edge detection that used to be two naive frame counters.
  bool _gateOpen = false;

  /// `input.start` has been sent and framed audio is streaming.
  bool _turnOpen = false;

  /// A barge-in decision is deferred until speech outlives a backchannel.
  bool _pendingOnset = false;

  String? _turnId;
  int _turnOpenedAtMs = 0;
  int _silenceSinceMs = -1;
  int _onsetAtMs = -1;
  int _assistantSinceMs = -1;
  int _ttsStartedAtMs = -1;
  double _ttsLevelRms = 0.0;

  bool _isLiveCall = false;

  /// Sol's reply as it streams this response; committed to the chat history
  /// once the utterance lands (or when the call ends mid-turn).
  final _assistantTurnBuffer = StringBuffer();

  /// Set when the server tore a response down (barge-in): its partial text is
  /// never committed, only a resumed or fresh response is.
  bool _assistantTurnCancelled = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ended || _paused || !mounted) return;
      setState(() => _seconds++);
    });

    _wsService = widget.webSocketService ?? CompanionWebSocketService();
    _ownsWsService = widget.webSocketService == null;
    _audioRecorder = widget.audioRecorderService;
    _ttsPlayback = widget.ttsPlaybackService;

    if (_wsService!.status == CompanionConnectionStatus.connected) {
      _startLiveDuplexCall();
    } else {
      _wsStatusSub = _wsService!.statusStream.listen(_onWsStatus);
      if (_isTestEnv) {
        // ponytail: widget tests never open a socket, the scripted loop is
        // their live-call stand-in.
        _runConversation(++_generation);
      } else {
        unawaited(_connectSavedServer());
      }
    }
  }

  static bool get _isTestEnv =>
      Platform.environment.containsKey('FLUTTER_TEST');

  /// The same saved address the chat settings screen writes; otherwise the
  /// service defaults.
  Future<void> _connectSavedServer() async {
    final ws = _wsService!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('companion_server_host');
      final port = prefs.getInt('companion_server_port');
      if (host != null && host.isNotEmpty) ws.host = host;
      if (port != null && port > 0) ws.port = port;
    } catch (_) {
      // ponytail: no readable config, connect with the service defaults
    }
    if (ws.status == CompanionConnectionStatus.connecting ||
        ws.status == CompanionConnectionStatus.connected) {
      return;
    }
    await ws.connect();
  }

  /// One owner for every connection outcome: connected starts the duplex call,
  /// a dead connection falls back to the scripted loop.
  void _onWsStatus(CompanionConnectionStatus status) {
    if (!mounted || _ended || _isLiveCall) return;
    if (status == CompanionConnectionStatus.connected) {
      _startLiveDuplexCall();
    } else if (status == CompanionConnectionStatus.error) {
      debugPrint('[CallPage] WebSocket connect failed, running scripted demo');
      _runConversation(++_generation);
    }
  }

  Future<void> _startLiveDuplexCall() async {
    _generation++; // supersede a scripted fallback still running
    _releaseDelay();
    _isLiveCall = true;

    // Restartable: a previous attempt's listeners must not double-send.
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _turn.reset();
    _turnId = null;
    _turnOpen = false;
    _gateOpen = false;
    _pendingOnset = false;
    _silenceSinceMs = -1;

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

    final started =
        await _audioRecorder!.startRecording(sampleRate: 16000, frameMs: 20);
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission required for call mode.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Mic frames. They only leave the device while a turn is open: the
    // pre-roll ring already carries the onset, so nothing captured before
    // `input.start` is lost (spec 9.2).
    _on(_audioRecorder!.audioStream, (Uint8List chunk) {
      if (_turnOpen && !_muted && !_ended && !_paused) {
        _wsService?.sendAudioChunk(chunk, framed: true);
      }
    });

    // The signal chain's verdict on every frame: noise floor, SNR gate edge,
    // echo filter, adaptive endpoint deadline. This replaces the frame-counter
    // pair and the two magic amplitude thresholds (spec 9.4).
    _on(_audioRecorder!.frameMetricsStream, _onFrameMetrics);

    // Playback level feeds the orb envelope while Aria speaks, and the echo
    // filter's idea of what our own voice sounds like in the mic.
    _on(_ttsPlayback?.amplitudeStream, (double amp) {
      _ttsLevelRms = amp;
      if (_turn.currentPhase == CallPhase.assistantSpeaking) {
        _turn.rawAmplitude = amp;
      }
      _syncEchoFilter();
    });

    // Real speaker output is what the echo filter must know about, and what
    // "the assistant is speaking" has to mean (spec 5.4: never network arrival).
    _on(_ttsPlayback?.playingStream, (bool playing) {
      final wasSpeaking = _ariaSpeaking;
      setState(() {
        _ariaSpeaking = playing || (_ttsPlayback?.isReceivingStream ?? false);
      });
      _syncEchoFilter();
      if (playing) {
        _assistantSinceMs = _nowMs;
      } else if (wasSpeaking && !_ariaSpeaking) {
        // Playback drained: ASSISTANT_SPEAKING -> IDLE.
        if (_turn.currentPhase == CallPhase.assistantSpeaking &&
            !_pendingOnset) {
          _turn.onTtsComplete();
        }
      }
    });

    _on(_wsService?.ttsStartStream, (Map<String, dynamic> data) {
      _ttsStartedAtMs = _nowMs;
      if (_assistantSinceMs < 0) _assistantSinceMs = _nowMs;
      setState(() => _ariaSpeaking = true);
      _syncEchoFilter();
      // First response audio: ASSISTANT_SPEAKING begins (spec 5.9).
      if (!_ended && !_muted &&
          _turn.currentPhase != CallPhase.assistantSpeaking) {
        _turn.onProcessing(_turnId, TurnStage.ttsFirstFrame);
      }
    });

    _on(_wsService?.ttsEndStream, (Map<String, dynamic> data) {
      final cancelled = data['cancelled'] as bool? ?? false;
      if (cancelled) {
        // Our own interruption tore down a response; only the visuals reset,
        // the phase is already USER_SPEAKING. Its half-spoken text stays out
        // of the history.
        _assistantTurnCancelled = true;
        _ttsStartedAtMs = -1;
        setState(() {
          _ariaSpeaking = false;
          _ttsLevelRms = 0.0;
        });
        _syncEchoFilter();
        return;
      }
      // Generation finished: this turn will send nothing else, so stop
      // matching events against it.
      _commitAssistantTurn();
      _ttsStartedAtMs = -1;
      _turnId = null;
    });

    _on(_wsService?.turnStartedStream, (Map<String, dynamic> data) {
      if (!_forCurrentTurn(data)) return;
      _turn.onTurnStarted(_turnId);
    });

    // Server confirmation of the provisional barge-in (spec 7.5).
    _on(_wsService?.speechDetectedStream, (Map<String, dynamic> data) {
      if (!_forCurrentTurn(data)) return;
      _turn.onSpeechDetected(
        _turnId,
        offsetMs: data['offset_ms'] as int? ?? 0,
        confidence: (data['confidence'] as num? ?? 0).toDouble(),
      );
    });

    _on(_wsService?.turnEndpointedStream, (Map<String, dynamic> data) {
      if (!_forCurrentTurn(data)) return;
      _turnOpen = false;
      _silenceSinceMs = -1;
      _turn.onEndpointed(_turnId, speechMs: data['speech_ms'] as int? ?? 0);
    });

    _on(_wsService?.turnProcessingStream, (Map<String, dynamic> data) {
      if (!_forCurrentTurn(data)) return;
      final stage = _stageOf(data['stage'] as String?);
      if (stage != null && !_ended && !_muted) {
        _turn.onProcessing(_turnId, stage);
      }
    });

    _on(_wsService?.turnDiscardedStream, (Map<String, dynamic> data) {
      if (!_forCurrentTurn(data)) return;
      _turnOpen = false;
      _turn.onDiscarded(_turnId, _reasonOf(data['reason'] as String?));
      _turnId = null;
    });

    _on(_wsService?.transcriptFailedStream, (Map<String, dynamic> data) {
      if (!_forCurrentTurn(data)) return;
      _turnOpen = false;
      _turn.onDiscarded(_turnId, _reasonOf(data['reason'] as String?));
      _turnId = null;
    });

    // A false interruption timed out and the assistant resumes from where it
    // stopped: the provisional barge-in reverts (spec 5.8).
    _on(_wsService?.ttsResumeStream, (Map<String, dynamic> data) {
      _assistantTurnCancelled = false;
      _turn.onTtsResume(
        data['utterance_id'] as String?,
        data['from_ms'] as int? ?? 0,
      );
    });

    _on(_wsService?.llmStartStream, (_) {
      _assistantTurnBuffer.clear();
      _assistantTurnCancelled = false;
      setState(() {
        if (_lines.length >= 2) _lines.removeAt(0);
        _lines.add(_CaptionLine(aria: true, words: []));
      });
      if (!_ended && !_muted &&
          _turn.currentPhase != CallPhase.assistantSpeaking) {
        _turn.onProcessing(_turnId, TurnStage.llmFirstToken);
      }
    });

    _on(_wsService?.llmChunkStream, (Map<String, dynamic> data) {
      final delta = data['delta'] as String? ?? '';
      if (delta.isNotEmpty) {
        _assistantTurnBuffer.write(delta);
      }
      if (delta.trim().isNotEmpty && _lines.isNotEmpty && _lines.last.aria) {
        final newWords = delta.trim().split(' ');
        setState(() {
          _lines.last.words.addAll(newWords);
          _lines.last.shown = _lines.last.words.length;
        });
      }
    });

    _on(_wsService?.transcriptFinalStream, (Map<String, dynamic> data) {
      final text = data['text'] as String? ?? '';
      if (text.trim().isEmpty) return;

      // The transcript is the committed confirmation of a barge-in. If the
      // local gate somehow got here first, flush now (spec 7.5).
      if (_turn.currentPhase == CallPhase.assistantSpeaking && !_pendingOnset) {
        _flushInterruption();
      }

      _commitUserTurn(text.trim());

      setState(() {
        if (_lines.length >= 2) _lines.removeAt(0);
        final words = text.split(' ');
        final line = _CaptionLine(aria: false, words: words);
        line.shown = words.length;
        _lines.add(line);
      });
    });
  }

  // --- chat history ---------------------------------------------------------

  void _commitUserTurn(String text) {
    if (text.isEmpty || widget.chatController == null) return;
    unawaited(
      widget.chatController!.addMessage(
        ChatMessageRecord(
          id: ChatController.generateId('msg'),
          isUser: true,
          text: text,
          timestamp: DateTime.now(),
        ),
      ),
    );
  }

  /// Commit Sol's buffered reply. A response the server cancelled never
  /// reaches the history (spec 7.5 barge-in).
  void _commitAssistantTurn() {
    if (_assistantTurnCancelled) {
      _assistantTurnBuffer.clear();
      return;
    }
    final responseText = _assistantTurnBuffer.toString().trim();
    _assistantTurnBuffer.clear();
    if (responseText.isEmpty || widget.chatController == null) return;
    unawaited(
      widget.chatController!.addMessage(
        ChatMessageRecord(
          id: ChatController.generateId('msg'),
          isUser: false,
          text: responseText,
          timestamp: DateTime.now(),
        ),
      ),
    );
  }

  // --- turn lifecycle --------------------------------------------------------

  int get _nowMs => _audioRecorder?.processor.nowMs ?? 0;

  void _on<T>(Stream<T>? stream, void Function(T) handler) {
    if (stream == null) return;
    _subs.add(stream.listen((event) {
      if (mounted) handler(event);
    }));
  }

  /// Every server envelope carries a turn id; events for a turn this page did
  /// not open (or that the user already cancelled) are dropped here, which is
  /// what keeps the state machine free of cross-turn races.
  bool _forCurrentTurn(Map<String, dynamic> data) {
    if (_ended || _muted || _turnId == null) return false;
    final id = data['turn_id'];
    return id is String && id == _turnId;
  }

  /// Tell the echo filter whether the loudspeaker is actually making noise.
  void _syncEchoFilter() {
    _audioRecorder?.onPlaybackChanged(
      active: _ariaSpeaking,
      levelRms: (_ttsLevelRms.clamp(0.0, 1.0) * 32767).round(),
    );
  }

  /// One frame from the signal chain. The gate already applied the noise
  /// floor, the echo filter and hysteresis; all that is left here is edge
  /// detection, the deferred barge-in decision and the endpoint deadline.
  void _onFrameMetrics(FrameMetrics m) {
    if (!_isLiveCall || _ended || _paused) return;
    final p = _audioRecorder?.processor;
    if (p == null) return;

    _turn.noiseFloorRms = p.floorRms;
    if (_turn.currentPhase != CallPhase.assistantSpeaking) {
      _turn.rawAmplitude = m.rms;
    }
    if (_muted) return;

    final now = p.nowMs;
    if (!_gateOpen && m.isSpeech) {
      _gateOpen = true;
      _onsetDetected(m, now);
    } else if (_gateOpen && !m.isSpeech) {
      _gateOpen = false;
      _silenceSinceMs = now;
      _resolvePendingOnset(m, now, stillSpeaking: false);
    }

    _resolvePendingOnset(m, now, stillSpeaking: true);
    _maybeEndpoint(p, now);
  }

  /// The gate confirmed speech. If the assistant is talking, the decision is
  /// deferred: a backchannel must not interrupt (spec 5.8), and the pre-roll
  /// ring keeps the onset meanwhile, so nothing is lost by waiting.
  void _onsetDetected(FrameMetrics m, int now) {
    _onsetAtMs = now;
    _silenceSinceMs = -1;
    if (_turnOpen) {
      // Our turn is already open: no new decision to make. The exception is
      // playback that resumed underneath the turn — take the floor back.
      if (_ariaSpeaking) _flushInterruption();
      return;
    }
    if (_ariaSpeaking) {
      _pendingOnset = true;
      return;
    }
    _startUserTurn(m, speechMs: 0, assistantWasSpeaking: false);
  }

  void _resolvePendingOnset(
    FrameMetrics m,
    int now, {
    required bool stillSpeaking,
  }) {
    if (!_pendingOnset) return;
    final speechMs = now - _onsetAtMs;
    if (stillSpeaking && speechMs < SpeechProbe.backchannelMaxMs) return;
    _pendingOnset = false;
    _startUserTurn(m, speechMs: speechMs, assistantWasSpeaking: true);
  }

  void _startUserTurn(
    FrameMetrics m, {
    required int speechMs,
    required bool assistantWasSpeaking,
  }) {
    final verdict = _turn.onLocalOnset(
      SpeechProbe(
        snrDb: m.snrDb,
        onsetRunMs: speechMs,
        speechMs: speechMs,
        assistantSpeaking: assistantWasSpeaking,
        sinceAssistantStartMs: assistantWasSpeaking && _assistantSinceMs >= 0
            ? (_nowMs - _assistantSinceMs).clamp(0, 60000)
            : 0,
      ),
    );
    final turnId = 'call_$_nowMs';

    if (verdict == BargeInClass.interrupt && assistantWasSpeaking) {
      _flushInterruption(turnId: turnId);
    }
    if (verdict != BargeInClass.interrupt) {
      // Backchannel or noise: the assistant keeps talking and no turn opens.
      return;
    }
    _openUserTurn(turnId);
  }

  /// `input.start`, then the pre-roll ring drained into the same stream so the
  /// first phonemes of the onset survive (spec 9.4).
  void _openUserTurn(String turnId) {
    if (_turnOpen) return;
    _turnOpen = true;
    _turnId = turnId;
    _turnOpenedAtMs = _nowMs;
    _silenceSinceMs = -1;

    unawaited(_wsService?.sendInputStart(
      turnId: turnId,
      preRollMs: 600,
      sampleRate: 16000,
      frameMs: 20,
    ));
    // Synchronous: no frame listener can interleave between input.start and
    // the ring contents, because both leave on this microtask in order.
    for (final chunk in _audioRecorder?.drainPreRoll(600) ?? const <Uint8List>[]) {
      _wsService?.sendAudioChunk(chunk, framed: true);
    }
    debugPrint('[CallPage] turn open: $turnId');
    if (mounted) setState(() {});
  }

  void _endUserTurn({String reason = 'client_endpoint'}) {
    if (!_turnOpen || _turnId == null) return;
    final p = _audioRecorder?.processor;
    final turnId = _turnId!;
    final durationMs = p == null ? 0 : (p.nowMs - _turnOpenedAtMs);
    _turnOpen = false;
    _silenceSinceMs = -1;
    if (p != null && p.gate.speechConfirmed && p.gate.lastSpeechMs >= 0) {
      // Adaptive endpoint deadline learns from the gaps this client emitted.
      p.gate.noteAcceptedGap(p.nowMs - p.gate.lastSpeechMs);
    }
    debugPrint('[CallPage] turn end: $turnId ($reason)');
    unawaited(_wsService?.sendInputEnd(
      turnId: turnId,
      durationMs: durationMs,
      reason: reason,
    ));
  }

  /// The silence deadline, and the hard cap no detector may exceed
  /// (spec 5.1.5).
  void _maybeEndpoint(AudioProcessor p, int now) {
    if (!_turnOpen) return;
    if (_gateOpen) {
      _silenceSinceMs = -1;
      return;
    }
    if (_silenceSinceMs < 0) return;
    final overCap = now - _turnOpenedAtMs >= p.gate.maxTurnMs;
    if (overCap || now - _silenceSinceMs >= p.gate.effectiveEndpointMs) {
      _endUserTurn(reason: overCap ? 'max_duration' : 'client_endpoint');
    }
  }

  /// Stop local playback and tell the server the exact point the ear reached,
  /// so its history matches what was actually heard (spec 6.2).
  void _flushInterruption({String? turnId}) {
    final playedMs = _ttsStartedAtMs >= 0
        ? (_nowMs - _ttsStartedAtMs).clamp(0, 60000)
        : 0;
    if (_turn.currentPhase == CallPhase.assistantSpeaking) {
      // null: keep whatever turn id the machine already holds, this flush is
      // about the assistant's audio, not about naming a new turn.
      _turn.onInterrupted(turnId: null, playedMs: playedMs);
    }
    _ttsPlayback?.stopVoice(fadeMs: 25);
    _wsService?.sendTurnInterrupted(
      turnId: turnId ?? 'call_$_nowMs',
      playedMs: playedMs,
    );
    if (mounted) setState(() => _ariaSpeaking = false);
  }

  static TurnStage? _stageOf(String? stage) => switch (stage) {
        'vad' => TurnStage.vad,
        'stt' => TurnStage.stt,
        'llm_first_token' => TurnStage.llmFirstToken,
        'tts_first_frame' => TurnStage.ttsFirstFrame,
        'llm_timeout' => TurnStage.llmTimeout,
        'tool' => TurnStage.tool,
        'complete' => TurnStage.complete,
        _ => null,
      };

  static DiscardReason _reasonOf(String? reason) => switch (reason) {
        'silence' => DiscardReason.silence,
        'unintelligible' => DiscardReason.unintelligible,
        'too_short' => DiscardReason.tooShort,
        'no_speech' => DiscardReason.noSpeechProb,
        'echo' => DiscardReason.echo,
        _ => DiscardReason.cancelled,
      };

  @override
  void dispose() {
    _generation++;
    _releaseDelay();
    _ticker?.cancel();
    _commitAssistantTurn();

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _wsStatusSub?.cancel();
    _wsStatusSub = null;
    _turn.dispose();

    if (_isLiveCall) {
      if (_turnOpen && _turnId != null) {
        _wsService?.sendTurnCancel(turnId: _turnId!, reason: 'page_disposed');
      }
      _turnOpen = false;
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
    if (_ownsWsService) {
      _wsService?.dispose();
    }

    super.dispose();
  }

  void _releaseDelay() {
    final delay = _delay;
    if (delay != null && !delay.isCompleted) delay.complete();
  }

  /// Header copy and dot colour, one per phase: the operator's five states,
  /// readable at a glance.
  (Color, String) _statusFor(CallPhase phase) => switch (phase) {
        CallPhase.userSpeaking => (const Color(0xFF10B981), 'Listening to you...'),
        CallPhase.thinking => (_amber, 'Thinking...'),
        CallPhase.assistantSpeaking => (_coral, 'Solace speaking'),
        CallPhase.muted => (_softInk, 'Microphone muted'),
        CallPhase.ended => (_softInk, 'Call ended'),
        _ => (_amber, 'Listening · take your time'),
      };

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
        _syncScriptPhase(aria);

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
          _syncScriptPhase(false, allowOnset: false);
        }
        await _wait(500, token);
      }
    } on _Stale {
      // conversation superseded or widget disposed
    }
  }

  /// The scripted demo has no server, so its two beats are pushed through the
  /// same machine: the orb shows the same states a live call would.
  void _syncScriptPhase(bool ariaSpeaking, {bool allowOnset = true}) {
    if (_muted || _ended) return;
    if (ariaSpeaking) {
      if (_turn.currentPhase != CallPhase.assistantSpeaking) {
        _turn.onProcessing(null, TurnStage.ttsFirstFrame);
      }
      return;
    }
    if (_turn.currentPhase == CallPhase.assistantSpeaking) {
      _turn.onTtsComplete();
    }
    if (allowOnset && _turn.currentPhase == CallPhase.idle) {
      _turn.onLocalOnset(
        const SpeechProbe(
          snrDb: 30,
          onsetRunMs: 0,
          speechMs: 0,
          assistantSpeaking: false,
          sinceAssistantStartMs: 0,
        ),
      );
    }
  }

  void _toggleMic() {
    if (_ended) return;
    setState(() => _muted = !_muted);
    _turn.onMicMutedChanged(_muted);
    if (_muted) {
      // Muting abandons whatever was in flight; the server keeps no orphan.
      if (_turnOpen && _turnId != null) {
        _wsService?.sendTurnCancel(turnId: _turnId!, reason: 'muted');
      }
      _turnOpen = false;
      _turnId = null;
      _pendingOnset = false;
      _gateOpen = false;
      _silenceSinceMs = -1;
      _syncEchoFilter();
    }
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
      if (_turnOpen && _turnId != null) {
        _wsService?.sendTurnCancel(turnId: _turnId!, reason: 'user_ended_call');
      }
      _turnOpen = false;
      _audioRecorder?.stopRecording();
      _ttsPlayback?.stopVoice();
      _wsService?.sendCallEnd(reason: 'user_ended_call');
      _wsService?.sendSessionConfigure(mode: 'chat_voice_playback');
    }
    _commitAssistantTurn();
    _turn.onCallEnded();
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
    _turn.reset();
    _turnId = null;
    _turnOpen = false;
    _gateOpen = false;
    _pendingOnset = false;
    _silenceSinceMs = -1;
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
                ValueListenableBuilder<CallPhase>(
                  valueListenable: _turn.phase,
                  builder: (context, phase, _) {
                    final (color, label) = _statusFor(phase);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
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
                    );
                  },
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
                _BreathingOrb(controller: _turn),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: _turn,
                  builder: (context, _) => _AcousticWaveform(
                    // Real gated level, not a free-running sine (spec 8.6).
                    level: _turn.modulation,
                    active: _turn.currentPhase == CallPhase.userSpeaking ||
                        _turn.currentPhase == CallPhase.assistantSpeaking,
                  ),
                ),
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

/// Bars driven by the real gated level, not a free-running sine. `level` is
/// [CallTurnController.modulation], already echo-gated, enveloped and
/// dB-mapped, so the shape follows whoever is actually talking (spec 8.6).
class _AcousticWaveform extends StatelessWidget {
  const _AcousticWaveform({required this.active, this.level = 0.0});

  final bool active;
  final double level;

  @override
  Widget build(BuildContext context) {
    final l = level.clamp(0.0, 1.0);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      opacity: active ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        offset: active ? Offset.zero : const Offset(0, -0.25),
        child: SizedBox(
          height: 22,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(7, (i) {
              // Each bar keeps its own weight so the profile has a shape, but
              // every height is a function of the measured level.
              final weight = 0.55 + 0.45 * math.sin((i + 1) * 1.1);
              final h = 5.0 + 15.0 * (0.15 + 0.85 * l) * weight;
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
  const _BreathingOrb({required this.controller});

  /// The orb is a pure function of this machine (spec 7.5): it reads the
  /// lerped parameter row for the current phase plus the gated envelope, and
  /// it ticks the controller, so this widget is the only animation driver.
  final CallTurnController controller;

  @override
  State<_BreathingOrb> createState() => _BreathingOrbState();
}

class _BreathingOrbState extends State<_BreathingOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;

  // Continuous monotonic time (seconds) — NEVER wraps, guarantees 0 discontinuities or snapping
  double _time = 0.0;

  // Accumulated rotation (radians). Driven by the state row's rotRate, which
  // is the visual that separates THINKING from every other state.
  double _rotation = 0.0;

  // Smooth continuous factors (exponential smoothing prevents abrupt pops on state change)
  double _speechFactor = 0.0;
  double _muteFactor = 0.0;

  // Envelope-follower filtered level (eliminates 100ms discrete mic/TTS jitter)
  double _smoothedAmplitude = 0.0;

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
      final dt =
          ((elapsed - _lastElapsed!).inMicroseconds / 1000000.0).clamp(0.001, 0.05);
      widget.controller.tick(dt);
      _updatePhysics(dt);
    }
    _lastElapsed = elapsed;
    setState(() {});
  }

  void _updatePhysics(double dt) {
    final p = widget.controller.parameters;
    final phase = widget.controller.phase.value;

    // 1. Morph rate comes from the state row: THINKING churns on a 7 s period,
    //    MUTED barely moves on 30 s. One number, one meaning, no magic timing.
    _time += dt * (11.0 / p.morphPeriodS);
    _rotation += dt * p.rotRate;

    // 2. Envelope follower on the gated level: fast attack, slow release, so
    //    inter-syllable silences bridge instead of flickering.
    final rawAmp = widget.controller.modulation.clamp(0.0, 1.0);
    final ampRate = rawAmp > _smoothedAmplitude ? 8.0 : 2.6;
    _smoothedAmplitude +=
        (rawAmp - _smoothedAmplitude) * (1.0 - math.exp(-ampRate * dt));

    // 3. Energy per state (spec 8.2): IDLE rests low with zero twitching, the
    //    two audio-coupled states ride the envelope, THINKING holds steady.
    final targetSpeech = switch (phase) {
      CallPhase.userSpeaking => 0.35 + 0.65 * _smoothedAmplitude,
      CallPhase.assistantSpeaking => 0.40 + 0.60 * _smoothedAmplitude,
      CallPhase.thinking => 0.45,
      CallPhase.muted || CallPhase.ended => 0.04,
      CallPhase.idle => 0.10,
    };
    _speechFactor +=
        (targetSpeech - _speechFactor) * (1.0 - math.exp(-3.2 * dt));

    // 4. Mute contracts the orb; the desaturation is the same parameter row,
    //    applied as a colour matrix in build.
    final muted = phase == CallPhase.muted || phase == CallPhase.ended;
    _muteFactor += ((muted ? 1.0 : 0.0) - _muteFactor) * (1.0 - math.exp(-4.5 * dt));

    // 5. Elastic spring rebound for drag offset
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

    // 7. Elastic touch squish rebound
    if (!_isDragging && _touchSquish < 1.0) {
      _touchSquish += (1.0 - _touchSquish) * (1.0 - math.exp(-12.0 * dt));
    }

    // 8. Propagate and decay ripples
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
    final p = widget.controller.parameters;

    // Breath straight from the state row: 6.4 s resting, 3.1 s radiant.
    final breathRate = 2 * math.pi / math.max(p.breathPeriodS, 0.5);
    final breathAmp = p.breathAmp * (1.0 + 1.2 * _smoothedAmplitude);
    final breathScale = (1.0 + breathAmp * math.sin(_time * breathRate)) *
        _touchSquish *
        p.baseScale;

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
        // Desaturation is a property of the state row (MUTED sits at 0.55),
        // applied once here so every layer of the orb honours it (spec 8.2).
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturationMatrix(p.saturation)),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Smooth continuous radiating harmonic rings
              for (var i = 0; i < 3; i++)
                _ContinuousRing(
                  time: _time,
                  index: i,
                  energy: _speechFactor,
                  ringPeriodS: p.ringPeriodS,
                  maxOpacity: p.ringMaxOpacity,
                ),
              Transform.scale(
                scale: breathScale,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: _LivingFluidOrbPainter(
                    time: _time,
                    rotation: _rotation,
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
      ),
    );
  }

  /// Standard saturation matrix: 1.0 leaves the colours alone, 0 is grey.
  static List<double> _saturationMatrix(double s) => <double>[
        0.213 + 0.787 * s,
        0.715 - 0.715 * s,
        0.072 - 0.072 * s,
        0,
        0,
        0.213 - 0.213 * s,
        0.715 + 0.285 * s,
        0.072 - 0.072 * s,
        0,
        0,
        0.213 - 0.213 * s,
        0.715 - 0.715 * s,
        0.072 + 0.928 * s,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ];
}

class _ContinuousRing extends StatelessWidget {
  const _ContinuousRing({
    required this.time,
    required this.index,
    required this.energy,
    required this.ringPeriodS,
    required this.maxOpacity,
  });

  final double time;
  final int index;

  /// Phase energy, 0..1: widens the ring and its stroke.
  final double energy;

  /// Seconds per ring expansion, straight from the state row. THINKING turns
  /// the rings off entirely by setting [maxOpacity] to zero.
  final double ringPeriodS;
  final double maxOpacity;

  @override
  Widget build(BuildContext context) {
    const base = 170.0;
    // Ring phase cycles smoothly [0.0 -> 1.0] with offset per ring
    final speed = 1.45 / math.max(ringPeriodS, 0.5);
    final phase = (time * speed + index * (1.0 / 3.0)) % 1.0;

    // Radius expands from 0.82 to 1.70
    final scale = 0.82 + (0.88 + energy * 0.25) * phase;

    // Opacity fades in from 0, peaks at phase 0.35, and cleanly fades to 0 at phase 1.0
    // Because sin(pi * phase) is 0 at phase=0 and phase=1, the loop is 100% SEAMLESS and invisible!
    final window = math.sin(math.pi * phase);
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
              width: 1.4 + energy * 0.8,
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
    required this.rotation,
    required this.speechFactor,
    required this.muteFactor,
    required this.dragOffset,
    required this.ripples,
  });

  final double time;

  /// Accumulated rotation in radians from the state row's rotRate. Separate
  /// from [time] so THINKING can gyrate while its morph period slows.
  final double rotation;

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
      rotation: rotation,
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
      rotation: -rotation * 0.79,
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
