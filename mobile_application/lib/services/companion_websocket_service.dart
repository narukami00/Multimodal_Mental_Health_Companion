import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants/companion_server_config.dart';

enum CompanionConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Service managing real-time WebSocket connection to the Python Solace Companion server.
/// Complies with CHAT_FEATURES.md Phase 1:
///   - FastAPI WebSocket endpoint (/ws/v1/session)
///   - JSON hello / session_ready handshake
///   - Heartbeat ping/pong (every 15s) with round-trip latency tracking
///   - Message echo & simulated LLM streaming
///   - Exponential backoff auto-reconnect on network drop
class CompanionWebSocketService {
  CompanionWebSocketService({
    this.host = CompanionServerConfig.defaultTailscaleIp,
    this.port = CompanionServerConfig.defaultPort,
    this.token = 'local-auth-token',
  });

  String host;
  int port;
  String token;

  String? _sessionId;
  String? _connectedHost;
  int? _connectedPort;
  String? _threadId;
  String? _lastEventId;

  String? get sessionId => _sessionId;
  String? get threadId => _threadId;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  bool _isDisposed = false;
  bool _manualDisconnect = false;
  bool _wasConnected = false;
  String? _lastErrorMessage;
  String? get lastErrorMessage => _lastErrorMessage;

  int _connectSequence = 0;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelaySec = 15;

  /// Heartbeat cadence for a duplex call. Chat mode keeps the 15 s interval.
  Duration _heartbeatInterval = const Duration(seconds: 15);
  static const Duration callHeartbeatInterval = Duration(seconds: 4);
  Duration get heartbeatInterval => _heartbeatInterval;

  /// Stream id used in the 8-byte binary header of duplex capture frames.
  final int _inputStreamId = 1001;
  int _inputSeq = 0;

  CompanionConnectionStatus _status = CompanionConnectionStatus.disconnected;
  CompanionConnectionStatus get status => _status;

  int? _lastLatencyMs;
  int? get lastLatencyMs => _lastLatencyMs;

  final _statusController =
      StreamController<CompanionConnectionStatus>.broadcast();
  Stream<CompanionConnectionStatus> get statusStream =>
      _statusController.stream;

  final _latencyController = StreamController<int>.broadcast();
  Stream<int> get latencyStream => _latencyController.stream;

  final _rawEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get rawEventStream => _rawEventController.stream;

  final _echoController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get echoStream => _echoController.stream;

  final _llmStartController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get llmStartStream => _llmStartController.stream;

  final _llmChunkController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get llmChunkStream => _llmChunkController.stream;

  final _llmDoneController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get llmDoneStream => _llmDoneController.stream;

  final _audioAckController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get audioAckStream => _audioAckController.stream;

  final _audioReceivedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get audioReceivedStream =>
      _audioReceivedController.stream;

  final _turnCancelledController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnCancelledStream =>
      _turnCancelledController.stream;

  final _transcriptFinalController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get transcriptFinalStream =>
      _transcriptFinalController.stream;

  final _transcriptFailedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get transcriptFailedStream =>
      _transcriptFailedController.stream;

  final _binaryAudioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get binaryAudioStream => _binaryAudioController.stream;

  final _ttsStartController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get ttsStartStream => _ttsStartController.stream;

  final _ttsEndController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get ttsEndStream => _ttsEndController.stream;

  final _ttsSegmentController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get ttsSegmentStream =>
      _ttsSegmentController.stream;

  final _callStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callStateStream => _callStateController.stream;

  // --- duplex turn lifecycle (spec §7.2) -------------------------------------
  final _turnStartedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnStartedStream =>
      _turnStartedController.stream;

  final _speechDetectedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get speechDetectedStream =>
      _speechDetectedController.stream;

  final _turnEndpointedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnEndpointedStream =>
      _turnEndpointedController.stream;

  final _turnProcessingController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnProcessingStream =>
      _turnProcessingController.stream;

  final _turnInterruptedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnInterruptedStream =>
      _turnInterruptedController.stream;

  final _turnDiscardedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnDiscardedStream =>
      _turnDiscardedController.stream;

  final _ttsResumeController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get ttsResumeStream => _ttsResumeController.stream;

  final _turnDiagnosticController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnDiagnosticStream =>
      _turnDiagnosticController.stream;

  /// Where a turn's time went: speech-to-text, first token, first audio.
  final _turnLatencyController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get turnLatencyStream =>
      _turnLatencyController.stream;

  /// The server acknowledges `call.listen` / `call.config`.
  final _callListeningController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callListeningStream =>
      _callListeningController.stream;

  /// The server's own crisis-language gate fired for the person's last words
  /// (`safety.alert`: a level, never their words).
  final _safetyAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get safetyAlertStream =>
      _safetyAlertController.stream;

  /// What the server inferred from a turn's voice and words (`emotion.update`),
  /// sent only when the person opted in.
  final _emotionUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get emotionUpdateStream =>
      _emotionUpdateController.stream;

  /// Where the camera-frame socket lives: the same host and port this call actually connected to, same session.
  /// Null until connected.
  Uri? get videoUri {
    final host = _connectedHost;
    final port = _connectedPort;
    final session = _sessionId;
    if (host == null || port == null || session == null) return null;
    return Uri(
      scheme: 'ws',
      host: host,
      port: port,
      path: '/ws/v1/video',
      queryParameters: {'session_id': session},
    );
  }

  static CompanionWebSocketService? _live;

  /// Quotes one good moment from a chat message over the live connection, or
  /// null when no connection is live. Lets code that does not own a connection
  /// (such as the moments controller) use whichever one is open.
  static Future<String?> Function(String text)? get liveMomentRequester {
    final live = _live;
    return live == null ? null : (text) => live.requestMoment(text);
  }

  void _updateStatus(CompanionConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (newStatus == CompanionConnectionStatus.connected) {
        _live = this;
      } else if (identical(_live, this)) {
        _live = null;
      }
      if (!_statusController.isClosed) {
        _statusController.add(newStatus);
      }
    }
  }

  /// Connect to the companion backend.
  /// If [customHost] is not provided and the primary [host] fails, attempts
  /// candidate fallbacks from [CompanionServerConfig.candidateHosts] (Tailscale -> MagicDNS -> LAN -> USB).
  Future<void> connect({
    String? customHost,
    int? customPort,
    String? sessionId,
    String? threadId,
    bool allowFallback = true,
  }) async {
    if (_isDisposed) return;
    final seq = ++_connectSequence;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (customHost != null) host = customHost;
    if (customPort != null) port = customPort;
    if (sessionId != null) _sessionId = sessionId;
    if (threadId != null) _threadId = threadId;

    _manualDisconnect = false;
    _wasConnected = false;
    _lastErrorMessage = null;
    _sessionId ??=
        'sess_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    _threadId ??= 'thread_main';

    _updateStatus(CompanionConnectionStatus.connecting);

    final shouldTryFallback = customHost == null &&
        customPort == null &&
        allowFallback &&
        !CompanionServerConfig.isTestEnvironment;

    final hostsToTry = shouldTryFallback
        ? [host, ...CompanionServerConfig.candidateHosts.where((h) => h != host)]
        : [host];

    for (var i = 0; i < hostsToTry.length; i++) {
      final currentCandidate = hostsToTry[i];
      if (seq != _connectSequence || _isDisposed) return;

      final success = await _attemptSingleConnect(
        candidateHost: currentCandidate,
        candidatePort: port,
        seq: seq,
      );

      if (success) {
        host = currentCandidate;
        debugPrint('[CompanionWS] Successfully connected via $host:$port');
        return;
      }

      if (i < hostsToTry.length - 1) {
        debugPrint(
          '[CompanionWS] Connection to $currentCandidate:$port failed, trying fallback: ${hostsToTry[i + 1]}',
        );
      }
    }

    if (seq != _connectSequence || _isDisposed) return;
    _wasConnected = false;
    _updateStatus(CompanionConnectionStatus.error);
    await _cleanUpConnection(resetManual: false);
  }

  Future<bool> _attemptSingleConnect({
    required String candidateHost,
    required int candidatePort,
    required int seq,
  }) async {
    try {
      await _cleanUpConnection(resetManual: false);
      if (seq != _connectSequence || _isDisposed) return false;

      final uri = Uri.parse(
        'ws://$candidateHost:$candidatePort/ws/v1/session?session_id=$_sessionId&token=$token',
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      final timeoutDuration = CompanionServerConfig.isTestEnvironment
          ? const Duration(milliseconds: 100)
          : const Duration(seconds: 4);
      await channel.ready.timeout(
        timeoutDuration,
        onTimeout: () {
          throw TimeoutException(
            'Connection to $candidateHost:$candidatePort timed out (${timeoutDuration.inSeconds}s)',
          );
        },
      );

      if (seq != _connectSequence || _isDisposed) {
        _safeClose(channel);
        return false;
      }

      _reconnectAttempts = 0;
      _connectedHost = candidateHost;
      _connectedPort = candidatePort;

      _subscription = channel.stream.listen(
        _handleIncomingMessage,
        onError: (dynamic error) {
          debugPrint(
            '[CompanionWS] WebSocket stream error on $candidateHost: $error',
          );
          _lastErrorMessage = error.toString();
          _updateStatus(CompanionConnectionStatus.error);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[CompanionWS] WebSocket stream done on $candidateHost');
          if (!_manualDisconnect) {
            _scheduleReconnect();
          } else {
            _updateStatus(CompanionConnectionStatus.disconnected);
          }
        },
        cancelOnError: false,
      );

      // Send JSON hello handshake immediately per specification 13.1
      _sendHello();
      return true;
    } catch (e) {
      debugPrint('[CompanionWS] Attempt failed on $candidateHost:$candidatePort: $e');
      _lastErrorMessage = e is TimeoutException
          ? 'Timed out connecting to $candidateHost:$candidatePort'
          : 'Failed: $e';
      return false;
    }
  }

  void _sendHello() {
    if (_channel == null) return;
    final helloPayload = {
      'v': 1,
      'type': 'hello',
      'session_id': _sessionId,
      'thread_id': _threadId,
      'last_event_id': _lastEventId,
      'client': {
        'platform': defaultTargetPlatform.name,
        'app_version': '1.0.0',
      },
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(helloPayload);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // 4 s for a call session: at 15 s a half-open socket produced a
    // 15-second window of "connected" that was not connected, during which
    // audio was silently dropped (spec §3.7).
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      sendPing();
    });
  }

  /// Sends a ping heartbeat message to verify liveness and measure RTT.
  void sendPing() {
    if (_status != CompanionConnectionStatus.connected || _channel == null) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final pingPayload = {
      'v': 1,
      'type': 'ping',
      'session_id': _sessionId,
      'ts': now,
    };
    _sendJson(pingPayload);
  }

  /// Sends a user text message to the companion server.
  Future<void> sendTextMessage(
    String text, {
    String? turnId,
    bool simulateStream = true,
  }) async {
    final effectiveTurnId =
        turnId ??
        'turn_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    final payload = {
      'v': 1,
      'type': 'text_message',
      'session_id': _sessionId,
      'turn_id': effectiveTurnId,
      'text': text,
      'simulate_stream': simulateStream,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Sends audio_start envelope before streaming raw PCM chunks (Phase 2).
  Future<void> sendAudioStart({
    required String turnId,
    int sampleRate = 16000,
    int channels = 1,
    int frameMs = 100,
    String mode = 'voice_note',
  }) async {
    final payload = {
      'v': 1,
      'type': 'audio_start',
      'session_id': _sessionId,
      'turn_id': turnId,
      'encoding': 'pcm16',
      'sample_rate': sampleRate,
      'channels': channels,
      'frame_ms': frameMs,
      'mode': mode,
      'client_vad': true,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Sends the duplex call's `input.start`, symmetric with the server's binary
  /// framing. The server answers `turn.started`; until then, frames are only
  /// buffered locally in the pre-roll ring.
  Future<void> sendInputStart({
    required String turnId,
    int preRollMs = 600,
    bool framed = true,
    int sampleRate = 16000,
    int channels = 1,
    int frameMs = 20,
    String mode = 'duplex_call',
  }) async {
    _heartbeatInterval = callHeartbeatInterval;
    _inputSeq = 0;
    final payload = {
      'v': 1,
      'type': 'input.start',
      'session_id': _sessionId,
      'turn_id': turnId,
      'stream_id': _inputStreamId,
      'modality': mode,
      'encoding': 'pcm16',
      'framed': framed,
      'sample_rate': sampleRate,
      'channels': channels,
      'frame_ms': frameMs,
      'pre_roll_ms': preRollMs,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Sends one framed capture frame: `uint32 LE stream_id`, `uint32 LE seq`,
  /// then exactly `frame_bytes` of pcm16. The header is what makes loss,
  /// duplication and reordering *detectable* server-side (spec §7.3).
  void sendAudioChunk(Uint8List chunk, {bool framed = false}) {
    if (_channel == null || _status != CompanionConnectionStatus.connected) {
      return;
    }
    try {
      if (!framed) {
        _channel!.sink.add(chunk);
        return;
      }
      // 50 frames a second for the length of a call: one allocation, no spreads.
      final out = Uint8List(8 + chunk.length);
      ByteData.sublistView(out, 0, 8)
        ..setUint32(0, _inputStreamId, Endian.little)
        ..setUint32(4, _inputSeq++, Endian.little);
      out.setRange(8, out.length, chunk);
      _channel!.sink.add(out);
    } catch (e) {
      debugPrint('[CompanionWS] Failed to send binary audio chunk: $e');
    }
  }

  /// `input.end`. [reason] is the client's endpointing decision; the server
  /// corroborates it against its own VAD.
  Future<void> sendInputEnd({
    required String turnId,
    int durationMs = 0,
    String reason = 'client_endpoint',
  }) async {
    final payload = {
      'v': 1,
      'type': 'input.end',
      'session_id': _sessionId,
      'turn_id': turnId,
      'duration_ms': durationMs,
      'reason': reason,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Starts a live call: from here the microphone streams continuously through
  /// [sendAudioChunk] and the *server* decides where each turn starts and ends.
  ///
  /// [bargeIn] says whether the person may talk over the assistant. Only true
  /// when the audio goes to headphones: a loudspeaker's own voice would come
  /// straight back in through the microphone.
  Future<void> sendCallListen({bool bargeIn = false}) async {
    _heartbeatInterval = callHeartbeatInterval;
    _inputSeq = 0;
    // Restart the timer so the call cadence applies to a connection that was
    // opened for chat.
    if (_status == CompanionConnectionStatus.connected) _startHeartbeat();
    _sendJson({
      'v': 1,
      'type': 'call.listen',
      'session_id': _sessionId,
      'sample_rate': 16000,
      'frame_ms': 20,
      'barge_in': bargeIn,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Changes a live call: the audio route moved between loudspeaker and
  /// headphones, so talking over the assistant became unsafe or safe.
  Future<void> sendCallConfig({required bool bargeIn}) async {
    _sendJson({
      'v': 1,
      'type': 'call.config',
      'session_id': _sessionId,
      'barge_in': bargeIn,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Mutes or unmutes the microphone for the server's turn detector. A muted
  /// call drops the turn in progress and ignores audio until unmuted.
  Future<void> sendCallMute({required bool muted}) async {
    _sendJson({
      'v': 1,
      'type': 'call.mute',
      'session_id': _sessionId,
      'muted': muted,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// The client abandoned the turn (page disposed, mute, call end). Sent
  /// *before* the socket goes away so the server never keeps an orphaned
  /// buffer.
  Future<void> sendTurnCancel({
    required String turnId,
    String reason = 'page_disposed',
  }) async {
    final payload = {
      'v': 1,
      'type': 'turn.cancel',
      'session_id': _sessionId,
      'turn_id': turnId,
      'reason': reason,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// The user genuinely took the floor. [playedMs] is what the ear actually
  /// heard: the server truncates its history to exactly that point. This is the
  /// message the previous code never sent, and without it the server's history
  /// became a record of words the user never heard.
  Future<void> sendTurnInterrupted({
    required String turnId,
    required int playedMs,
    String? interruptedTurnId,
  }) async {
    final payload = {
      'v': 1,
      'type': 'turn.interrupted',
      'session_id': _sessionId,
      'turn_id': turnId,
      if (interruptedTurnId != null) 'interrupted_turn_id': interruptedTurnId,
      'played_ms': playedMs,
      'reason': 'user_speech',
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Sends audio_end envelope after finishing recording (Phase 2).
  Future<void> sendAudioEnd({
    required String turnId,
    int durationMs = 0,
    bool clientVadEndpoint = true,
  }) async {
    final payload = {
      'v': 1,
      'type': 'audio_end',
      'session_id': _sessionId,
      'turn_id': turnId,
      'duration_ms': durationMs,
      'client_vad_endpoint': clientVadEndpoint,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Sends audio_cancel envelope when the user slides to cancel (Phase 2).
  Future<void> sendAudioCancel({
    required String turnId,
    String reason = 'user_cancelled',
  }) async {
    final payload = {
      'v': 1,
      'type': 'audio_cancel',
      'session_id': _sessionId,
      'turn_id': turnId,
      'reason': reason,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Configures session mode, voice settings, and audio parameters.
  ///
  /// [vad] carries the §5.11 calibration block. Server config wins: the client
  /// must not be able to set a threshold the server disagrees with, or the two
  /// halves of the gate disagree and the failure is undebuggable.
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
    if (mode != 'duplex_call') {
      _heartbeatInterval = const Duration(seconds: 15);
    }
    final payload = buildSessionConfigurePayload(
      sessionId: _sessionId,
      mode: mode,
      ttsEnabled: ttsEnabled,
      voiceId: voiceId,
      speed: speed,
      micSampleRate: micSampleRate,
      playbackSampleRate: playbackSampleRate,
      codec: codec,
      vad: vad,
      memory: memoryProvider?.call(),
      resume: resume,
      country: countryProvider?.call(),
      emotion: emotionProvider?.call(),
      face: faceProvider?.call() ?? false,
    );
    _sendJson(payload);
  }

  /// Supplies the person's consented memory block (a profile snippet and the
  /// moments they kept) for every `session.configure`. Set once at start-up.
  /// Returning null sends nothing, which is also how withdrawn consent reaches
  /// the server: it treats an absent block as "none" on each configure.
  static Map<String, Object?>? Function()? memoryProvider;

  /// Where the person is based (ISO alpha-2), sent with every `session.configure` so the server
  /// can name the right local emergency resources if it ever has to. Set once at start-up.
  static String? Function()? countryProvider;

  /// Whether the person agreed to Sol noticing how they sound. Read on every configure, so
  /// withdrawing the consent reaches the server on the next one. Set once at start-up.
  static bool Function()? emotionProvider;

  /// Whether the person also agreed to the camera being read during calls (a separate consent).
  static bool Function()? faceProvider;

  /// The `session.configure` message. Pure, so what goes on the wire can be
  /// tested without a socket.
  @visibleForTesting
  static Map<String, dynamic> buildSessionConfigurePayload({
    required String? sessionId,
    required String mode,
    bool ttsEnabled = true,
    String voiceId = 'af_heart',
    double speed = 0.96,
    int micSampleRate = 16000,
    int playbackSampleRate = 24000,
    String codec = 'pcm_s16le',
    Map<String, dynamic>? vad,
    Map<String, Object?>? memory,
    Map<String, Object?>? resume,
    String? country,
    bool? emotion,
    bool face = false,
  }) {
    return {
      'v': 1,
      'type': 'session.configure',
      'session_id': sessionId,
      'mode': mode,
      'tts': {
        'enabled': ttsEnabled,
        'voice_id': voiceId,
        'speed': speed,
      },
      'audio': {
        'mic_sample_rate': micSampleRate,
        'playback_sample_rate': playbackSampleRate,
        'codec': codec,
      },
      if (vad != null) 'vad': vad,
      if (memory != null) 'memory': memory,
      if (resume != null) 'resume': resume,
      if (country != null && country.isNotEmpty) 'country': country,
      // Sent whenever the app knows the answer, so withdrawing consent reaches the server on the very next configure.
      if (emotion != null)
        'emotion': {'enabled': emotion, if (emotion && face) 'face_features': true},
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Cancels voice audio synthesis without stopping LLM text streaming (Phase 6).
  Future<void> sendSpeechCancel({
    String? utteranceId,
    bool cancelTts = true,
    bool cancelLlm = false,
    String reason = 'user_tapped_cancel_voice',
  }) async {
    final payload = {
      'v': 1,
      'type': 'speech.cancel',
      'session_id': _sessionId,
      if (utteranceId != null) 'utterance_id': utteranceId,
      'cancel_tts': cancelTts,
      'cancel_llm': cancelLlm,
      'reason': reason,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Aborts assistant response immediately on user speech in call mode (Phase 6).
  Future<void> sendCallBargeIn({
    String? turnId,
    String? utteranceId,
    String reason = 'vad_speech_detected',
  }) async {
    final payload = {
      'v': 1,
      'type': 'call.barge_in',
      'session_id': _sessionId,
      if (turnId != null) 'turn_id': turnId,
      if (utteranceId != null) 'utterance_id': utteranceId,
      'cancel_tts': true,
      'cancel_llm': true,
      'reason': reason,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  /// Ends call mode and returns to chat mode (Phase 6).
  Future<void> sendCallEnd({String reason = 'user_ended_call'}) async {
    final payload = {
      'v': 1,
      'type': 'call.end',
      'session_id': _sessionId,
      'reason': reason,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
  }

  final Map<String, Completer<String?>> _pendingMoments = {};

  /// Asks the companion to quote one good moment from [text], a chat message
  /// the person just sent. Resolves to the quoted sentence, or null when there
  /// is none, the server did not answer in time, or it is not reachable. Never
  /// throws. The server validates its answer; the caller validates it again.
  Future<String?> requestMoment(
    String text, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_channel == null || text.trim().isEmpty) return null;
    final requestId = 'mom_${DateTime.now().microsecondsSinceEpoch}_${_summarySequence++}';
    final completer = Completer<String?>();
    _pendingMoments[requestId] = completer;
    _sendJson({
      'v': 1,
      'type': 'moment.extract',
      'request_id': requestId,
      'text': text,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      _pendingMoments.remove(requestId);
    }
  }

  final Map<String, Completer<String?>> _pendingSummaries = {};
  int _summarySequence = 0;

  /// Asks the companion to fold [messages] into [previousSummary]. Resolves to
  /// the new summary, or null if the server did not answer in time, was not
  /// reachable, or sent nothing usable. Never throws.
  Future<String?> requestSummary({
    required List<Map<String, String>> messages,
    String? previousSummary,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_channel == null || messages.isEmpty) return null;
    final requestId = 'sum_${DateTime.now().microsecondsSinceEpoch}_${_summarySequence++}';
    final completer = Completer<String?>();
    _pendingSummaries[requestId] = completer;
    _sendJson({
      'v': 1,
      'type': 'summary.request',
      'request_id': requestId,
      'previous_summary': previousSummary ?? '',
      'messages': messages,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      _pendingSummaries.remove(requestId);
    }
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        debugPrint('[CompanionWS] Failed to send JSON: $e');
      }
    }
  }

  void _handleIncomingMessage(dynamic raw) {
    try {
      if (raw is List<int>) {
        final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
        if (!_binaryAudioController.isClosed) {
          _binaryAudioController.add(bytes);
        }
        return;
      }
      if (raw is! String) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _rawEventController.add(data);

      final type = data['type'] as String?;
      if (type == null) return;

      if (data.containsKey('session_id')) {
        _sessionId = data['session_id'] as String?;
      }

      switch (type) {
        case 'session_ready':
        case 'session.ready':
          _wasConnected = true;
          _lastErrorMessage = null;
          _updateStatus(CompanionConnectionStatus.connected);
          _startHeartbeat();
          debugPrint('[CompanionWS] Session ready: $_sessionId');
          break;

        case 'pong':
          final clientTs = data['client_ts'] ?? data['ts'];
          if (clientTs is num) {
            final now = DateTime.now().millisecondsSinceEpoch;
            _lastLatencyMs = (now - clientTs.toInt()).clamp(0, 99999);
            if (!_latencyController.isClosed) {
              _latencyController.add(_lastLatencyMs!);
            }
          }
          break;

        case 'echo':
          if (!_echoController.isClosed) {
            _echoController.add(data);
          }
          break;

        case 'moment.proposal':
          final momentId = data['request_id'] as String?;
          final quoted = (data['text'] as String?)?.trim();
          _pendingMoments[momentId]?.complete(
            quoted == null || quoted.isEmpty ? null : quoted,
          );
          break;

        case 'summary.result':
          final id = data['request_id'] as String?;
          final text = (data['summary'] as String?)?.trim();
          _pendingSummaries[id]?.complete(
            text == null || text.isEmpty ? null : text,
          );
          break;

        case 'llm_start':
          if (!_llmStartController.isClosed) {
            _llmStartController.add(data);
          }
          break;

        case 'llm_chunk':
          if (!_llmChunkController.isClosed) {
            _llmChunkController.add(data);
          }
          break;

        case 'llm_done':
          if (!_llmDoneController.isClosed) {
            _llmDoneController.add(data);
          }
          break;

        case 'tts.start':
          if (!_ttsStartController.isClosed) {
            _ttsStartController.add(data);
          }
          break;

        case 'tts.end':
          if (!_ttsEndController.isClosed) {
            _ttsEndController.add(data);
          }
          break;

        case 'tts.segment':
          if (!_ttsSegmentController.isClosed) {
            _ttsSegmentController.add(data);
          }
          break;

        case 'call.state':
          if (!_callStateController.isClosed) {
            _callStateController.add(data);
          }
          break;

        case 'audio_ack':
          if (!_audioAckController.isClosed) {
            _audioAckController.add(data);
          }
          break;

        case 'audio_received':
          if (!_audioReceivedController.isClosed) {
            _audioReceivedController.add(data);
          }
          break;

        case 'turn_cancelled':
          if (!_turnCancelledController.isClosed) {
            _turnCancelledController.add(data);
          }
          break;

        case 'transcript_final':
          if (!_transcriptFinalController.isClosed) {
            _transcriptFinalController.add(data);
          }
          break;

        case 'safety.alert':
          if (!_safetyAlertController.isClosed) {
            _safetyAlertController.add(data);
          }
          break;

        case 'emotion.update':
          if (!_emotionUpdateController.isClosed) {
            _emotionUpdateController.add(data);
          }
          break;

        case 'transcript_failed':
          if (!_transcriptFailedController.isClosed) {
            _transcriptFailedController.add(data);
          }
          break;

        // --- duplex turn lifecycle (spec §7.2) ---
        case 'turn.started':
          if (!_turnStartedController.isClosed) {
            _turnStartedController.add(data);
          }
          break;

        case 'turn.speech_detected':
          if (!_speechDetectedController.isClosed) {
            _speechDetectedController.add(data);
          }
          break;

        case 'turn.endpointed':
          if (!_turnEndpointedController.isClosed) {
            _turnEndpointedController.add(data);
          }
          break;

        case 'turn.processing':
          if (!_turnProcessingController.isClosed) {
            _turnProcessingController.add(data);
          }
          break;

        case 'turn.interrupted':
          if (!_turnInterruptedController.isClosed) {
            _turnInterruptedController.add(data);
          }
          break;

        case 'turn.discarded':
          if (!_turnDiscardedController.isClosed) {
            _turnDiscardedController.add(data);
          }
          break;

        case 'tts.resume':
          if (!_ttsResumeController.isClosed) {
            _ttsResumeController.add(data);
          }
          break;

        case 'turn.diagnostic':
          if (!_turnDiagnosticController.isClosed) {
            _turnDiagnosticController.add(data);
          }
          break;

        case 'turn.latency':
          if (!_turnLatencyController.isClosed) {
            _turnLatencyController.add(data);
          }
          break;

        case 'call.listening':
          if (!_callListeningController.isClosed) {
            _callListeningController.add(data);
          }
          break;

        case 'error':
          debugPrint('[CompanionWS] Server error: ${data['message']}');
          break;

        default:
          debugPrint('[CompanionWS] Unhandled message type: $type');
      }
    } catch (e) {
      debugPrint('[CompanionWS] Failed to parse message: $e');
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _isDisposed || !_wasConnected) return;
    _updateStatus(CompanionConnectionStatus.connecting);
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    final delaySec = (_reconnectAttempts * 2).clamp(1, _maxReconnectDelaySec);
    debugPrint(
      '[CompanionWS] Reconnecting in $delaySec s (attempt $_reconnectAttempts)...',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_isDisposed && !_manualDisconnect && _wasConnected) {
        connect();
      }
    });
  }

  /// Disconnect explicitly (disables auto-reconnect).
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _wasConnected = false;
    _lastErrorMessage = null;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _cleanUpConnection(resetManual: false);
    _updateStatus(CompanionConnectionStatus.disconnected);
  }

  Future<void> _cleanUpConnection({bool resetManual = true}) async {
    for (final pending in [
      ..._pendingSummaries.values,
      ..._pendingMoments.values,
    ]) {
      if (!pending.isCompleted) pending.complete(null);
    }
    if (resetManual) _manualDisconnect = false;
    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    final oldChannel = _channel;
    _channel = null;
    if (oldChannel != null) {
      _safeClose(oldChannel);
    }
  }

  void _safeClose(WebSocketChannel? ch) {
    if (ch == null) return;
    try {
      if (CompanionServerConfig.isTestEnvironment) {
        unawaited(ch.sink.close());
      } else {
        ch.sink.close().timeout(
          const Duration(milliseconds: 250),
          onTimeout: () => null,
        );
      }
    } catch (_) {}
  }

  void dispose() {
    _isDisposed = true;
    if (identical(_live, this)) _live = null;
    _manualDisconnect = true;
    _wasConnected = false;
    _connectSequence++;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _subscription?.cancel();
    } catch (_) {}
    _subscription = null;
    _safeClose(_channel);
    _channel = null;
    _statusController.close();
    _latencyController.close();
    _rawEventController.close();
    _echoController.close();
    _llmStartController.close();
    _llmChunkController.close();
    _llmDoneController.close();
    _audioAckController.close();
    _audioReceivedController.close();
    _turnCancelledController.close();
    _transcriptFinalController.close();
    _safetyAlertController.close();
    _emotionUpdateController.close();
    _transcriptFailedController.close();
    _binaryAudioController.close();
    _ttsStartController.close();
    _ttsEndController.close();
    _ttsSegmentController.close();
    _callStateController.close();
    _turnStartedController.close();
    _speechDetectedController.close();
    _turnEndpointedController.close();
    _turnProcessingController.close();
    _turnInterruptedController.close();
    _turnDiscardedController.close();
    _ttsResumeController.close();
    _turnDiagnosticController.close();
    _turnLatencyController.close();
    _callListeningController.close();
  }
}
