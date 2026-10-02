import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/audio_processor.dart';

/// 20 ms of 16 kHz mono PCM16 at a given RMS level (normalised, 1.0 == full
/// scale).
Uint8List toneFrame(double rms, {int sampleCount = 320, double dcOffset = 0}) {
  final out = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < sampleCount; i++) {
    // A full-amplitude sine has RMS = amplitude / sqrt(2); `rms` is normalised
    // against full scale.
    final value =
        rms * math.sqrt(2) * math.sin(2 * math.pi * i / 32) * 32768.0;
    data.setInt16(
      i * 2,
      (value + dcOffset).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return out;
}

void main() {
  group('AdaptiveNoiseFloor', () {
    test('settles on the room tone, and a burst of speech barely lifts it', () {
      final floor = AdaptiveNoiseFloor();
      for (var i = 0; i < 400; i++) {
        floor.update(100 / 32768);
      }
      expect(floor.floorRms, closeTo(100 / 32768, 0.0005));
      expect(floor.snrDb(100 / 32768), lessThan(3));

      // Three seconds of loud speech must not move the estimate much.
      for (var i = 0; i < 150; i++) {
        floor.update(3000 / 32768);
      }
      expect(floor.floorRms, lessThan(400 / 32768));
      expect(floor.snrDb(3000 / 32768), greaterThan(15));

      // And it finds its way back to the room.
      for (var i = 0; i < 300; i++) {
        floor.update(100 / 32768);
      }
      expect(floor.floorRms, closeTo(100 / 32768, 0.001));
    });

    test('a noisy room that starts above the seed is tracked, not latched', () {
      // The failure that broke the old gate: room noise a few dB above the seed
      // floor was read as speech forever and the floor never rose to meet it.
      final floor = AdaptiveNoiseFloor();
      for (var i = 0; i < 4000; i++) {
        floor.update(300 / 32768);
      }
      expect(floor.floorRms, closeTo(300 / 32768, 0.002));
      expect(floor.snrDb(300 / 32768), lessThan(2));
    });

    test('a 17 dB mic-gain spread does not move the room-relative level', () {
      final quiet = AdaptiveNoiseFloor();
      final hot = AdaptiveNoiseFloor();
      for (var i = 0; i < 6000; i++) {
        quiet.update(300 / 32768);
        hot.update(3000 / 32768);
      }
      expect(
        (quiet.snrDb(3000 / 32768) - hot.snrDb(30000 / 32768)).abs(),
        lessThan(0.5),
      );
    });
  });

  group('AudioProcessor', () {
    test('measures every frame once and reports level and room-relative level', () {
      final processor = AudioProcessor();
      late FrameMetrics last;
      for (var i = 0; i < 60; i++) {
        last = processor.step(
          frame: toneFrame(0.003),
          seq: i,
          sampleOffset: i * 320,
          frameMs: 20,
        );
      }
      expect(last.seq, 59);
      expect(last.sampleOffset, 59 * 320);
      expect(last.rms, closeTo(0.003, 0.0005));
      expect(processor.floorRms, lessThan(0.01));

      final loud = processor.step(
        frame: toneFrame(0.2),
        seq: 60,
        sampleOffset: 60 * 320,
        frameMs: 20,
      );
      expect(loud.snrDb, greaterThan(15));
    });
  });

  group('frame measurement', () {
    test('DC offset is removed before squaring', () {
      final clean = toneFrame(0.1);
      final biased = toneFrame(0.1, dcOffset: 9000);
      expect(
        AudioProcessor.computeRms(biased),
        closeTo(AudioProcessor.computeRms(clean), 0.01),
      );
    });

    test('a single transient cannot dominate a quiet frame', () {
      final room = toneFrame(0.002);
      final data = ByteData.sublistView(room);
      for (var i = 0; i < 2; i++) {
        data.setInt16(i * 2, 32000, Endian.little); // door slam
      }
      final roomOnly = AudioProcessor.computeRms(toneFrame(0.002));
      // Two samples at full scale in a 320-sample frame would be 12x the room
      // tone if measured raw; transient rejection must keep them near it.
      expect(AudioProcessor.computeRms(room), lessThan(roomOnly * 1.5));
      expect(
        AudioProcessor.computeRms(room, floorRms: 0.002),
        lessThan(roomOnly * 1.5),
      );
    });

    test('a floor-relative cap never clips real speech', () {
      final speech = toneFrame(0.2);
      final withCap = AudioProcessor.computeRms(speech, floorRms: 0.003);
      expect(withCap, closeTo(AudioProcessor.computeRms(speech), 0.01));
    });
  });
}
