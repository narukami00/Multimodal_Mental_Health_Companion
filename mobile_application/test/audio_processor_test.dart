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
    // Ramp so the frame RMS lands on `rms` (a full-amplitude sine has
    // RMS = amplitude / sqrt(2)). `rms` is normalised against full scale.
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
    test('tracks room tone, holds through speech, and stays gain-invariant', () {
      final floor = AdaptiveNoiseFloor();

      for (var i = 0; i < 200; i++) {
        floor.update(rms: 100 / 32768, speechProb: 0.0, nowMs: i * 20);
      }
      expect(floor.floorRms, closeTo(100 / 32768, 0.002));
      expect(floor.snrDb(100 / 32768), lessThan(3));

      // 800 ms of loud speech must not move the estimate.
      for (var i = 0; i < 40; i++) {
        floor.update(rms: 3000 / 32768, speechProb: 1.0, nowMs: 4000 + i * 20);
      }
      expect(floor.floorRms, lessThan(200 / 32768));
      expect(floor.snrDb(3000 / 32768), greaterThan(15));
      expect(floor.snrDb(100 / 32768), lessThan(3));

      // Back to room tone: converges again.
      for (var i = 0; i < 300; i++) {
        floor.update(rms: 100 / 32768, speechProb: 0.0, nowMs: 5000 + i * 20);
      }
      expect(floor.floorRms, closeTo(100 / 32768, 0.0005));
    });

    test('a 17 dB mic-gain spread does not move the SNR decision', () {
      // The whole point of the floor: the same room measured by a quiet mic and
      // a hot mic must produce the same dB.
      final quiet = AdaptiveNoiseFloor();
      final hot = AdaptiveNoiseFloor();
      for (var i = 0; i < 200; i++) {
        quiet.update(rms: 300 / 32768, speechProb: 0.0, nowMs: i * 20);
        hot.update(rms: 3000 / 32768, speechProb: 0.0, nowMs: i * 20);
      }
      expect(
        (quiet.snrDb(3000 / 32768) - hot.snrDb(30000 / 32768)).abs(),
        lessThan(0.5),
      );
    });

    test('ambiguous frames in the band never update the floor', () {
      final floor = AdaptiveNoiseFloor();
      final seed = floor.floorRms;
      for (var i = 0; i < 100; i++) {
        floor.update(rms: 0.15, speechProb: 0.4, nowMs: i * 20);
      }
      expect(floor.floorRms, seed);
    });

    test('driftDb reports a floor that keeps climbing', () {
      final floor = AdaptiveNoiseFloor();
      for (var sec = 0; sec < 40; sec++) {
        // A room that gets louder: +8 RMS per second.
        floor.update(
          rms: (100 + 8 * sec) / 32768,
          speechProb: 0.0,
          nowMs: sec * 1000,
        );
      }
      expect(floor.driftDb, greaterThan(3));
    });
  });

  group('SnrGate', () {
    test('confirms an onset through a plosive gap left inside the band', () {
      final gate = SnrGate();
      var now = 0;
      // A plosive / stop closure dips the frame below the on-threshold but not
      // below off-threshold. Those frames must neither confirm nor deny.
      for (var i = 0; i < 8; i++) {
        final db = i.isEven ? 12.0 : 6.0;
        gate.step(snrDb: db, frameMs: 20, onDb: 9, nowMs: now);
        now += 20;
      }
      expect(gate.onsetRunMs, greaterThanOrEqualTo(gate.onsetConfirmMs));
      expect(gate.onsetConfirmed, isTrue);
    });

    test('a single frame below offDb resets the onset run', () {
      final gate = SnrGate();
      gate.step(snrDb: 12, frameMs: 20, onDb: 9, nowMs: 0);
      gate.step(snrDb: 12, frameMs: 20, onDb: 9, nowMs: 20);
      expect(gate.onsetRunMs, 40);
      gate.step(snrDb: 2, frameMs: 20, onDb: 9, nowMs: 40);
      expect(gate.onsetRunMs, 0);
      expect(gate.onsetConfirmed, isFalse);
    });

    test('hangover holds speech through inter-syllable gaps, then ends', () {
      final gate = SnrGate();
      var now = 0;
      for (var i = 0; i < 10; i++) {
        gate.step(snrDb: 12, frameMs: 20, onDb: 9, nowMs: now);
        now += 20;
      }
      expect(gate.speechConfirmed, isTrue);
      for (var i = 0; i < 6; i++) {
        // 120 ms below off: inside the 240 ms hangover, so still one turn.
        gate.step(snrDb: 1, frameMs: 20, onDb: 9, nowMs: now);
        now += 20;
      }
      expect(gate.speechConfirmed, isTrue);
      expect(gate.shouldEndTurn(nowMs: now), isFalse);
      for (var i = 0; i < 40; i++) {
        gate.step(snrDb: 1, frameMs: 20, onDb: 9, nowMs: now);
        now += 20;
      }
      expect(gate.shouldEndTurn(nowMs: now), isTrue);
    });

    test('the ceiling releases a turn no matter what', () {
      final gate = SnrGate();
      var now = 0;
      gate.step(snrDb: 12, frameMs: 20, onDb: 9, nowMs: now);
      expect(gate.shouldEndTurn(nowMs: 40000), isTrue);
    });

    test('endpoint deadline adapts toward the speaker pause distribution', () {
      final gate = SnrGate();
      expect(gate.effectiveEndpointMs, 700);
      for (var i = 0; i < 10; i++) {
        gate.noteAcceptedGap(1000);
      }
      expect(gate.effectiveEndpointMs, 1250);
      for (var i = 0; i < 20; i++) {
        gate.noteAcceptedGap(300);
      }
      expect(gate.effectiveEndpointMs, 500); // clamped at the floor
    });
  });

  group('EchoSuppressionFilter', () {
    test('rejects onsets during playback and inside the grace window', () {
      final echo = EchoSuppressionFilter();
      echo.onPlaybackChanged(active: true, levelRms: 4000, nowMs: 0);
      expect(echo.admitsOnset(snrDb: 20, onDb: 14, nowMs: 100), isFalse);
      expect(echo.suppressionCount, 1);

      echo.onPlaybackChanged(active: false, levelRms: 0, nowMs: 500);
      // Grace window is 700 ms from TTS start, so 500 ms in it is still refused.
      expect(echo.admitsOnset(snrDb: 20, onDb: 14, nowMs: 600), isFalse);
      // Past grace, past persistence (300 ms after playback ended).
      expect(echo.admitsOnset(snrDb: 20, onDb: 14, nowMs: 1000), isTrue);
    });

    test('persistence and cooldown gate a genuine interruption after playback', () {
      final echo = EchoSuppressionFilter();
      echo.onPlaybackChanged(active: true, levelRms: 4000, nowMs: 0);
      echo.onPlaybackChanged(active: false, levelRms: 0, nowMs: 2000);

      // Inside persistence (300 ms): the room-decay tail is refused.
      expect(echo.admitsOnset(snrDb: 22, onDb: 14, nowMs: 2100), isFalse);
      // Past persistence, inside cooldown (1500 ms): 14 dB is no longer enough.
      expect(echo.admitsOnset(snrDb: 14, onDb: 14, nowMs: 2400), isFalse);
      expect(echo.admitsOnset(snrDb: 18, onDb: 14, nowMs: 2400), isTrue);
      // Past cooldown: an ordinary onset is admitted.
      expect(echo.admitsOnset(snrDb: 16, onDb: 14, nowMs: 4000), isTrue);
    });

    test('quiet frames are never counted as suppressions', () {
      final echo = EchoSuppressionFilter();
      echo.onPlaybackChanged(active: true, levelRms: 4000, nowMs: 0);
      for (var i = 0; i < 50; i++) {
        expect(echo.admitsOnset(snrDb: 2, onDb: 14, nowMs: i * 20), isFalse);
      }
      expect(echo.suppressionCount, 0);
    });
  });

  group('PreRollRingBuffer', () {
    test('keeps the last 600 ms and drains the requested window', () {
      final buffer = PreRollRingBuffer();
      for (var i = 0; i < 100; i++) {
        buffer.push(Uint8List(640)..[0] = i, i);
      }
      expect(buffer.length, 30); // 600 ms / 20 ms
      expect(buffer.lastSeq, 99);

      final drained = buffer.drain(60); // last 3 frames
      expect(drained.length, 3);
      expect(drained[0][0], 97);
      expect(drained[2][0], 99);
      expect(buffer.length, 27);

      // The next drain continues where the last one stopped: no gap, no repeat.
      final next = buffer.drain(40);
      expect(next[0][0], 95);
      expect(next[1][0], 96);
    });

    test('drain is capped at capacity and empty is safe', () {
      final buffer = PreRollRingBuffer();
      expect(buffer.drain(5000), isEmpty);
      for (var i = 0; i < 5; i++) {
        buffer.push(Uint8List(640)..[0] = i, i);
      }
      expect(buffer.drain(5000).length, 5);
      expect(buffer.isEmpty, isTrue);
    });
  });

  group('AudioProcessor', () {
    test('end-to-end: silence, speech, silence drives the gate and pre-roll', () {
      final processor = AudioProcessor();
      final metrics = <FrameMetrics>[];

      for (var i = 0; i < 60; i++) {
        metrics.add(processor.step(
          frame: toneFrame(0.003),
          seq: i,
          sampleOffset: i * 320,
          frameMs: 20,
          assistantSpeaking: false,
        ));
      }
      expect(metrics.every((m) => !m.isSpeech), isTrue);
      expect(processor.floorRms, lessThan(0.01));

      for (var i = 60; i < 80; i++) {
        metrics.add(processor.step(
          frame: toneFrame(0.2),
          seq: i,
          sampleOffset: i * 320,
          frameMs: 20,
          assistantSpeaking: false,
        ));
      }
      final peak = metrics.last.snrDb;
      expect(peak, greaterThan(15));
      expect(metrics.last.isSpeech, isTrue);
      expect(processor.gate.speechConfirmed, isTrue);

      final preRoll = processor.drainPreRoll(200);
      expect(preRoll.length, 10);
      expect(preRoll.length * 640, 6400);
    });

    test('own playback is filtered out of the gate input', () {
      final processor = AudioProcessor();
      processor.onPlaybackChanged(active: true, levelRms: 4000);
      for (var i = 0; i < 20; i++) {
        processor.step(
          frame: toneFrame(0.05),
          seq: i,
          sampleOffset: i * 320,
          frameMs: 20,
          assistantSpeaking: true,
        );
      }
      expect(processor.echoSuppressions, greaterThan(0));
      expect(processor.gate.speechMs, 0);
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
