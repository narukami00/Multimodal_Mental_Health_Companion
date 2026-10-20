import 'dart:math' as math;
import 'dart:typed_data';

/// Full-scale magnitude of a 16-bit sample. Every RMS in this file is
/// normalised against it, so no threshold anywhere is a raw integer count.
const double _fullScale = 32768.0;

/// One measured capture frame.
class FrameMetrics {
  const FrameMetrics({
    required this.seq,
    required this.sampleOffset,
    required this.frameMs,
    required this.rms,
    required this.snrDb,
  });

  /// Monotonic frame counter assigned by the capture path.
  final int seq;

  /// Samples since recording started (`seq * samplesPerFrame`).
  final int sampleOffset;

  final int frameMs;

  /// Frame RMS normalised to full scale: 1.0 == 32767.
  final double rms;

  /// dB above the tracked room-noise level.
  final double snrDb;
}

/// Tracks the room's noise level so the orb can ignore it.
///
/// **Display only.** Deciding when a person is speaking is the server's job: its
/// neural VAD hears speech at signal-to-noise ratios a volume threshold cannot,
/// and the phone no longer gates anything on this number. An earlier version fed
/// a gate with it, and a floor that could not climb above a noisy room left the
/// gate open for the whole call.
///
/// A minimum follower: it drops to quiet moments quickly and creeps upward
/// slowly, so it settles on the room's lower envelope and a few seconds of
/// speech barely lift it.
class AdaptiveNoiseFloor {
  AdaptiveNoiseFloor({double seedRms = 120 / _fullScale})
      : _seedRms = seedRms,
        _floor = seedRms;

  /// Per-frame smoothing toward a quieter frame (fast) or a louder one (slow).
  static const double alphaDown = 0.2;
  static const double alphaUp = 0.0006;

  static const double floorMinRms = 20 / _fullScale;
  static const double floorMaxRms = 6000 / _fullScale;

  final double _seedRms;
  double _floor;

  double get floorRms => _floor;

  void update(double rms) {
    final alpha = rms < _floor ? alphaDown : alphaUp;
    _floor = (_floor + alpha * (rms - _floor)).clamp(floorMinRms, floorMaxRms);
  }

  /// `20 * log10(max(rms, 1 LSB) / max(floor, 1 LSB))` - room-relative, so mic
  /// gain cancels out.
  double snrDb(double rms) {
    const lsb = 1 / _fullScale;
    return 20 * (math.log(math.max(rms, lsb) / math.max(_floor, lsb)) / math.ln10);
  }

  void reset() => _floor = _seedRms;
}

/// Measures capture frames for the orb: level and room-relative level.
///
/// Owned by `PcmAudioRecorderService`. A monotonic clock lives here so nothing
/// reads `DateTime.now()`; [clockMs] replaces it for tests that pump fake time.
class AudioProcessor {
  AudioProcessor({AdaptiveNoiseFloor? noiseFloor, int Function()? clockMs})
      : noiseFloor = noiseFloor ?? AdaptiveNoiseFloor(),
        _clockMs = clockMs;

  final AdaptiveNoiseFloor noiseFloor;
  final Stopwatch _clock = Stopwatch()..start();
  final int Function()? _clockMs;

  int get nowMs => _clockMs?.call() ?? _clock.elapsedMilliseconds;
  double get floorRms => noiseFloor.floorRms;

  FrameMetrics step({
    required Uint8List frame,
    required int seq,
    required int sampleOffset,
    required int frameMs,
  }) {
    final rms = computeRms(frame, floorRms: noiseFloor.floorRms);
    noiseFloor.update(rms);
    return FrameMetrics(
      seq: seq,
      sampleOffset: sampleOffset,
      frameMs: frameMs,
      rms: rms,
      snrDb: noiseFloor.snrDb(rms),
    );
  }

  void reset() => noiseFloor.reset();

  /// Frame RMS normalised to full scale, with the frame's DC offset removed and
  /// transient rejection so one loud sample cannot dominate a 20 ms frame.
  /// `computeRmsAmplitude` keeps the historical name/signature.
  ///
  /// The rejection limit is the larger of eight times the frame's median
  /// absolute sample (a robust within-frame reference: a sine's median sits far
  /// below its peak, so speech is never clipped) and four times the tracked
  /// noise floor. A door slam is two samples orders of magnitude above both, so
  /// it is clamped back to the level of the frame it landed in.
  static double computeRmsAmplitude(Uint8List bytes) => computeRms(bytes);

  static double computeRms(Uint8List bytes, {double? floorRms}) {
    final sampleCount = bytes.length ~/ 2;
    if (sampleCount <= 0) return 0.0;

    final samples = List<double>.filled(sampleCount, 0);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = _sampleAt(bytes, i);
    }

    // DC offset is the median, not the mean: a door slam would otherwise drag
    // the mean with it and leave a phantom bias across the rest of the frame.
    final byValue = List<double>.from(samples)..sort();
    final dc = byValue[sampleCount ~/ 2];

    final magnitudes = List<double>.filled(sampleCount, 0);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] -= dc;
      magnitudes[i] = samples[i].abs();
    }
    magnitudes.sort();
    final median = magnitudes[sampleCount ~/ 2];

    var cap = median * 8.0;
    if (floorRms != null) {
      final floorCap = floorRms * 4 * _fullScale;
      if (floorCap > cap) cap = floorCap;
    }

    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      var s = samples[i];
      if (s > cap) s = cap;
      if (s < -cap) s = -cap;
      sumSquares += s * s;
    }
    return (math.sqrt(sumSquares / sampleCount) / _fullScale).clamp(0.0, 1.0);
  }

  static double _sampleAt(Uint8List bytes, int index) {
    final lo = bytes[index * 2];
    final hi = bytes[index * 2 + 1];
    var sample = lo | (hi << 8);
    if (sample >= 32768) sample -= 65536;
    return sample.toDouble();
  }
}
