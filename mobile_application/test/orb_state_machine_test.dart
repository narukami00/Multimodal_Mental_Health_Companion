import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/call/call_turn_controller.dart';

/// Simulate [seconds] of animation at 60 Hz.
void run(CallTurnController c, double seconds) {
  const dt = 1 / 60;
  for (var i = 0; i < (seconds * 60).round(); i++) {
    c.tick(dt);
  }
}

void main() {
  group('orb parameter table (spec §8.2)', () {
    test('each state has the documented row', () {
      expect(
        OrbParameters.idle.values,
        [6.4, 0.030, 18.0, 0.04, 0.02, 5.2, 0.20, 0.035, 1.00, 1.00, 0.34, 0.0, 9.0],
      );
      expect(
        OrbParameters.userSpeaking.values,
        [4.2, 0.048, 9.0, 0.10, 0.05, 3.0, 0.32, 0.10, 1.04, 1.00, 0.46, 1.0, 7.0],
      );
      expect(
        OrbParameters.thinking.values,
        [5.0, 0.016, 7.0, 0.55, 0.17, 5.0, 0.0, 0.22, 0.97, 0.92, 0.40, 0.0, 9.0],
      );
      expect(
        OrbParameters.assistantSpeaking.values,
        [3.1, 0.060, 11.0, 0.16, 0.07, 3.2, 0.46, 0.12, 1.06, 1.05, 0.60, 1.0, 9.0],
      );
      expect(
        OrbParameters.muted.values,
        [9.5, 0.008, 30.0, 0.012, 0.006, 7.0, 0.08, 0.008, 0.90, 0.55, 0.16, 0.0, 9.0],
      );
    });

    test('only the two speaking states are coupled to audio', () {
      expect(OrbParameters.idle.ampCoupling, 0.0);
      expect(OrbParameters.thinking.ampCoupling, 0.0);
      expect(OrbParameters.muted.ampCoupling, 0.0);
      expect(OrbParameters.userSpeaking.ampCoupling, 1.0);
      expect(OrbParameters.assistantSpeaking.ampCoupling, 1.0);
    });

    test('THINKING is gyration, not a fast breath', () {
      // The rotation *is* the message: no other state comes close, and the
      // rings vanish entirely so THINK cannot be mistaken for a fast ASSIST.
      final otherRates = [
        OrbParameters.idle.rotRate,
        OrbParameters.userSpeaking.rotRate,
        OrbParameters.assistantSpeaking.rotRate,
        OrbParameters.muted.rotRate,
      ];
      expect(OrbParameters.thinking.rotRate,
          greaterThan(3 * otherRates.reduce(math.max)));
      expect(OrbParameters.thinking.ringMaxOpacity, 0.0);
      expect(OrbParameters.thinking.breathAmp, lessThan(OrbParameters.idle.breathAmp));
    });

    test('IDLE rings are barely perceptible', () {
      expect(OrbParameters.idle.ringMaxOpacity, 0.20);
      expect(OrbParameters.idle.breathPeriodS, 6.4);
      expect(OrbParameters.idle.morphPeriodS, 18.0);
    });
  });

  group('orb at rest', () {
    test('a 10 minute idle session never drifts into motion', () {
      final c = CallTurnController(clock: Stopwatch());
      c.noiseFloorRms = 0.003;
      run(c, 600);

      // Nothing about the resting state is allowed to grow on its own.
      for (var i = 0; i < c.parameters.values.length; i++) {
        expect(
          (c.parameters[i] - OrbParameters.idle[i]).abs(),
          lessThan(1e-6),
          reason: 'parameter $i drifted at idle',
        );
      }
      expect(c.modulation, 0.0);
      // The phase advances monotonically; it never jumps backwards.
      expect(c.animationPhase, greaterThan(0));
      expect(c.rotationRate, closeTo(OrbParameters.idle.rotRate, 1e-6));
      c.dispose();
    });

    test('a level below the display gate produces no motion at all', () {
      final c = CallTurnController(clock: Stopwatch());
      c.noiseFloorRms = 0.01;
      c.rawAmplitude = 0.005; // under floor * 10^(9/20)
      run(c, 2);
      expect(c.modulation, 0.0);
      c.dispose();
    });
  });

  group('orb transitions', () {
    test('the barge-in is the fastest transition in the matrix', () {
      final c = CallTurnController(clock: Stopwatch());
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onProcessing('t', TurnStage.ttsFirstFrame);
      run(c, 3);
      expect(c.currentPhase, CallPhase.assistantSpeaking);

      final before = c.parameters.baseScale;
      final target = OrbParameters.userSpeaking.baseScale;
      c.onInterrupted(turnId: 't2', playedMs: 900);
      run(c, 0.25); // tau is 0.20 s for this pair
      final progress = (before - c.parameters.baseScale) / (before - target);
      // 1 - exp(-0.25 / 0.20) = 0.71. The slowest pair in the matrix (0.50 s)
      // would only be at 0.39 in the same time.
      expect(progress, greaterThan(0.7));
      c.dispose();
    });

    test('the phase-rate filter makes a transition a morph, not a jump', () {
      final c = CallTurnController(clock: Stopwatch());
      run(c, 2);
      final idleRate = c.rotationRate;
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.tick(1 / 60);
      // One frame in, the rate has barely moved even though the target jumped.
      expect(c.rotationRate - idleRate, lessThan(0.05));
      run(c, 3);
      expect(c.rotationRate, greaterThan(idleRate));
      c.dispose();
    });

    test('ASSISTANT_SPEAKING glows and swells with real playback level', () {
      final c = CallTurnController(clock: Stopwatch());
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onProcessing('t', TurnStage.ttsFirstFrame);
      c.noiseFloorRms = 0.003;
      c.rawAmplitude = 0.0;
      run(c, 2);
      final quiet = c.modulation;
      c.rawAmplitude = 0.12;
      run(c, 1);
      expect(c.modulation, greaterThan(quiet));
      expect(c.modulation, lessThanOrEqualTo(1.0));
      c.dispose();
    });

    test('the release is slower than the attack', () {
      final c = CallTurnController(clock: Stopwatch());
      c.onTurnStarted('t');
      c.rawAmplitude = 0.2;
      run(c, 0.5);
      final peak = c.modulation;
      c.rawAmplitude = 0.0;
      run(c, 0.1);
      final quick = c.modulation;
      expect(quick, greaterThan(peak * 0.5)); // 100 ms in, still mostly up
      run(c, 2);
      expect(c.modulation, lessThan(peak * 0.2));
      c.dispose();
    });

    test('mute contracts and desaturates, unmute restores', () {
      final c = CallTurnController(clock: Stopwatch());
      run(c, 1);
      c.onMicMutedChanged(true);
      run(c, 2);
      expect(c.parameters.baseScale, closeTo(OrbParameters.muted.baseScale, 0.01));
      expect(c.parameters.saturation, closeTo(OrbParameters.muted.saturation, 0.01));
      c.onMicMutedChanged(false);
      run(c, 2);
      expect(c.parameters.baseScale, closeTo(OrbParameters.idle.baseScale, 0.01));
      c.dispose();
    });
  });
}
