import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The five conversational states the operator asked for, plus the two
/// lifecycle terminals. The Living Orb is a pure function of this value and of
/// nothing else (spec §7.5).
enum CallPhase { idle, userSpeaking, thinking, assistantSpeaking, muted, ended }

/// `turn.processing` sub-stages. Telemetry, not visuals: a sub-stage change must
/// never move the orb between states (spec §8.4).
enum TurnStage { vad, stt, llmFirstToken, ttsFirstFrame, llmTimeout, tool, complete }

enum DiscardReason { silence, unintelligible, tooShort, noSpeechProb, echo, cancelled }

/// §5.8: barge-in is a classification problem, not a detection problem.
enum BargeInClass { interrupt, backchannel, echo, noise }

/// Every input that can move the machine. The table below is the whole machine.
enum TurnEvent {
  turnStarted,
  speechDetected,
  localOnset,
  endpointed,
  processing,
  firstToken,
  firstAudioFrame,
  ttsComplete,
  interrupted,
  discarded,
  ttsResume,
  cancelled,
  callEnded,
}

/// One row of the §10 metrics. A state machine whose transitions are not logged
/// cannot be tuned.
class CallPhaseTransition {
  const CallPhaseTransition({
    required this.from,
    required this.to,
    required this.event,
    required this.tMs,
  });

  final CallPhase from;
  final CallPhase to;
  final TurnEvent event;
  final int tMs;

  @override
  String toString() => '${from.name}->${to.name} (${event.name} @${tMs}ms)';
}

/// §8.2 parameter vector `A ∈ R^13`, one row per state. Timing values are
/// inherited from `html_ref/call.html` where it had them, so the five-state orb
/// is a restoration rather than a redesign.
///
/// Order: breathPeriod_s, breathAmp, morphPeriod_s, rotRate_radPerS, swirlAmp,
/// ringPeriod_s, ringMaxOpacity, corePulseAmp, baseScale, saturation,
/// glowAlpha, ampCoupling, noiseGateDb.
class OrbParameters {
  const OrbParameters(this.values);

  final List<double> values;

  double operator [](int i) => values[i];

  double get breathPeriodS => values[0];
  double get breathAmp => values[1];
  double get morphPeriodS => values[2];
  double get rotRate => values[3];
  double get swirlAmp => values[4];
  double get ringPeriodS => values[5];
  double get ringMaxOpacity => values[6];
  double get corePulseAmp => values[7];
  double get baseScale => values[8];
  double get saturation => values[9];
  double get glowAlpha => values[10];
  double get ampCoupling => values[11];
  double get noiseGateDb => values[12];

  OrbParameters lerp(OrbParameters other, double k) => OrbParameters([
        for (var i = 0; i < values.length; i++)
          values[i] + (other.values[i] - values[i]) * k,
      ]);

  /// IDLE_LISTENING — a slow breath, rings barely perceptible, no audio
  /// coupling. This is the resting baseline the operator could not see before.
  static const idle = OrbParameters([
    6.4, 0.030, 18.0, 0.04, 0.02, 5.2, 0.20, 0.035, 1.00, 1.00, 0.34, 0.0, 9.0,
  ]);

  /// USER_SPEAKING — receptive outward bloom, expanded by user vocal power.
  static const userSpeaking = OrbParameters([
    4.2, 0.048, 9.0, 0.10, 0.05, 3.0, 0.32, 0.10, 1.04, 1.00, 0.46, 1.0, 7.0,
  ]);

  /// THINKING_PROCESSING — deep concentrated gyration: fast rotation, high swirl
  /// amplitude, almost no breath, no rings at all.
  static const thinking = OrbParameters([
    5.0, 0.016, 7.0, 0.55, 0.17, 5.0, 0.0, 0.22, 0.97, 0.92, 0.40, 0.0, 9.0,
  ]);

  /// ASSISTANT_SPEAKING — radiant, expansive, modulated by real playback.
  static const assistantSpeaking = OrbParameters([
    3.1, 0.060, 11.0, 0.16, 0.07, 3.2, 0.46, 0.12, 1.06, 1.05, 0.60, 1.0, 9.0,
  ]);

  /// MUTED — contracted, desaturated, almost still.
  static const muted = OrbParameters([
    9.5, 0.008, 30.0, 0.012, 0.006, 7.0, 0.08, 0.008, 0.90, 0.55, 0.16, 0.0, 9.0,
  ]);

  static OrbParameters forPhase(CallPhase phase) => switch (phase) {
        CallPhase.idle => idle,
        CallPhase.userSpeaking => userSpeaking,
        CallPhase.thinking => thinking,
        CallPhase.assistantSpeaking => assistantSpeaking,
        CallPhase.muted => muted,
        CallPhase.ended => muted,
      };
}

/// §8.3 transition matrix: time constant in seconds for the whole parameter
/// vector. `ASSIST -> USER` is the fastest pair in the table because it is the
/// barge-in, and the user must see that they have the floor immediately.
const Map<(CallPhase, CallPhase), double> _transitionTau = {
  (CallPhase.idle, CallPhase.userSpeaking): 0.30,
  (CallPhase.idle, CallPhase.thinking): 0.35,
  (CallPhase.idle, CallPhase.assistantSpeaking): 0.30,
  (CallPhase.idle, CallPhase.muted): 0.35,
  (CallPhase.userSpeaking, CallPhase.idle): 0.40,
  (CallPhase.userSpeaking, CallPhase.thinking): 0.40,
  (CallPhase.userSpeaking, CallPhase.assistantSpeaking): 0.35,
  (CallPhase.userSpeaking, CallPhase.muted): 0.35,
  (CallPhase.thinking, CallPhase.idle): 0.45,
  (CallPhase.thinking, CallPhase.userSpeaking): 0.35,
  (CallPhase.thinking, CallPhase.assistantSpeaking): 0.35,
  (CallPhase.thinking, CallPhase.muted): 0.35,
  (CallPhase.assistantSpeaking, CallPhase.idle): 0.50,
  (CallPhase.assistantSpeaking, CallPhase.userSpeaking): 0.20,
  (CallPhase.assistantSpeaking, CallPhase.thinking): 0.30,
  (CallPhase.assistantSpeaking, CallPhase.muted): 0.35,
  (CallPhase.muted, CallPhase.idle): 0.45,
  (CallPhase.muted, CallPhase.userSpeaking): 0.45,
  (CallPhase.muted, CallPhase.thinking): 0.45,
  (CallPhase.muted, CallPhase.assistantSpeaking): 0.45,
};

/// Client-side mirror of the §7.4 table. A `null` result is an illegal pair —
/// a race between the local provisional gate and a server event. It is logged
/// and absorbed: a live call must not die on a server race.
const Map<(CallPhase, TurnEvent), CallPhase> _transitionTable = {
  // IDLE -> USER_SPEAKING
  (CallPhase.idle, TurnEvent.turnStarted): CallPhase.userSpeaking,
  (CallPhase.idle, TurnEvent.localOnset): CallPhase.userSpeaking,
  (CallPhase.idle, TurnEvent.speechDetected): CallPhase.userSpeaking,
  (CallPhase.idle, TurnEvent.interrupted): CallPhase.userSpeaking,
  (CallPhase.idle, TurnEvent.firstToken): CallPhase.thinking,
  (CallPhase.idle, TurnEvent.firstAudioFrame): CallPhase.assistantSpeaking,
  (CallPhase.idle, TurnEvent.processing): CallPhase.thinking,
  (CallPhase.idle, TurnEvent.ttsComplete): CallPhase.idle,
  // USER_SPEAKING
  // Confirmations of a turn the client already opened locally: no change.
  (CallPhase.userSpeaking, TurnEvent.turnStarted): CallPhase.userSpeaking,
  (CallPhase.userSpeaking, TurnEvent.speechDetected): CallPhase.userSpeaking,
  // A fresh onset while the previous turn is still being finalised: the floor
  // is already ours, the new turn simply replaces the old one's audio.
  (CallPhase.userSpeaking, TurnEvent.localOnset): CallPhase.userSpeaking,
  // The server answered before this client's own endpoint landed.
  (CallPhase.userSpeaking, TurnEvent.firstAudioFrame): CallPhase.assistantSpeaking,
  (CallPhase.userSpeaking, TurnEvent.firstToken): CallPhase.thinking,
  (CallPhase.userSpeaking, TurnEvent.endpointed): CallPhase.thinking,
  (CallPhase.userSpeaking, TurnEvent.discarded): CallPhase.idle,
  (CallPhase.userSpeaking, TurnEvent.cancelled): CallPhase.idle,
  (CallPhase.userSpeaking, TurnEvent.interrupted): CallPhase.assistantSpeaking,
  (CallPhase.userSpeaking, TurnEvent.ttsComplete): CallPhase.userSpeaking,
  // THINKING
  // The user reclaimed the floor while a response was still in flight.
  (CallPhase.thinking, TurnEvent.localOnset): CallPhase.userSpeaking,
  (CallPhase.thinking, TurnEvent.turnStarted): CallPhase.userSpeaking,
  (CallPhase.thinking, TurnEvent.speechDetected): CallPhase.userSpeaking,
  (CallPhase.thinking, TurnEvent.firstToken): CallPhase.thinking,
  (CallPhase.thinking, TurnEvent.processing): CallPhase.thinking,
  (CallPhase.thinking, TurnEvent.firstAudioFrame): CallPhase.assistantSpeaking,
  (CallPhase.thinking, TurnEvent.discarded): CallPhase.idle,
  (CallPhase.thinking, TurnEvent.cancelled): CallPhase.idle,
  (CallPhase.thinking, TurnEvent.interrupted): CallPhase.userSpeaking,
  (CallPhase.thinking, TurnEvent.ttsComplete): CallPhase.idle,
  // MUTED / ENDED absorb a late server event without leaving their state.
  (CallPhase.muted, TurnEvent.cancelled): CallPhase.muted,
  (CallPhase.muted, TurnEvent.discarded): CallPhase.muted,
  (CallPhase.ended, TurnEvent.cancelled): CallPhase.ended,
  (CallPhase.ended, TurnEvent.discarded): CallPhase.ended,
  // ASSISTANT_SPEAKING
  (CallPhase.assistantSpeaking, TurnEvent.interrupted): CallPhase.userSpeaking,
  (CallPhase.assistantSpeaking, TurnEvent.speechDetected): CallPhase.userSpeaking,
  (CallPhase.assistantSpeaking, TurnEvent.localOnset): CallPhase.userSpeaking,
  // A new turn can start while the previous audio is still draining: the
  // server raced our playback, the floor goes to the user.
  (CallPhase.assistantSpeaking, TurnEvent.turnStarted): CallPhase.userSpeaking,
  (CallPhase.assistantSpeaking, TurnEvent.firstAudioFrame):
      CallPhase.assistantSpeaking,
  (CallPhase.assistantSpeaking, TurnEvent.firstToken):
      CallPhase.assistantSpeaking,
  (CallPhase.assistantSpeaking, TurnEvent.processing):
      CallPhase.assistantSpeaking,
  (CallPhase.assistantSpeaking, TurnEvent.endpointed): CallPhase.thinking,
  (CallPhase.assistantSpeaking, TurnEvent.ttsComplete): CallPhase.idle,
  (CallPhase.assistantSpeaking, TurnEvent.discarded): CallPhase.idle,
};

/// What the local gate knows when it proposes an onset. Passed as one value so
/// there is a single barge-in path (spec §5.4: two paths into barge-in, one
/// gated evaluator).
class SpeechProbe {
  const SpeechProbe({
    required this.snrDb,
    required this.onsetRunMs,
    required this.speechMs,
    required this.assistantSpeaking,
    required this.sinceAssistantStartMs,
  });

  final double snrDb;
  final int onsetRunMs;
  final int speechMs;
  final bool assistantSpeaking;
  final int sinceAssistantStartMs;

  /// A backchannel ("mm-hm", "right") is short and lands early in the
  /// assistant's turn. That is the single most common barge-in bug, and
  /// duration + position is enough to catch it without a model.
  static const int backchannelMaxMs = 250;
  static const int backchannelWindowMs = 1000;
}

/// The single owner of conversational state. `call_page.dart` and the Living
/// Orb both read from here; nothing else writes orb state (spec §7.5).
class CallTurnController extends ChangeNotifier {
  /// [clock] is injectable so transition timestamps are deterministic in tests.
  CallTurnController({Stopwatch? clock}) : _clock = clock ?? Stopwatch();

  final Stopwatch _clock;
  final ValueNotifier<CallPhase> phase = ValueNotifier(CallPhase.idle);

  final _transitions = StreamController<CallPhaseTransition>.broadcast();
  Stream<CallPhaseTransition> get transitions => _transitions.stream;

  CallPhase get currentPhase => phase.value;

  CallPhase _phaseBeforeMute = CallPhase.idle;
  bool _muted = false;
  bool _ended = false;

  String? _turnId;
  String? get activeTurnId => _turnId;

  TurnStage _stage = TurnStage.vad;
  TurnStage get stage => _stage;

  // --- Orb animation state (§8.2, §8.5) -------------------------------------
  OrbParameters _params = OrbParameters.idle;
  OrbParameters get parameters => _params;

  /// Time constant of the current transition, from the §8.3 matrix.
  double _tau = 0.35;

  /// Smoothed phase *rate*, not a rate applied straight to the accumulator.
  /// Without this filter every state change pops the frequency of all
  /// harmonics at once — the single highest-value visual fix in the spec.
  double _rate = OrbParameters.idle.rotRate;
  double get rotationRate => _rate;

  /// Animation phase in seconds. Never wraps.
  double _animPhase = 0.0;
  double get animationPhase => _animPhase;

  /// Modulation actually applied this frame, 0..1. Zero unless the current
  /// state couples to audio (§8.5): only USER and ASSIST do.
  double _modulation = 0.0;
  double get modulation => _modulation;

  /// Envelope-follower state before the perceptual map, kept so both stages of
  /// §8.5 are observable.
  double _amp = 0.0;
  double get envelope => _amp;

  double _rawAmp = 0.0;
  double _noiseFloorRms = 0.0;

  static const double _attackTau = 0.025;
  static const double _releaseTau = 0.180;
  static const double _rateTau = 0.35;
  static const double _dbfsMin = 6.0;
  static const double _dbfsMax = 34.0;

  // ---------------------------------------------------------------------------

  /// Feed the tracked noise floor so the display gate (§8.5 stage 2) can zero a
  /// level that is only passing the gate by a hair.
  set noiseFloorRms(double value) => _noiseFloorRms = value;

  /// Raw normalised RMS for the current phase's modulation source: user mic
  /// level while the user speaks, real playback level while Solace speaks.
  set rawAmplitude(double value) => _rawAmp = value.clamp(0.0, 1.0);

  /// §8.5: display gate, asymmetric envelope follower, log-domain mapping.
  void _updateModulation(double dt) {
    final gate = _noiseFloorRms > 0
        ? _noiseFloorRms * math.pow(10, _params.noiseGateDb / 20).toDouble()
        : 0.0;
    final target = _rawAmp <= gate ? 0.0 : _rawAmp;
    final tau = target > _amp ? _attackTau : _releaseTau;
    _amp += (target - _amp) * (1 - math.exp(-dt / tau));

    final dbfs = 20 * (math.log(math.max(_amp, 1e-4) * 32768.0) / math.ln10);
    final mapped = ((dbfs - _dbfsMin) / (_dbfsMax - _dbfsMin)).clamp(0.0, 1.0);
    _modulation = _params.ampCoupling * mapped;
  }

  /// Advance every animated quantity. Called from a Ticker; drives the painter
  /// through [notifyListeners] so no `setState` is needed anywhere.
  void tick(double dtSeconds) {
    if (dtSeconds <= 0) return;
    final target = OrbParameters
        .forPhase(_muted ? _phaseBeforeMute : currentPhase)
        .lerp(OrbParameters.muted, _muted ? 1.0 : 0.0);
    _params = _params.lerp(target, 1 - math.exp(-dtSeconds / _tau));

    final targetRate = _params.rotRate;
    _rate += (targetRate - _rate) * (1 - math.exp(-dtSeconds / _rateTau));
    _animPhase += _rate * dtSeconds;

    _updateModulation(dtSeconds);
    notifyListeners();
  }

  // --- events ----------------------------------------------------------------

  /// A local onset is *provisional*: the client acts on echo-filtered evidence
  /// immediately and reconciles when `turn.speech_detected` or `transcript_final`
  /// arrives. Returns the barge-in class so the caller knows whether to flush
  /// playback.
  BargeInClass onLocalOnset(SpeechProbe probe) {
    if (_ended) return BargeInClass.noise;
    if (!probe.assistantSpeaking) {
      _apply(TurnEvent.localOnset);
      return BargeInClass.interrupt;
    }
    final isBackchannel = probe.speechMs > 0 &&
        probe.speechMs < SpeechProbe.backchannelMaxMs &&
        probe.sinceAssistantStartMs < SpeechProbe.backchannelWindowMs;
    if (isBackchannel) {
      // Logged, not acted on: the assistant keeps talking (spec §5.8).
      _log(TurnEvent.localOnset, currentPhase);
      return BargeInClass.backchannel;
    }
    _apply(TurnEvent.localOnset);
    return BargeInClass.interrupt;
  }

  void onTurnStarted(String? turnId) {
    if (turnId != null) _turnId = turnId;
    _apply(TurnEvent.turnStarted);
  }

  void onSpeechDetected(String? turnId, {int offsetMs = 0, double confidence = 0.0}) {
    if (turnId != null) _turnId = turnId;
    _apply(TurnEvent.speechDetected);
  }

  void onEndpointed(String? turnId, {int speechMs = 0, int silenceMs = 0}) {
    if (turnId != null) _turnId = turnId;
    _apply(TurnEvent.endpointed);
  }

  void onProcessing(String? turnId, TurnStage stage, {int elapsedMs = 0}) {
    if (turnId != null) _turnId = turnId;
    _stage = stage;
    switch (stage) {
      case TurnStage.llmFirstToken:
        _apply(TurnEvent.firstToken);
      case TurnStage.ttsFirstFrame:
        _apply(TurnEvent.firstAudioFrame);
      default:
        // Sub-stages are telemetry only. The orb must not flicker between them,
        // so a `vad`/`stt`/`tool` update only opens THINKING if nothing has.
        if (currentPhase == CallPhase.idle &&
            _transitionTable.containsKey((currentPhase, TurnEvent.processing))) {
          _apply(TurnEvent.processing);
        }
    }
  }

  void onTtsComplete() {
    _turnId = null;
    _apply(TurnEvent.ttsComplete);
  }

  void onDiscarded(String? turnId, DiscardReason reason) {
    if (turnId != null && turnId != _turnId) return;
    _turnId = null;
    _apply(TurnEvent.discarded);
  }

  /// The user took the floor. [playedMs] is what the ear actually heard and is
  /// the server's truncation point; the caller reads it *before* flushing local
  /// playback (spec §6.2).
  void onInterrupted({required String? turnId, required int playedMs}) {
    if (turnId != null) _turnId = turnId;
    _apply(TurnEvent.interrupted);
  }

  /// A false interruption timed out: the server resumes from [fromMs]. The
  /// provisional barge-in is reverted.
  void onTtsResume(String? utteranceId, int fromMs) {
    if (currentPhase == CallPhase.userSpeaking) {
      _apply(TurnEvent.interrupted);
    }
  }

  void onTurnCancelled() {
    _turnId = null;
    _apply(TurnEvent.cancelled);
  }

  void onMicMutedChanged(bool muted) {
    if (_ended || _muted == muted) return;
    _muted = muted;
    final from = currentPhase;
    final to = muted
        ? CallPhase.muted
        : (_phaseBeforeMute == CallPhase.muted ||
                _phaseBeforeMute == CallPhase.thinking ||
                _phaseBeforeMute == CallPhase.assistantSpeaking
            ? CallPhase.idle
            : _phaseBeforeMute);
    if (from != CallPhase.muted) {
      _tau = _transitionTau[(from, to)] ?? 0.35;
    }
    _setPhase(to);
    _log(muted ? TurnEvent.cancelled : TurnEvent.turnStarted, from);
    notifyListeners();
  }

  void onCallEnded() {
    _ended = true;
    _muted = false;
    _setPhase(CallPhase.ended);
    _log(TurnEvent.callEnded, currentPhase);
    notifyListeners();
  }

  void reset() {
    _turnId = null;
    _ended = false;
    _muted = false;
    _phaseBeforeMute = CallPhase.idle;
    _stage = TurnStage.vad;
    _setPhase(CallPhase.idle);
    notifyListeners();
  }

  // --- machine ---------------------------------------------------------------

  void _apply(TurnEvent event) {
    final from = currentPhase;
    final to = _transitionTable[(from, event)];
    if (to == null) {
      // Illegal pair: a race between the local provisional gate and a server
      // event. Log and absorb — a fatal assert here killed the event stream
      // mid-call.
      debugPrint(
        '[CallTurnController] Unhandled transition: ${from.name} --${event.name}--> ignoring',
      );
      return;
    }
    if (to != CallPhase.muted && to != CallPhase.ended) {
      _phaseBeforeMute = to;
    }
    _tau = _transitionTau[(from, to)] ?? 0.35;
    _setPhase(to);
    _log(event, from);
    notifyListeners();
  }

  void _setPhase(CallPhase next) {
    if (phase.value == next) return;
    phase.value = next;
  }

  void _log(TurnEvent event, CallPhase from) {
    if (_transitions.isClosed) return;
    _transitions.add(CallPhaseTransition(
      from: from,
      to: currentPhase,
      event: event,
      tMs: _clock.elapsedMilliseconds,
    ));
  }

  @override
  void dispose() {
    _transitions.close();
    phase.dispose();
    super.dispose();
  }
}
