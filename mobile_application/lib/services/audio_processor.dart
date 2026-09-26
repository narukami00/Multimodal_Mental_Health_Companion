import 'dart:math' as math;
import 'dart:typed_data';

/// Full-scale magnitude of a 16-bit sample. Every RMS in this file is
/// normalised against it, so no threshold anywhere is a raw integer count.
const double _fullScale = 32768.0;

/// One measured capture frame. Every duration downstream is derived from
/// [sampleOffset] (or ms counters), never from `DateTime.now()`.
class FrameMetrics {
  const FrameMetrics({
    required this.seq,
    required this.sampleOffset,
    required this.frameMs,
    required this.rms,
    required this.snrDb,
    required this.isSpeech,
  });

  /// Monotonic frame counter assigned by the capture path.
  final int seq;

  /// Samples since recording started (`seq * samplesPerFrame`).
  final int sampleOffset;

  final int frameMs;

  /// Frame RMS normalised to full scale: 1.0 == 32767. Raw measurement, never
  /// a display value and never divided by a magic constant.
  final double rms;

  /// dB above the tracked noise floor. This is what every threshold uses.
  final double snrDb;

  /// True once the SNR gate has confirmed speech (onset run or beyond).
  final bool isSpeech;
}

/// Layer 1 — adaptive noise-floor estimator (spec §5.3).
///
/// Invariant: every downstream threshold is expressed in dB relative to
/// [floorRms], so turn-taking behaviour is invariant to mic gain. The floor is
/// updated **only** from frames that are unambiguously non-speech, so the
/// hysteresis band is never learned as noise.
class AdaptiveNoiseFloor {
  AdaptiveNoiseFloor({double seedRms = 120 / _fullScale}) : _seedRms = seedRms, _floor = seedRms;

  /// Asymmetric: a door slam (fast up) is tracked, a lull (slow down) is not
  /// mistaken for a permanently louder room.
  static const double alphaUp = 0.40; // ~4 frames to track +6 dB
  static const double alphaDown = 0.985; // ~67 frames to track -6 dB

  /// Ambiguity band, mirroring the gate's own band. Only frames below
  /// [negThreshold] may update the estimate.
  static const double threshold = 0.50;
  static const double negThreshold = 0.35;

  /// Clamp bounds, expressed in normalised RMS. These are the spec's raw
  /// constants (20 ≈ -49 dBFS digital silence, 6000 ≈ 0 dBFS clipping guard)
  /// divided by full scale.
  static const double floorMinRms = 20 / _fullScale;
  static const double floorMaxRms = 6000 / _fullScale;

  /// Window used for [driftDb]: floor now vs. floor 30 s ago (spec §10.3).
  static const int driftWindowSec = 30;

  final double _seedRms;
  double _floor;
  final List<double> _floorHistory = <double>[];
  int _lastHistoryMs = -1;

  double get floorRms => _floor;

  /// Change in floor over [driftWindowSec]. A monotonic rise is a real bug and
  /// must be visible on the diagnostic stream.
  double get driftDb {
    if (_floorHistory.length < 2) return 0.0;
    final oldest = _floorHistory.first;
    if (oldest <= 0) return 0.0;
    return 20 * (math.log(_floor / oldest) / math.ln10);
  }

  /// [speechProb] is the local speech probability; the floor moves only below
  /// [negThreshold].
  ///
  /// ponytail: no minimum-statistics window over the raw frames. The
  /// negThreshold rule already prevents a monologue from inflating the
  /// estimate; add a windowed minimum if floor_drift_db is ever non-zero.
  void update({required double rms, required double speechProb, int nowMs = 0}) {
    if (speechProb < negThreshold) {
      final alpha = rms > _floor ? alphaUp : alphaDown;
      _floor += alpha * (rms - _floor);
      _floor = _floor.clamp(floorMinRms, floorMaxRms);
      _noteHistory(nowMs);
    }
  }

  /// `20 * log10(max(rms, 1 LSB) / max(floor, 1 LSB))` — room-relative by
  /// construction, so mic gain cancels out.
  double snrDb(double rms) {
    const lsb = 1 / _fullScale;
    return 20 * (math.log(math.max(rms, lsb) / math.max(_floor, lsb)) / math.ln10);
  }

  void reset() {
    _floor = _seedRms;
    _floorHistory.clear();
    _lastHistoryMs = -1;
  }

  void _noteHistory(int nowMs) {
    if (nowMs <= 0) return;
    if (_lastHistoryMs < 0 || nowMs - _lastHistoryMs >= 1000) {
      _lastHistoryMs = nowMs;
      _floorHistory.add(_floor);
      final maxSamples = driftWindowSec;
      if (_floorHistory.length > maxSamples) _floorHistory.removeAt(0);
    }
  }
}

/// Layer 2 — echo suppression as a VAD *input* filter (spec §5.4).
///
/// ponytail: the envelope-coherence rule (normalised cross-correlation against
/// the playback envelope) is deliberately omitted. Persistence + grace +
/// cooldown cover the measured 503–757 ms echo onset; add coherence only if
/// `echo_suppression_activations` fails to converge.
class EchoSuppressionFilter {
  EchoSuppressionFilter({
    this.persistMs = 300,
    this.graceMs = 700,
    this.cooldownMs = 1500,
    this.cooldownMarginDb = 3.0,
  });

  /// Speech must outlive our own audio by this long before it is an interrupt.
  final int persistMs;

  /// Do not accept a barge-in this soon after the assistant started talking.
  final int graceMs;

  /// Room-decay tail after playback stops; a stricter threshold applies.
  final int cooldownMs;
  final double cooldownMarginDb;

  bool _playbackActive = false;
  int _playbackStartedAtMs = -1;
  int _playbackEndedAtMs = -1;
  int _playbackLevelRms = 0;
  int _suppressionCount = 0;

  bool get playbackActive => _playbackActive;
  int get playbackLevelRms => _playbackLevelRms;
  int get suppressionCount => _suppressionCount;

  void onPlaybackChanged({
    required bool active,
    required int levelRms,
    required int nowMs,
  }) {
    _playbackLevelRms = levelRms;
    if (active == _playbackActive) return;
    _playbackActive = active;
    if (active) {
      _playbackStartedAtMs = nowMs;
    } else {
      _playbackEndedAtMs = nowMs;
    }
  }

  /// True if this frame may drive an onset: it is loud enough to be a candidate
  /// *and* it does not look like our own playback. A rejected candidate is
  /// counted for the §10 `echo_suppression_activations` metric.
  bool admitsOnset({
    required double snrDb,
    required double onDb,
    required int nowMs,
  }) {
    if (snrDb < onDb) return false; // not an onset candidate at all

    final inGrace = _playbackStartedAtMs >= 0 &&
        nowMs - _playbackStartedAtMs < graceMs;
    if (_playbackActive || inGrace) return _suppress();

    if (_playbackEndedAtMs >= 0) {
      final sinceEnd = nowMs - _playbackEndedAtMs;
      // Persistence: echo dies with the speaker, a real interrupter does not.
      if (sinceEnd < persistMs) return _suppress();
      // Room decay after playback stops lasts 1-2 s and is the other measured
      // false-trigger source; demand 3 dB more than usual until it settles.
      if (sinceEnd < cooldownMs && snrDb < onDb + cooldownMarginDb) {
        return _suppress();
      }
    }
    return true;
  }

  bool _suppress() {
    _suppressionCount++;
    return false;
  }

  void reset() {
    _playbackActive = false;
    _playbackStartedAtMs = -1;
    _playbackEndedAtMs = -1;
    _suppressionCount = 0;
  }
}

/// Outcome of one [SnrGate] step. `onsetRun` means a candidate is building but
/// is not yet confirmed; `speech` is confirmed speech; `hangover` is the
/// release hold after speech stopped.
enum GateState { idle, onsetRun, speech, hangover }

/// Layer 3 — SNR gate with a hysteresis band and hangover (spec §5.5).
///
/// Replaces the single absolute amplitude threshold and the frame-counter pair
/// that used to live in `call_page.dart`. Frames inside the band
/// `[offDb, onDb)` are *ambiguous*: they neither confirm nor deny an onset, so
/// a plosive no longer destroys the onset run.
class SnrGate {
  SnrGate({
    this.onDbSilent = 9.0,
    this.onDbSpeaking = 14.0,
    this.offDb = 5.0,
    this.onsetConfirmMs = 60,
    this.minSpeechMs = 120,
    this.hangoverMs = 240,
    this.endpointSilenceMs = 700,
    this.endpointMinMs = 500,
    this.endpointMaxMs = 1500,
    this.endpointEmaAlpha = 0.9,
    this.maxTurnMs = 30000,
  });

  /// Assistant silent: a normal conversational onset.
  final double onDbSilent;

  /// Assistant audible: strictly higher, because our own output is the largest
  /// source of false triggers.
  final double onDbSpeaking;

  /// Exit threshold. The band between on and off IS the hysteresis.
  final double offDb;

  final int onsetConfirmMs; // 3 x 20 ms frames
  final int minSpeechMs; // below this it is a cough or a knock
  final int hangoverMs; // release hold, bridges plosives
  final int endpointSilenceMs; // seed for the adaptive deadline
  final int endpointMinMs;
  final int endpointMaxMs;
  final double endpointEmaAlpha;

  /// No detector may block a turn indefinitely (spec §5.1.5).
  final int maxTurnMs;

  static const double _dbFloor = -120.0;

  int onsetRunMs = 0;
  int speechMs = 0;
  int hangoverRunMs = 0;
  int silenceMs = 0;
  int lastSpeechMs = -1;
  int turnStartedMs = -1;

  double _emittedGapMs = 0;
  bool _emittedGapSeeded = false;

  GateState _state = GateState.idle;

  GateState get state => _state;
  bool get onsetConfirmed => onsetRunMs >= onsetConfirmMs;
  bool get speechConfirmed => speechMs >= minSpeechMs;

  /// Adaptive turn-end deadline measured from the last speech sample (spec
  /// §5.7): 1.25x the EMA of the gaps that actually preceded accepted ends.
  int get effectiveEndpointMs {
    if (!_emittedGapSeeded) {
      return endpointSilenceMs.clamp(endpointMinMs, endpointMaxMs);
    }
    return (_emittedGapMs * 1.25).round().clamp(endpointMinMs, endpointMaxMs);
  }

  /// [onDb] is chosen by the caller from real playback state, never from
  /// network arrival.
  GateState step({
    required double snrDb,
    required int frameMs,
    required double onDb,
    required int nowMs,
  }) {
    final value = snrDb.clamp(_dbFloor, 120.0);

    if (value >= onDb) {
      onsetRunMs += frameMs;
    } else if (value < offDb) {
      // Only the lower threshold resets the onset run.
      onsetRunMs = 0;
    }

    if (value >= offDb) {
      speechMs += frameMs;
      hangoverRunMs = 0;
      silenceMs = 0;
      lastSpeechMs = nowMs;
    } else {
      hangoverRunMs += frameMs;
      silenceMs += frameMs;
    }

    if (turnStartedMs < 0 && onsetRunMs > 0) turnStartedMs = nowMs;

    _state = switch (_state) {
      GateState.idle ||
      GateState.onsetRun =>
        onsetConfirmed ? GateState.speech : (onsetRunMs > 0 ? GateState.onsetRun : GateState.idle),
      GateState.speech =>
        silenceMs >= hangoverMs ? GateState.hangover : GateState.speech,
      GateState.hangover =>
        value >= offDb ? GateState.speech : GateState.hangover,
    };
    if (_state == GateState.speech && !speechConfirmed) _state = GateState.onsetRun;
    return _state;
  }

  /// True when the turn should be closed: the adaptive silence deadline, the
  /// hard cap, or the end of speech after the hangover hold.
  bool shouldEndTurn({required int nowMs}) {
    if (turnStartedMs < 0) return false;
    if (nowMs - turnStartedMs >= maxTurnMs) return true;
    if (!speechConfirmed) return false;
    return silenceMs >= effectiveEndpointMs;
  }

  /// Feed the observed silence gap that preceded an accepted turn end so the
  /// deadline adapts to this speaker's pause distribution.
  void noteAcceptedGap(int observedGapMs) {
    if (observedGapMs <= 0) return;
    if (!_emittedGapSeeded) {
      _emittedGapMs = observedGapMs.toDouble();
      _emittedGapSeeded = true;
      return;
    }
    _emittedGapMs =
        endpointEmaAlpha * _emittedGapMs + (1 - endpointEmaAlpha) * observedGapMs;
  }

  void reset() {
    onsetRunMs = 0;
    speechMs = 0;
    hangoverRunMs = 0;
    silenceMs = 0;
    lastSpeechMs = -1;
    turnStartedMs = -1;
    _state = GateState.idle;
  }
}

/// Layer 4 — pre-roll ring buffer (spec §5.6). Written on **every** frame,
/// unconditionally, before any gating. On turn start its contents are prepended
/// to the transmitted stream so the ~60–200 ms of audio that triggered the
/// onset is not lost.
class PreRollRingBuffer {
  PreRollRingBuffer({this.capacityMs = 600, this.frameMs = 20});

  final int capacityMs;
  final int frameMs;

  // ponytail: a 30-element deque, not a hand-rolled ring. Identical behaviour,
  // and `drain` stays obviously correct. Cost is 30 pointers of memmove.
  final List<Uint8List> _frames = <Uint8List>[];
  int _lastSeq = -1;

  int get capacityFrames => (capacityMs / frameMs).ceil();
  int get length => _frames.length;
  bool get isEmpty => _frames.isEmpty;
  int get lastSeq => _lastSeq;
  int get totalBytes => _frames.fold<int>(0, (sum, f) => sum + f.length);

  void push(Uint8List frame, int seq) {
    if (_frames.length >= capacityFrames) {
      _frames.removeAt(0);
    }
    _frames.add(frame);
    _lastSeq = seq;
  }

  /// Oldest-first frames covering the last [backMs], capped at capacity.
  List<Uint8List> drain(int backMs) {
    if (_frames.isEmpty) return const <Uint8List>[];
    final want = math.max(1, (backMs / frameMs).ceil());
    final take = math.min(want, _frames.length);
    final start = _frames.length - take;
    final out = _frames.sublist(start);
    _frames.removeRange(start, _frames.length);
    return out;
  }

  void clear() {
    _frames.clear();
    _lastSeq = -1;
  }
}

/// The four layers composed into the single capture-side pipeline. Owned by
/// `PcmAudioRecorderService`; `call_page.dart` only reads metrics and drains
/// the pre-roll, so there is exactly one gate and one noise floor per call.
class AudioProcessor {
  AudioProcessor({
    AdaptiveNoiseFloor? noiseFloor,
    EchoSuppressionFilter? echo,
    SnrGate? gate,
    PreRollRingBuffer? preRoll,
    int Function()? clockMs,
  })  : noiseFloor = noiseFloor ?? AdaptiveNoiseFloor(),
        echo = echo ?? EchoSuppressionFilter(),
        gate = gate ?? SnrGate(),
        preRoll = preRoll ?? PreRollRingBuffer(),
        _clockMs = clockMs;

  final AdaptiveNoiseFloor noiseFloor;
  final EchoSuppressionFilter echo;
  final SnrGate gate;
  final PreRollRingBuffer preRoll;

  /// Monotonic capture clock in ms. Every time-based rule reads this, never
  /// `DateTime.now()`. [clockMs] replaces it: a pumped widget test advances
  /// fake time, which wall time does not see.
  final Stopwatch _clock = Stopwatch()..start();
  final int Function()? _clockMs;

  int get nowMs => _clockMs?.call() ?? _clock.elapsedMilliseconds;
  double get floorRms => noiseFloor.floorRms;
  double get floorDriftDb => noiseFloor.driftDb;
  int get echoSuppressions => echo.suppressionCount;
  bool get playbackActive => echo.playbackActive;

  /// Feed one frame. [assistantSpeaking] must come from real playback state.
  FrameMetrics step({
    required Uint8List frame,
    required int seq,
    required int sampleOffset,
    required int frameMs,
    required bool assistantSpeaking,
  }) {
    final now = nowMs;
    final rms = computeRms(frame, floorRms: noiseFloor.floorRms);

    // Order-independent: classify against the current floor, then let the
    // floor learn from that classification, then re-measure.
    final provisional = noiseFloor.snrDb(rms);
    noiseFloor.update(
      rms: rms,
      speechProb: provisional >= gate.offDb ? 1.0 : 0.0,
      nowMs: now,
    );
    final snrDb = noiseFloor.snrDb(rms);

    preRoll.push(frame, seq);

    final onDb = assistantSpeaking ? gate.onDbSpeaking : gate.onDbSilent;
    final admitted = echo.admitsOnset(snrDb: snrDb, onDb: onDb, nowMs: now);
    final state = gate.step(
      snrDb: admitted ? snrDb : -120.0,
      frameMs: frameMs,
      onDb: onDb,
      nowMs: now,
    );

    return FrameMetrics(
      seq: seq,
      sampleOffset: sampleOffset,
      frameMs: frameMs,
      rms: rms,
      snrDb: snrDb,
      // `hangover` is the release hold: the utterance has ended as far as a
      // listener is concerned, and it never returns to idle on its own, so
      // counting it as speech would latch the caller's silence timer open
      // forever (the endpoint would never fire).
      isSpeech: state == GateState.speech || state == GateState.onsetRun,
    );
  }

  void onPlaybackChanged({required bool active, required int levelRms}) {
    echo.onPlaybackChanged(
      active: active,
      levelRms: levelRms,
      nowMs: nowMs,
    );
  }

  List<Uint8List> drainPreRoll(int backMs) => preRoll.drain(backMs);

  void reset() {
    gate.reset();
    preRoll.clear();
  }

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
