import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service responsible for recording raw 16 kHz PCM 16-bit mono audio
/// and streaming chunks (default 100ms / 3200 bytes) over an EventChannel.
class PcmAudioRecorderService {
  static const MethodChannel _controlChannel =
      MethodChannel('com.sysmentalhealth.solace_mobile/audio_control');
  static const EventChannel _streamChannel =
      EventChannel('com.sysmentalhealth.solace_mobile/audio_stream');

  final bool isMock;
  PcmAudioRecorderService({this.isMock = false});

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  StreamSubscription<dynamic>? _nativeStreamSub;

  final _audioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioStream => _audioController.stream;

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

  /// Start recording raw PCM audio at the specified sample rate (default 16000 Hz, 100ms frames).
  Future<bool> startRecording({
    int sampleRate = 16000,
    int frameMs = 100,
  }) async {
    if (_isRecording) return true;

    final permitted = await requestPermission();
    if (!permitted) {
      debugPrint('[PcmAudioRecorder] Cannot record: permission denied');
      return false;
    }

    _isRecording = true;

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
          if (chunk is Uint8List) {
            _onAudioChunk(chunk);
          } else if (chunk is List<int>) {
            _onAudioChunk(Uint8List.fromList(chunk));
          }
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

  void _onAudioChunk(Uint8List chunk) {
    if (!_audioController.isClosed) {
      _audioController.add(chunk);
    }
    final amp = computeRmsAmplitude(chunk);
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(amp);
    }
  }

  void _startMockStreaming(int sampleRate, int frameMs) {
    _mockTimer?.cancel();
    final frameBytes = (sampleRate * 2 * frameMs) ~/ 1000;
    _mockTimer = Timer.periodic(Duration(milliseconds: frameMs), (t) {
      if (!_isRecording) {
        t.cancel();
        return;
      }
      final chunk = Uint8List(frameBytes);
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

  /// Compute normalized RMS (Root Mean Square) amplitude (0.0 .. 1.0) from 16-bit PCM.
  static double computeRmsAmplitude(Uint8List bytes) {
    if (bytes.length < 2) return 0.0;
    var sumSquares = 0.0;
    final sampleCount = bytes.length ~/ 2;
    for (var i = 0; i < bytes.length - 1; i += 2) {
      var sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample >= 32768) sample -= 65536;
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    // Typical voice RMS is between 300 and 8000; normalize to 0.0 - 1.0
    return (rms / 6000.0).clamp(0.0, 1.0);
  }

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
