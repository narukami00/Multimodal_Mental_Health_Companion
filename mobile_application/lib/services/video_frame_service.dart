import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'companion_auth.dart';
import 'account_service.dart';

/// Where upright camera frames come from. The real source (the phone camera) is
/// platform code; tests and previews use a fake. A frame is ONE upright JPEG,
/// already rotated so the face is the right way up: a rotated frame is not
/// recognised as a face by the server.
abstract class FrameSource {
  Stream<Uint8List> get frames;

  /// Opens the camera. False when it could not be opened (no permission, in use).
  Future<bool> start();

  /// Closes the camera. Must be safe to call twice.
  Future<void> stop();
}

enum VideoStreamState { off, connecting, streaming, refused, error }

/// Streams camera frames to the companion server's video socket
/// (`/ws/v1/video`), only while the person has agreed to it.
///
/// The camera consent is checked here before anything is opened, and again for
/// every frame: switching it off stops the camera and the upload at once. If
/// the server refuses (no matching consent on its side, or the camera analysis
/// is off there) the camera is closed too, so the phone never keeps filming for
/// nothing. Nothing is stored on the phone.
class VideoFrameService extends ChangeNotifier {
  VideoFrameService({
    required this.source,
    required this.uriProvider,
    required this.consentGranted,
    WebSocketChannel Function(Uri uri)? connect,
    CompanionTokenProvider? tokenProvider,
    CompanionTransportPolicy? transportPolicy,
    this.minGap = const Duration(milliseconds: 180),
    this.staleAfter = const Duration(milliseconds: 600),
    this.handshakeTimeout = const Duration(seconds: 3),
  }) : _connect = connect,
       _tokenProvider = tokenProvider ?? companionIdToken,
       _transportPolicy = transportPolicy ?? CompanionTransportPolicy() {
    if (connect == null && tokenProvider == null) {
      _account = AccountService.instance;
      _account!.addListener(_onAccountChanged);
    }
  }

  AccountService? _account;
  String? _connectedUid;
  bool get _hasSameAccount =>
      _account == null ||
      (_connectedUid != null && _account!.identity?.uid == _connectedUid);
  void _onAccountChanged() {
    if (_connectedUid != null && _account?.identity?.uid != _connectedUid) {
      _connectedUid = null;
      unawaited(stop());
    }
  }

  final FrameSource source;

  /// The video socket address (null while the call is not connected).
  final Uri? Function() uriProvider;

  /// Whether the person agreed to the camera being analysed right now.
  final bool Function() consentGranted;

  /// Fastest frame rate sent, and how long to wait for an acknowledgement
  /// before sending the next frame anyway (the server drops what it cannot take).
  final Duration minGap;
  final Duration staleAfter;
  final Duration handshakeTimeout;
  final WebSocketChannel Function(Uri uri)? _connect;
  final CompanionTokenProvider _tokenProvider;
  final CompanionTransportPolicy _transportPolicy;

  /// The latest camera frame, for the on-screen self view (null while the camera is closed). Shown on
  /// the phone only; what is sent to the server is throttled separately.
  final ValueNotifier<Uint8List?> preview = ValueNotifier<Uint8List?>(null);

  VideoStreamState _state = VideoStreamState.off;
  bool? _lastUsable;
  int _sent = 0;
  int _seq = 0;
  int _serverDropped = 0;
  String? _refusedReason;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  StreamSubscription<Uint8List>? _frameSub;
  Completer<bool>? _ready;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _awaitingAckSince;

  VideoStreamState get state => _state;

  /// Whether the last acknowledged frame had a usable face (null = unknown).
  bool? get lastUsable => _lastUsable;
  int get framesSent => _sent;
  int get serverDropped => _serverDropped;
  String? get refusedReason => _refusedReason;
  bool get streaming => _state == VideoStreamState.streaming;

  /// Opens the camera and the socket. Does nothing without consent. Returns
  /// whether frames are now flowing.
  Future<bool> start() async {
    if (_state == VideoStreamState.streaming ||
        _state == VideoStreamState.connecting) {
      return streaming;
    }
    if (!consentGranted()) return false;
    final uri = uriProvider();
    if (uri == null) {
      _setState(VideoStreamState.error);
      return false;
    }
    _refusedReason = null;
    _setState(VideoStreamState.connecting);
    try {
      final channel = await _open(uri);
      if (!consentGranted() || !_hasSameAccount) {
        unawaited(channel.sink.close());
        return false;
      }
      _channel = channel;
      _ready = Completer<bool>();
      _channelSub = channel.stream.listen(
        _onMessage,
        onError: (_) => _fail(),
        onDone: () {
          if (_ready != null && !_ready!.isCompleted) _ready!.complete(false);
          if (_state == VideoStreamState.streaming) _fail();
        },
      );
      await channel.ready;
      channel.sink.add(
        jsonEncode({'type': 'video.start', 'codec': 'jpeg', 'upright': true}),
      );
      final ok = await _ready!.future.timeout(
        handshakeTimeout,
        onTimeout: () => false,
      );
      if (!ok || !consentGranted() || !_hasSameAccount) {
        await stop(refused: _state == VideoStreamState.refused);
        if (_state == VideoStreamState.off) _setState(VideoStreamState.error);
        return false;
      }
      if (!await source.start()) {
        await stop();
        _setState(VideoStreamState.error);
        return false;
      }
      _frameSub = source.frames.listen(_onFrame);
      _setState(VideoStreamState.streaming);
      return true;
    } catch (error) {
      if (error is CompanionSecureConnectionRequired) {
        _refusedReason = error.toString();
      }
      await stop();
      _setState(VideoStreamState.error);
      return false;
    }
  }

  Future<WebSocketChannel> _open(Uri uri) async {
    if (_connect != null) return _connect(uri);
    _transportPolicy.requireSecure(uri);
    _connectedUid = _account?.identity?.uid;
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _tokenProvider(forceRefresh: attempt == 1);
      if (token == null ||
          token.isEmpty ||
          !consentGranted() ||
          !_hasSameAccount) {
        throw const CompanionSignInRequired();
      }
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      try {
        await channel.ready.timeout(handshakeTimeout);
        return channel;
      } catch (error) {
        unawaited(channel.sink.close());
        if (attempt == 1 ||
            !(error.toString().contains('401') ||
                error.toString().contains('403'))) {
          rethrow;
        }
      }
    }
    throw StateError('Unreachable authentication retry');
  }

  /// Stops the camera and closes the socket. Safe to call at any time.
  Future<void> stop({bool refused = false}) async {
    if (_ready != null && !_ready!.isCompleted) _ready!.complete(false);
    await _frameSub?.cancel();
    _frameSub = null;
    await source.stop();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        channel.sink.add(jsonEncode({'type': 'video.stop'}));
      } catch (_) {}
      await _channelSub?.cancel();
      _channelSub = null;
      try {
        await channel.sink.close();
      } catch (_) {}
    }
    _awaitingAckSince = null;
    preview.value = null;
    if (!refused) _setState(VideoStreamState.off);
  }

  void _onFrame(Uint8List jpeg) {
    final channel = _channel;
    if (channel == null || _state != VideoStreamState.streaming) return;
    preview.value = jpeg;
    if (!consentGranted() || !_hasSameAccount) {
      unawaited(stop());
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastSentAt) < minGap) return;
    final waiting = _awaitingAckSince;
    if (waiting != null && now.difference(waiting) < staleAfter) return;
    final frame = BytesBuilder(copy: false)
      ..add(
        (ByteData(4)..setUint32(0, _seq++, Endian.little)).buffer.asUint8List(),
      )
      ..add(jpeg);
    channel.sink.add(frame.takeBytes());
    _lastSentAt = now;
    _awaitingAckSince = now;
    _sent++;
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (message['type']) {
      case 'video.ready':
        if (_ready != null && !_ready!.isCompleted) _ready!.complete(true);
      case 'video.ack':
        _awaitingAckSince = null;
        final usable = message['usable'];
        _lastUsable = usable is num ? usable != 0 : null;
        _serverDropped =
            (message['dropped'] as num?)?.toInt() ?? _serverDropped;
        notifyListeners();
      case 'video.refused':
        _refusedReason = message['reason'] as String? ?? 'refused';
        if (_ready != null && !_ready!.isCompleted) _ready!.complete(false);
        _setState(VideoStreamState.refused);
        unawaited(stop(refused: true));
    }
  }

  void _fail() {
    if (_state == VideoStreamState.refused) return;
    unawaited(stop());
    _setState(VideoStreamState.error);
  }

  void _setState(VideoStreamState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _account?.removeListener(_onAccountChanged);
    unawaited(stop());
    super.dispose();
  }
}
