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
    if (customHost != null) host = customHost;
    if (customPort != null) port = customPort;
    if (sessionId != null) _sessionId = sessionId;
    if (threadId != null) _threadId = threadId;

    _manualDisconnect = false;
    _sessionId ??=
        'sess_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    _threadId ??= 'thread_main';

    final uri = Uri.parse(
      'ws://$host:$port/ws/v1/session?session_id=$_sessionId&token=$token',
    );
    _updateStatus(CompanionConnectionStatus.connecting);

    try {
      await _cleanUpConnection(resetManual: false);
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      // Wait for socket to be established
      await channel.ready;

      _reconnectAttempts = 0;

      _subscription = channel.stream.listen(
        _handleIncomingMessage,
        onError: (dynamic error) {
          debugPrint('[CompanionWS] WebSocket stream error: $error');
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
      debugPrint('[CompanionWS] Connection initiation error: $e');
      _updateStatus(CompanionConnectionStatus.error);
      _scheduleReconnect();
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
    if (_manualDisconnect || _isDisposed) return;
    _updateStatus(CompanionConnectionStatus.connecting);
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    final delaySec = (_reconnectAttempts * 2).clamp(1, _maxReconnectDelaySec);
    debugPrint(
      '[CompanionWS] Reconnecting in $delaySec s (attempt $_reconnectAttempts)...',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_isDisposed && !_manualDisconnect) {
        connect();
      }
    });
  }

  /// Disconnect explicitly (disables auto-reconnect).
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _cleanUpConnection(resetManual: false);
    _updateStatus(CompanionConnectionStatus.disconnected);
  }

  Future<void> _cleanUpConnection({bool resetManual = true}) async {
    if (resetManual) _manualDisconnect = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void dispose() {
    _isDisposed = true;
    _manualDisconnect = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _statusController.close();
    _latencyController.close();
    _rawEventController.close();
    _echoController.close();
    _llmStartController.close();
    _llmChunkController.close();
    _llmDoneController.close();
  }
}
