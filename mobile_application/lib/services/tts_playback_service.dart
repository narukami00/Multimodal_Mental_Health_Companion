import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'companion_websocket_service.dart';
import 'pcm_audio_recorder_service.dart';

/// Manages incoming streaming binary audio from the Solace companion server (Phase 6),
/// builds PCM/WAV buffers, handles live audio playback with smooth cancellation (fade-out),
/// and exposes reactive streams for amplitude and playback state.
class TtsPlaybackService {
  TtsPlaybackService({
    required CompanionWebSocketService webSocketService,
    AudioPlayer? audioPlayer,
    this.isMock = false,
  })  : _wsService = webSocketService,
        _audioPlayer = audioPlayer ??
            (isMock || Platform.environment.containsKey('FLUTTER_TEST')
                ? null
                : AudioPlayer()) {
    if (!_isTestEnv) _configureAudioContext();
    _initSubscriptions();
  }

  static bool get _isTestEnv =>
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Configures clean, high-fidelity media playback through the main loudspeaker
  /// in both chat mode and call mode. Avoids telephony DSP filtering and earpiece routing.
  void _configureAudioContext() {
    final context = AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransient,
        audioMode: AndroidAudioMode.normal,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {
          AVAudioSessionOptions.defaultToSpeaker,
          AVAudioSessionOptions.allowBluetooth,
        },
      ),
    );
    unawaited(AudioPlayer.global.setAudioContext(context));
    final player = _audioPlayer;
    if (player != null) unawaited(player.setAudioContext(context));
  }

  final bool isMock;
  final CompanionWebSocketService _wsService;
  final AudioPlayer? _audioPlayer;

  StreamSubscription<Map<String, dynamic>>? _ttsStartSub;
  StreamSubscription<Map<String, dynamic>>? _ttsEndSub;
  StreamSubscription<Map<String, dynamic>>? _ttsSegmentSub;
  StreamSubscription<Uint8List>? _binaryAudioSub;
  StreamSubscription<void>? _playerCompleteSub;

  int? _activeStreamId;
  String? _activeUtteranceId;
  int _activeSampleRate = 24000;
  String? _activeVoiceId;

  final BytesBuilder _currentSegmentPcm = BytesBuilder(copy: false);
  final BytesBuilder _fullUtterancePcm = BytesBuilder(copy: false);
  final List<Uint8List> _playbackQueue = [];

  String? _lastGeneratedAudioPath;
  String? _activePlayingPath;

  bool _isPlaying = false;
  bool _isPlayerActive = false;
  bool _isReceivingStream = false;
  double _currentAmplitude = 0.0;

  bool get isPlaying => _isPlaying;
  bool get isReceivingStream => _isReceivingStream;
  int? get activeStreamId => _activeStreamId;
  String? get activeUtteranceId => _activeUtteranceId;
  String? get lastGeneratedAudioPath => _lastGeneratedAudioPath;
  String? get activePlayingPath => _activePlayingPath;
  double get currentAmplitude => _currentAmplitude;

  final _playingController = StreamController<bool>.broadcast();
  Stream<bool> get playingStream => _playingController.stream;

  final _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  final _audioReadyController = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get audioReadyStream => _audioReadyController.stream;

  void _initSubscriptions() {
    _ttsStartSub = _wsService.ttsStartStream.listen(_onTtsStart);
    _ttsEndSub = _wsService.ttsEndStream.listen(_onTtsEnd);
    _ttsSegmentSub = _wsService.ttsSegmentStream.listen(_onTtsSegment);
    _binaryAudioSub = _wsService.binaryAudioStream.listen(_onBinaryFrame);

    _playerCompleteSub = _audioPlayer?.onPlayerComplete.listen((_) {
      _onSegmentPlaybackComplete();
    });
  }

  void _setPlaying(bool val) {
    if (_isPlaying != val) {
      _isPlaying = val;
      if (!_playingController.isClosed) {
        _playingController.add(val);
      }
    }
  }

  void _onTtsStart(Map<String, dynamic> data) {
    _activeUtteranceId = data['utterance_id'] as String?;
    _activeStreamId = data['audio_stream_id'] as int?;
    _activeSampleRate = data['sample_rate'] as int? ?? 24000;
    _activeVoiceId = data['voice_id'] as String? ?? 'af_heart';

    _currentSegmentPcm.clear();
    _fullUtterancePcm.clear();
    _playbackQueue.clear();
    _isReceivingStream = true;
    debugPrint(
      '[TtsPlayback] Started stream $_activeStreamId (utterance: $_activeUtteranceId, sr: $_activeSampleRate, voice: $_activeVoiceId)',
    );
  }

  void _onBinaryFrame(Uint8List frame) {
    if (frame.length < 8) return;

    final header = ByteData.sublistView(frame);
    final streamId = header.getUint32(0, Endian.little);
    final seq = header.getUint32(4, Endian.little);

    // Stale frame from previously cancelled utterance -> drop cleanly!
    if (_activeStreamId != null && streamId != _activeStreamId) {
      return;
    }

    final pcmPayload = frame.sublist(8);
    _currentSegmentPcm.add(pcmPayload);
    _fullUtterancePcm.add(pcmPayload);

    // Compute RMS amplitude for fluid orb or animated equalizer
    final amp = _computePcmRms(pcmPayload);
    _currentAmplitude = amp;
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(amp);
    }

    if (seq % 10 == 0) {
      debugPrint(
        '[TtsPlayback] Frame #$seq for stream $streamId (seg ${_currentSegmentPcm.length} B, total ${_fullUtterancePcm.length} B, amp: ${amp.toStringAsFixed(2)})',
      );
    }
  }

  void _onTtsSegment(Map<String, dynamic> data) {
    final streamId = data['audio_stream_id'] as int?;
    final state = data['state'] as String?;
    if (_activeStreamId != null && streamId != null && streamId != _activeStreamId) {
      return;
    }

    if (state == 'ended') {
      final segPcm = _currentSegmentPcm.toBytes();
      _currentSegmentPcm.clear();
      if (segPcm.isNotEmpty) {
        final wavData = PcmAudioRecorderService.createWav(
          segPcm,
          sampleRate: _activeSampleRate,
          channels: 1,
          bitsPerSample: 16,
        );
        _enqueueSegment(wavData);
      }
    }
  }

  void _enqueueSegment(Uint8List wavBytes) {
    _playbackQueue.add(wavBytes);
    if (!_isPlayerActive) {
      _playNextSegment();
    }
  }

  Future<void> _playNextSegment() async {
    if (_playbackQueue.isEmpty) {
      _isPlayerActive = false;
      if (!_isReceivingStream) {
        _setPlaying(false);
        _currentAmplitude = 0.0;
        if (!_amplitudeController.isClosed) {
          _amplitudeController.add(0.0);
        }
      }
      return;
    }

    final nextWav = _playbackQueue.removeAt(0);
    _isPlayerActive = true;
    _setPlaying(true);

    if (_audioPlayer != null) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setVolume(1.0);
        debugPrint('[TtsPlayback] Playing segment: ${nextWav.length} bytes '
            '(queue remaining: ${_playbackQueue.length})');
        await _audioPlayer.play(BytesSource(nextWav));
      } catch (e) {
        debugPrint('[TtsPlayback] Segment playback error: $e');
        _isPlayerActive = false;
        _playNextSegment();
      }
    } else {
      // In mock / test environment, immediately proceed
      _isPlayerActive = false;
      if (_playbackQueue.isEmpty && !_isReceivingStream) {
        _setPlaying(false);
      }
    }
  }

  void _onSegmentPlaybackComplete() {
    _isPlayerActive = false;
    _playNextSegment();
  }

  Future<void> _onTtsEnd(Map<String, dynamic> data) async {
    _isReceivingStream = false;
    final streamId = data['audio_stream_id'] as int?;
    final cancelled = data['cancelled'] as bool? ?? false;

    if (_activeStreamId != null && streamId != null && streamId != _activeStreamId) {
      return;
    }

    if (cancelled) {
      debugPrint('[TtsPlayback] TTS stream $streamId cancelled by server/client.');
      _playbackQueue.clear();
      _currentSegmentPcm.clear();
      _fullUtterancePcm.clear();
      await stopVoice(fadeMs: 25);
      return;
    }

    // Flush any leftover pcm in current segment buffer
    final leftover = _currentSegmentPcm.toBytes();
    _currentSegmentPcm.clear();
    if (leftover.isNotEmpty) {
      final wavData = PcmAudioRecorderService.createWav(
        leftover,
        sampleRate: _activeSampleRate,
        channels: 1,
        bitsPerSample: 16,
      );
      _enqueueSegment(wavData);
    }

    final fullPcm = _fullUtterancePcm.toBytes();
    if (fullPcm.isNotEmpty) {
      try {
        final wavData = PcmAudioRecorderService.createWav(
          fullPcm,
          sampleRate: _activeSampleRate,
          channels: 1,
          bitsPerSample: 16,
        );

        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/tts_${_activeUtteranceId ?? DateTime.now().millisecondsSinceEpoch}.wav';
        final file = File(path);
        await file.writeAsBytes(wavData, flush: true);
        _lastGeneratedAudioPath = path;
        if (_activeUtteranceId != null && !_audioReadyController.isClosed) {
          _audioReadyController.add({
            'utterance_id': _activeUtteranceId!,
            'audio_path': path,
          });
        }
      } catch (err) {
        debugPrint('[TtsPlayback] Notice: could not cache WAV to disk: $err');
      }
    }

    if (_playbackQueue.isEmpty && !_isPlayerActive) {
      _setPlaying(false);
      _currentAmplitude = 0.0;
      if (!_amplitudeController.isClosed) {
        _amplitudeController.add(0.0);
      }
    }
  }

  /// Cancels voice playback immediately with a smooth 25ms fade-out to prevent clicks/pops,
  /// and sends a `speech.cancel` envelope to the companion server.
  Future<void> cancelVoice({String? utteranceId, String reason = 'user_tapped_cancel_voice'}) async {
    final uttId = utteranceId ?? _activeUtteranceId;
    _activeStreamId = null;
    _activeUtteranceId = null;
    _activePlayingPath = null;
    _isReceivingStream = false;
    _isPlayerActive = false;
    _playbackQueue.clear();
    _currentSegmentPcm.clear();
    _fullUtterancePcm.clear();

    await stopVoice(fadeMs: 25);

    // Notify backend to halt TTS worker without terminating LLM text stream
    _wsService.sendSpeechCancel(
      utteranceId: uttId,
      cancelTts: true,
      cancelLlm: false,
      reason: reason,
    );
  }

  /// Stops current audio playback with optional smooth fade-out.
  Future<void> stopVoice({int fadeMs = 25}) async {
    _activePlayingPath = null;
    _playbackQueue.clear();
    _isPlayerActive = false;
    if (_isPlaying) {
      try {
        if (_audioPlayer != null) {
          if (fadeMs > 0) {
            // Rapid volume ramp down
            await _audioPlayer.setVolume(0.0);
            await Future<void>.delayed(Duration(milliseconds: fadeMs));
          }
          await _audioPlayer.stop();
          await _audioPlayer.setVolume(1.0);
        }
      } catch (e) {
        debugPrint('[TtsPlayback] Error stopping player: $e');
      }
    }
    _setPlaying(false);
    _currentAmplitude = 0.0;
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(0.0);
    }
  }

  /// Replays audio from a local WAV file path.
  Future<void> playAudioFile(String path, {String? utteranceId}) async {
    final file = File(path);
    if (!file.existsSync() && !isMock && !_isTestEnv) return;
    try {
      await stopVoice();
      _activeUtteranceId = utteranceId;
      _activePlayingPath = path;
      if (_audioPlayer != null) {
        await _audioPlayer.play(DeviceFileSource(path));
      }
      _isPlayerActive = true;
      _setPlaying(true);
    } catch (e) {
      _isPlayerActive = false;
      debugPrint('[TtsPlayback] Error replaying audio file: $e');
    }
  }

  double _computePcmRms(Uint8List pcm16Bytes) {
    if (pcm16Bytes.length < 2) return 0.0;
    final byteData = ByteData.sublistView(pcm16Bytes);
    final count = pcm16Bytes.length ~/ 2;
    var sumSquares = 0.0;
    for (var i = 0; i < count; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      final norm = sample / 32768.0;
      sumSquares += norm * norm;
    }
    final rms = math.sqrt(sumSquares / count);
    return (rms * 2.8).clamp(0.0, 1.0);
  }

  void dispose() {
    _ttsStartSub?.cancel();
    _ttsEndSub?.cancel();
    _ttsSegmentSub?.cancel();
    _binaryAudioSub?.cancel();
    _playerCompleteSub?.cancel();
    _audioPlayer?.dispose();
    _playingController.close();
    _amplitudeController.close();
    _audioReadyController.close();
  }
}
