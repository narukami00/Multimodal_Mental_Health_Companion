import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/audio_processor.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';

Uint8List sine({double amplitude = 15000, int sampleCount = 1600, int freq = 440}) {
  final buffer = Uint8List(sampleCount * 2);
  final byteData = ByteData.sublistView(buffer);
  for (var i = 0; i < sampleCount; i++) {
    final sample = (amplitude * math.sin(2 * math.pi * freq * i / 16000)).toInt();
    byteData.setInt16(i * 2, sample, Endian.little);
  }
  return buffer;
}

void main() {
  group('PcmAudioRecorderService Unit Tests', () {
    test('computeRmsAmplitude is raw, normalised, and gain-calibrated', () {
      // 1. Pure silence
      expect(PcmAudioRecorderService.computeRmsAmplitude(Uint8List(3200)), 0.0);

      // 2. A 0.4578-amplitude sine is 0.3237 normalised RMS (amplitude/sqrt(2)).
      //    No magic divisor: the value is a measurement, not a display curve.
      final amp = PcmAudioRecorderService.computeRmsAmplitude(sine());
      expect(amp, closeTo(15000 / 32768 / math.sqrt(2), 0.005));
      expect(amp, lessThanOrEqualTo(1.0));

      // 3. A DC-biased buffer measures the same as the clean one.
      final biased = sine();
      final biasedData = ByteData.sublistView(biased);
      for (var i = 0; i < biased.length ~/ 2; i++) {
        biasedData.setInt16(i * 2, biasedData.getInt16(i * 2, Endian.little) + 8000, Endian.little);
      }
      expect(
        PcmAudioRecorderService.computeRmsAmplitude(biased),
        closeTo(amp, 0.01),
      );
    });

    test('mock audio recorder streams frames and metrics with sequence numbers', () async {
      final recorder = PcmAudioRecorderService(isMock: true);
      expect(recorder.isRecording, isFalse);

      final chunks = <Uint8List>[];
      final metrics = <FrameMetrics>[];

      final chunkSub = recorder.audioStream.listen(chunks.add);
      final metricsSub = recorder.frameMetricsStream.listen(metrics.add);

      final started = await recorder.startRecording(sampleRate: 16000, frameMs: 50);
      expect(started, isTrue);
      expect(recorder.isRecording, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(metrics.length, greaterThanOrEqualTo(2));
      expect(chunks.first.length, (16000 * 2 * 50) ~/ 1000); // 1600 bytes for 50ms
      expect(metrics.first.seq, 0);
      expect(metrics.last.seq, metrics.length - 1);
      expect(metrics.last.sampleOffset, metrics.last.seq * 800);
      expect(metrics.last.frameMs, 50);

      // The mock emits a tone, so the measured level is real, not zero.
      expect(metrics.map((m) => m.rms).reduce(math.max), greaterThan(0.05));

      await recorder.stopRecording();
      expect(recorder.isRecording, isFalse);

      await chunkSub.cancel();
      await metricsSub.cancel();
      recorder.dispose();
    });

    test('every captured frame reaches the stream, none are held back', () async {
      final recorder = PcmAudioRecorderService(isMock: true);
      final frames = <Uint8List>[];
      final sub = recorder.audioStream.listen(frames.add);
      await recorder.startRecording(sampleRate: 16000, frameMs: 20);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await recorder.stopRecording();

      // A call streams the microphone continuously; the recorder must not decide
      // which frames are worth sending.
      expect(frames.length, greaterThanOrEqualTo(5));
      expect(frames.every((f) => f.length == 640), isTrue);

      await sub.cancel();
      recorder.dispose();
    });

    test('the mock is never on a headset', () async {
      final recorder = PcmAudioRecorderService(isMock: true);
      expect(await recorder.isHeadsetConnected(), isFalse);
      recorder.dispose();
    });

    test('cancel recording stops streaming cleanly', () async {
      final recorder = PcmAudioRecorderService(isMock: true);
      await recorder.startRecording(sampleRate: 16000, frameMs: 50);
      expect(recorder.isRecording, isTrue);

      await recorder.cancelRecording();
      expect(recorder.isRecording, isFalse);
      recorder.dispose();
    });

    test('createWav generates valid 44-byte RIFF header and payload', () {
      final pcm = Uint8List(3200); // 100ms of audio
      final wav = PcmAudioRecorderService.createWav(pcm, sampleRate: 16000, channels: 1, bitsPerSample: 16);
      expect(wav.length, 3200 + 44);

      // Verify 'RIFF'
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // Verify 'WAVE'
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      // Verify 'fmt '
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      // Verify 'data'
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(4, Endian.little), 3200 + 36);
      expect(bd.getUint16(20, Endian.little), 1); // PCM
      expect(bd.getUint16(22, Endian.little), 1); // Mono
      expect(bd.getUint32(24, Endian.little), 16000); // 16kHz
      expect(bd.getUint32(28, Endian.little), 32000); // Byte rate
      expect(bd.getUint16(32, Endian.little), 2); // Block align
      expect(bd.getUint16(34, Endian.little), 16); // 16-bit
      expect(bd.getUint32(40, Endian.little), 3200); // data size
    });

    test('extractWaveform extracts normalized bars representing acoustic envelope', () {
      // 1600 samples (3200 bytes)
      final buffer = Uint8List(3200);
      final bd = ByteData.sublistView(buffer);
      // Put high amplitude in the first half and silence in the second half
      for (var i = 0; i < 800; i++) {
        bd.setInt16(i * 2, 12000, Endian.little);
      }

      final bars = PcmAudioRecorderService.extractWaveform(buffer, barCount: 16);
      expect(bars.length, 16);
      // First 8 bars should be high amplitude (near 1.0)
      for (var i = 0; i < 8; i++) {
        expect(bars[i], closeTo(1.0, 0.05));
      }
      // Remaining bars should drop down to min baseline (~0.12)
      for (var i = 8; i < 16; i++) {
        expect(bars[i], closeTo(0.12, 0.01));
      }
    });
  });
}
