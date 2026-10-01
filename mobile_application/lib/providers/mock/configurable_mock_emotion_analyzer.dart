import 'dart:math' as math;

import '../../core/emotion/emotion_taxonomy.dart';
import '../../core/models/emotion_result.dart';
import '../../core/models/session_input.dart';
import '../../data/contracts/provider_contracts.dart';

/// What a mock run should look like to the rest of the app.
enum MockEmotionScenario {
  /// Mostly positive readings.
  positive,

  /// Mostly negative readings.
  negative,

  /// Mostly neutral readings.
  neutral,

  /// Positive at first, drifting negative over successive calls.
  decline,

  /// Negative at first, drifting positive over successive calls.
  uplift,

  /// Each call lands anywhere, seeded so it is reproducible.
  mixed,
}

/// A stand-in for the real emotion model that works with **any** taxonomy.
///
/// It emits what the real model will: classes with a confidence, and no valence
/// or arousal. It picks labels from whatever [EmotionTaxonomy] it is given, so
/// the pipeline can be exercised end to end now and the real model dropped in
/// later with only a different analyzer and taxonomy file.
///
/// Deterministic for a given [seed] and call order, and clock-injectable, so
/// tests can script a week of readings.
class ConfigurableMockEmotionAnalyzer implements EmotionAnalyzer {
  ConfigurableMockEmotionAnalyzer({
    this.taxonomy = EmotionTaxonomy.placeholder,
    this.scenario = MockEmotionScenario.mixed,
    this.origin = EmotionOrigin.checkIn,
    this.seed = 0,
    this.driftCalls = 10,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _random = math.Random(seed);

  final EmotionTaxonomy taxonomy;
  final MockEmotionScenario scenario;
  final EmotionOrigin origin;
  final int seed;

  /// How many calls a [MockEmotionScenario.decline] or
  /// [MockEmotionScenario.uplift] takes to finish turning.
  final int driftCalls;

  static const modelVersionPrefix = 'mock-configurable-v1';

  final DateTime Function() _clock;
  final math.Random _random;
  int _calls = 0;

  @override
  Future<List<EmotionResult>> analyze(SessionInput input) async {
    final pull = _nextPull();
    final labels = _labelsFor(pull);
    final modality = switch (input.mode) {
      CaptureMode.text => EmotionModality.text,
      CaptureMode.voice => EmotionModality.voice,
      CaptureMode.video => EmotionModality.face,
    };
    _calls++;

    return [
      EmotionResult(
        sessionId: input.sessionId,
        modality: modality,
        origin: origin,
        timestamp: _clock(),
        // An empty taxonomy yields no reading at all, rather than an empty
        // list posing as one.
        labels: labels.isEmpty ? null : labels,
        confidence: labels.isEmpty ? null : labels.first.score,
        modelVersion: '$modelVersionPrefix+${taxonomy.version}',
      ),
    ];
  }

  AffectGroup _nextPull() {
    switch (scenario) {
      case MockEmotionScenario.positive:
        return AffectGroup.positive;
      case MockEmotionScenario.negative:
        return AffectGroup.negative;
      case MockEmotionScenario.neutral:
        return AffectGroup.neutral;
      case MockEmotionScenario.decline:
        return _calls < driftCalls ~/ 2
            ? AffectGroup.positive
            : AffectGroup.negative;
      case MockEmotionScenario.uplift:
        return _calls < driftCalls ~/ 2
            ? AffectGroup.negative
            : AffectGroup.positive;
      case MockEmotionScenario.mixed:
        const groups = [
          AffectGroup.positive,
          AffectGroup.negative,
          AffectGroup.neutral,
        ];
        return groups[_random.nextInt(groups.length)];
    }
  }

  /// A dominant class from [pull]'s group plus a small spread over the rest,
  /// scores summing to 1. Falls back to any class if the taxonomy has none in
  /// that group, so a custom taxonomy never makes the mock throw.
  List<EmotionLabel> _labelsFor(AffectGroup pull) {
    final all = taxonomy.labels;
    if (all.isEmpty) return const [];

    final inGroup = [
      for (final c in taxonomy.classes)
        if (c.affectGroup == pull) c.label,
    ];
    final pool = inGroup.isEmpty ? all : inGroup;
    final dominant = pool[_random.nextInt(pool.length)];

    final dominantScore = 0.55 + _random.nextDouble() * 0.3;
    final others = all.where((label) => label != dominant).toList();
    if (others.isEmpty) {
      return [EmotionLabel(label: dominant, score: 1)];
    }

    final weights = [for (final _ in others) 0.2 + _random.nextDouble()];
    final weightSum = weights.fold<double>(0, (a, b) => a + b);
    final rest = 1 - dominantScore;
    return [
      EmotionLabel(label: dominant, score: dominantScore),
      for (var i = 0; i < others.length; i++)
        EmotionLabel(label: others[i], score: rest * weights[i] / weightSum),
    ];
  }
}
