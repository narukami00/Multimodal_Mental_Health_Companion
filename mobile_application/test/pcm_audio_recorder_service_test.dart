import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';

void main() {
  group('PcmAudioRecorderService Unit Tests', () {
    test('computeRmsAmplitude handles silence and signals accurately', () {
      // 1. Pure silence
      final silence = Uint8List(3200);
      expect(PcmAudioRecorderService.computeRmsAmplitude(silence), 0.0);

      // 2. High amplitude sine wave
      final sampleRate = 16000;
      final numSamples = 1600; // 100ms
      final buffer = Uint8List(numSamples * 2);
      final byteData = ByteData.sublistView(buffer);
      for (var i = 0; i < numSamples; i++) {
        final sample = (15000.0 * math.sin(2 * math.pi * 440 * i / sampleRate)).toInt();
        byteData.setInt16(i * 2, sample, Endian.little);
      }
      final amp = PcmAudioRecorderService.computeRmsAmplitude(buffer);
      expect(amp, greaterThan(0.5));
      expect(amp, lessThanOrEqualTo(1.0));
    });

    test('mock audio recorder streams frames and amplitude', () async {
      final recorder = PcmAudioRecorderService(isMock: true);
      expect(recorder.isRecording, isFalse);

      final chunks = <Uint8List>[];
      final amplitudes = <double>[];

      final chunkSub = recorder.audioStream.listen(chunks.add);
      final ampSub = recorder.amplitudeStream.listen(amplitudes.add);

      final started = await recorder.startRecording(sampleRate: 16000, frameMs: 50);
      expect(started, isTrue);
      expect(recorder.isRecording, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(amplitudes.length, greaterThanOrEqualTo(2));
      expect(chunks.first.length, (16000 * 2 * 50) ~/ 1000); // 1600 bytes for 50ms

      await recorder.stopRecording();
      expect(recorder.isRecording, isFalse);

      await chunkSub.cancel();
      await ampSub.cancel();
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
