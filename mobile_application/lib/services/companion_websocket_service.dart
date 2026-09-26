import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
    this.host = '127.0.0.1',
    this.port = 8000,
    this.token = 'local-auth-token',
  });

  String host;
  int port;
  String token;

  String? _sessionId;
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

  final _callStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callStateStream => _callStateController.stream;

  void _updateStatus(CompanionConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(newStatus);
      }
    }
  }

  /// Connect to the companion backend.
  Future<void> connect({
    String? customHost,
    int? customPort,
    String? sessionId,
    String? threadId,
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

    final uri = Uri.parse(
      'ws://$host:$port/ws/v1/session?session_id=$_sessionId&token=$token',
    );
    _updateStatus(CompanionConnectionStatus.connecting);

    try {
      await _cleanUpConnection(resetManual: false);
      if (seq != _connectSequence || _isDisposed) return;

      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      // Wait for socket to be established with 5s timeout to prevent infinite hang
      await channel.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Connection to $host:$port timed out (5s)');
        },
      );

      if (seq != _connectSequence || _isDisposed) {
        _safeClose(channel);
        return;
      }

      _reconnectAttempts = 0;

      _subscription = channel.stream.listen(
        _handleIncomingMessage,
        onError: (dynamic error) {
          debugPrint('[CompanionWS] WebSocket stream error: $error');
          _lastErrorMessage = error.toString();
          _updateStatus(CompanionConnectionStatus.error);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[CompanionWS] WebSocket stream done');
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
    } catch (e) {
      if (seq != _connectSequence || _isDisposed) return;
      debugPrint('[CompanionWS] Connection initiation error: $e');
      _wasConnected = false;
      _lastErrorMessage = e is TimeoutException
          ? 'Timed out connecting to $host:$port'
          : 'Failed: $e';
      _updateStatus(CompanionConnectionStatus.error);
      await _cleanUpConnection(resetManual: false);
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
    // 15 seconds interval per section 10
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
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

  /// Sends raw 16-bit PCM binary chunk over the active WebSocket (Phase 2).
  void sendAudioChunk(Uint8List chunk) {
    if (_channel != null && _status == CompanionConnectionStatus.connected) {
      try {
        _channel!.sink.add(chunk);
      } catch (e) {
        debugPrint('[CompanionWS] Failed to send binary audio chunk: $e');
      }
    }
  }

  /// Sends audio_end envelope after finishing recording (Phase 2).
  Future<void> sendAudioEnd({
    required String turnId,
    required int durationMs,
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

  /// Configures session mode, voice settings, and audio parameters (Phase 6).
  Future<void> sendSessionConfigure({
    required String mode,
    bool ttsEnabled = true,
    String voiceId = 'af_heart',
    double speed = 0.96,
    int micSampleRate = 16000,
    int playbackSampleRate = 24000,
    String codec = 'pcm_s16le',
  }) async {
    final payload = {
      'v': 1,
      'type': 'session.configure',
      'session_id': _sessionId,
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
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _sendJson(payload);
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

        case 'transcript_failed':
          if (!_transcriptFailedController.isClosed) {
            _transcriptFailedController.add(data);
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
      ch.sink.close().timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => null,
      );
    } catch (_) {}
  }

  void dispose() {
    _isDisposed = true;
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
    _transcriptFailedController.close();
    _binaryAudioController.close();
    _ttsStartController.close();
    _ttsEndController.close();
    _callStateController.close();
  }
}
