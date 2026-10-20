import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_processor.dart';

/// Records raw 16 kHz PCM 16-bit mono audio over an EventChannel and measures
/// every frame exactly once.
///
/// Capture only: it never decides whether anyone is speaking. A call streams
/// every frame to the server, whose VAD finds the speech; the level measured
/// here drives the orb's animation and nothing else.
class PcmAudioRecorderService {
  static const MethodChannel _controlChannel =
      MethodChannel('com.sysmentalhealth.solace_mobile/audio_control');
  static const EventChannel _streamChannel =
      EventChannel('com.sysmentalhealth.solace_mobile/audio_stream');

  final bool isMock;

  /// Mock capture cadence: a burst of tone, then silence, repeating.
  final int mockSpeechMs;
  final int mockSilenceMs;

  PcmAudioRecorderService({
    this.isMock = false,
    this.mockSpeechMs = 700,
    this.mockSilenceMs = 500,
    AudioProcessor? processor,
  }) : processor = processor ?? AudioProcessor();

  /// Frame measurement for the orb. Exposed for diagnostics.
  final AudioProcessor processor;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Frame size the session was started with. Every duration is derived from
  /// it, never from a hardcoded frame count.
  int get frameMs => _frameMs;
  int _frameMs = 20;

  int _frameSeq = 0;
  int _samplesPerFrame = 320;

  /// Current room-noise level (normalised RMS), for the orb's display gate.
  double get floorRms => processor.floorRms;

  StreamSubscription<dynamic>? _nativeStreamSub;

  final _audioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioStream => _audioController.stream;

  final _frameMetricsController = StreamController<FrameMetrics>.broadcast();
  Stream<FrameMetrics> get frameMetricsStream => _frameMetricsController.stream;

  /// Display-only level curve for waveform visuals. **Never a gate input** — the
  /// gate reads [FrameMetrics.snrDb] only.
  final _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  Timer? _mockTimer;

  /// Check whether microphone recording permission is granted.
  Future<bool> hasPermission() async {
    if (isMock) return true;
    try {
      final granted =
          await _controlChannel.invokeMethod<bool>('hasPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('[PcmAudioRecorder] hasPermission check failed: $e');
      return false;
    }
  }

  /// Request microphone recording permission.
  Future<bool> requestPermission() async {
    if (isMock) return true;
    try {
      final granted =
          await _controlChannel.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('[PcmAudioRecorder] requestPermission failed: $e');
      return false;
    }
  }

  /// Start recording raw PCM audio (default 16000 Hz, 20 ms frames — 640 bytes).
  /// 20 ms is the resolution every VAD threshold in the spec is expressed in.
  Future<bool> startRecording({
    int sampleRate = 16000,
    int frameMs = 20,
  }) async {
    if (_isRecording) return true;

    final permitted = await requestPermission();
    if (!permitted) {
      debugPrint('[PcmAudioRecorder] Cannot record: permission denied');
      return false;
    }

    _isRecording = true;
    _frameMs = frameMs;
    _samplesPerFrame = sampleRate * frameMs ~/ 1000;
    _frameSeq = 0;
    processor.reset();

    if (isMock) {
      _startMockStreaming(sampleRate, frameMs);
      return true;
    }

    try {
      final started = await _controlChannel.invokeMethod<bool>(
        'startRecording',
        {
          'sampleRate': sampleRate,
          'frameMs': frameMs,
        },
      );

      if (started != true) {
        _isRecording = false;
        return false;
      }

      await _nativeStreamSub?.cancel();
      _nativeStreamSub = _streamChannel.receiveBroadcastStream().listen(
        (dynamic chunk) {
          if (!_isRecording) return;
          final frame = _decodeFrame(chunk);
          if (frame != null) _onAudioChunk(frame);
        },
        onError: (dynamic err) {
          debugPrint('[PcmAudioRecorder] Native audio stream error: $err');
        },
        cancelOnError: false,
      );

      return true;
    } catch (e) {
      debugPrint('[PcmAudioRecorder] startRecording error: $e');
      _isRecording = false;
      return false;
    }
  }

  /// The capture path sends `{seq, samples, pcm}` so every frame carries a
  /// monotonic position on the audio timeline. A bare list is still accepted so
  /// an older native build degrades to a locally-sequenced stream.
  static Uint8List? _decodeFrame(dynamic chunk) {
    if (chunk is Uint8List) return chunk;
    if (chunk is List<int>) return Uint8List.fromList(chunk);
    if (chunk is Map) {
      final pcm = chunk['pcm'];
      if (pcm is Uint8List) return pcm;
      if (pcm is List<int>) return Uint8List.fromList(pcm);
    }
    return null;
  }

  /// The single place a frame is measured.
  void _onAudioChunk(Uint8List chunk) {
    if (!_audioController.isClosed) {
      _audioController.add(chunk);
    }
    final metrics = processor.step(
      frame: chunk,
      seq: _frameSeq,
      sampleOffset: _frameSeq * _samplesPerFrame,
      frameMs: _frameMs,
    );
    _frameSeq++;
    if (!_frameMetricsController.isClosed) {
      _frameMetricsController.add(metrics);
    }
    if (!_amplitudeController.isClosed) {
      // Perceptual curve for visuals only; the gate never sees this.
      _amplitudeController.add(math.sqrt(metrics.rms));
    }
  }

  /// Whether the audio is going to headphones, earbuds or a headset rather than
  /// the phone's loudspeaker. Only then can the microphone stay open while the
  /// assistant talks: a loudspeaker's own voice would come straight back in.
  Future<bool> isHeadsetConnected() async {
    if (isMock) return false;
    try {
      final route =
          await _controlChannel.invokeMapMethod<String, dynamic>('outputRoute');
      return route?['headset'] as bool? ?? false;
    } catch (e) {
      debugPrint('[PcmAudioRecorder] outputRoute failed: $e');
      return false;
    }
  }

  /// Whether platform echo cancellation is engaged on the capture session.
  /// `null` until the capture path has been started.
  Future<Map<String, dynamic>?> captureInfo() async {
    if (isMock) {
      return const {'aec_active': false, 'aec_source': 'mock'};
    }
    try {
      final info =
          await _controlChannel.invokeMapMethod<String, dynamic>('captureInfo');
      return info;
    } catch (e) {
      debugPrint('[PcmAudioRecorder] captureInfo failed: $e');
      return null;
    }
  }

  void _startMockStreaming(int sampleRate, int frameMs) {
    _mockTimer?.cancel();
    final frameBytes = (sampleRate * 2 * frameMs) ~/ 1000;
    // A synthesised speech/silence cadence, not zeros: a mock that emits silence
    // can never exercise turn logic (the original defect).
    final period = math.max(
        1, ((mockSpeechMs + mockSilenceMs) / frameMs).round());
    final speechFrames = math.max(1, (mockSpeechMs / frameMs).round());
    _mockTimer = Timer.periodic(Duration(milliseconds: frameMs), (t) {
      if (!_isRecording) {
        t.cancel();
        return;
      }
      // t.tick counts firings, i.e. frames - the cadence is in frames.
      final tick = t.tick;
      final inSpeech = (tick % period) < speechFrames;
      final chunk = Uint8List(frameBytes);
      if (inSpeech) {
        final data = ByteData.sublistView(chunk);
        for (var i = 0; i < frameBytes ~/ 2; i++) {
          final value = 6000.0 * math.sin(2 * math.pi * 220 * i / 16000);
          data.setInt16(i * 2, value.round(), Endian.little);
        }
      }
      _onAudioChunk(chunk);
    });
  }

  /// Stop recording cleanly and finish the stream.
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    _mockTimer?.cancel();
    _mockTimer = null;

    if (!isMock) {
      try {
        await _controlChannel.invokeMethod<void>('stopRecording');
      } catch (e) {
        debugPrint('[PcmAudioRecorder] stopRecording error: $e');
      }
    }
    await _nativeStreamSub?.cancel();
    _nativeStreamSub = null;
  }

  /// Cancel recording (discard buffered data).
  Future<void> cancelRecording() async {
    await stopRecording();
  }

  /// Raw frame RMS, normalised to full scale (1.0 == 32767), with the frame's
  /// DC offset removed. Thresholds live in [AudioProcessor] and are expressed in
  /// dB above the tracked floor — never derived from this number.
  static double computeRmsAmplitude(Uint8List bytes) =>
      AudioProcessor.computeRmsAmplitude(bytes);

  /// Generate a standard 44-byte RIFF WAV file from raw 16-bit PCM audio bytes.
  static Uint8List createWav(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final totalDataLen = pcmBytes.length;
    final totalAudioLen = totalDataLen + 36;

    final header = ByteData(44);
    // 'RIFF'
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    // File size - 8
    header.setUint32(4, totalAudioLen, Endian.little);
    // 'WAVE'
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // 'fmt '
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    // Subchunk1Size (16 for PCM)
    header.setUint32(16, 16, Endian.little);
    // AudioFormat (1 = PCM)
    header.setUint16(20, 1, Endian.little);
    // NumChannels
    header.setUint16(22, channels, Endian.little);
    // SampleRate
    header.setUint32(24, sampleRate, Endian.little);
    // ByteRate
    header.setUint32(28, byteRate, Endian.little);
    // BlockAlign
    header.setUint16(32, blockAlign, Endian.little);
    // BitsPerSample
    header.setUint16(34, bitsPerSample, Endian.little);
    // 'data'
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    // Subchunk2Size
    header.setUint32(40, totalDataLen, Endian.little);

    final out = Uint8List(44 + totalDataLen);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + totalDataLen, pcmBytes);
    return out;
  }

  /// Extract a normalized acoustic waveform envelope (0.12 .. 1.0) from raw 16-bit PCM bytes.
  static List<double> extractWaveform(Uint8List bytes, {int barCount = 24}) {
    if (barCount <= 0) return const [];
    final sampleCount = bytes.length ~/ 2;
    const minHeight = 0.12;
    if (sampleCount == 0) {
      return List<double>.filled(barCount, minHeight);
    }

    final rawAmplitudes = <double>[];
    for (var b = 0; b < barCount; b++) {
      final startSample = (b * sampleCount) ~/ barCount;
      final endSample = math.min(sampleCount, ((b + 1) * sampleCount) ~/ barCount);
      if (startSample >= endSample) {
        rawAmplitudes.add(0.0);
        continue;
      }

      var sumSquares = 0.0;
      var count = 0;
      for (var s = startSample; s < endSample; s++) {
        final byteIdx = s * 2;
        var sample = bytes[byteIdx] | (bytes[byteIdx + 1] << 8);
        if (sample >= 32768) sample -= 65536;
        sumSquares += sample * sample;
        count++;
      }
      final rms = count > 0 ? math.sqrt(sumSquares / count) : 0.0;
      rawAmplitudes.add(rms);
    }

    var maxRms = 0.0;
    for (final v in rawAmplitudes) {
      if (v > maxRms) maxRms = v;
    }

    if (maxRms < 1e-4) {
      return List<double>.filled(barCount, minHeight);
    }

    return rawAmplitudes.map((rms) {
      final ratio = (rms / maxRms).clamp(0.0, 1.0);
      return (minHeight + (1.0 - minHeight) * ratio).clamp(minHeight, 1.0);
    }).toList(growable: false);
  }

  void dispose() {
    stopRecording();
    _audioController.close();
    _amplitudeController.close();
  }
}
