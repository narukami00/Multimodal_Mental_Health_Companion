import 'dart:math' as math;

import '../../core/day_key.dart';
import '../../core/emotion/emotion_taxonomy.dart';
import '../../core/models/emotion_result.dart';

/// One day (or one session) of emotion results, folded into numbers that do not
/// care which classes the model has.
///
/// The model outputs classes with a confidence and nothing else, and its class
/// set is not final. So this keeps the label distribution as plain strings,
/// asks the [EmotionTaxonomy] only to group them, and treats a label the
/// taxonomy does not know as [AffectGroup.unmapped] rather than as an error.
/// Swapping the model or the taxonomy changes no code here.
///
/// Pure: no clock, no I/O.
class EmotionDaily {
  const EmotionDaily({
    required this.distribution,
    required this.dominantLabel,
    required this.dominantShare,
    required this.entropy,
    required this.affectShare,
    required this.coverage,
    required this.meanConfidence,
    this.meanValence,
    this.meanArousal,
  });

  /// Share of the day by label, confidence-weighted, summing to 1.
  final Map<String, double> distribution;

  /// The label with the largest share. Ties go to the alphabetically first
  /// label, so a day always has one reproducible answer.
  final String dominantLabel;
  final double dominantShare;

  /// How spread out the day was, 0 (one label) to 1 (all labels equally).
  final double entropy;

  /// [distribution] grouped by the taxonomy. Always has every group, so callers
  /// never need to check for a missing key.
  final Map<AffectGroup, double> affectShare;

  /// Results that contributed. Small coverage means the day is thinly known.
  final int coverage;

  /// Mean confidence of the contributing results, 0 to 1.
  final double meanConfidence;

  /// Present only if some result carried it. The model may never provide these.
  final double? meanValence;
  final double? meanArousal;

  /// Folds [results] into one aggregate, or null if none carried labels.
  ///
  /// A result's weight is its confidence, or [defaultConfidence] when the model
  /// gave none. A result with no confidence at all is therefore counted at half
  /// weight instead of being trusted fully or dropped.
  static EmotionDaily? aggregate(
    Iterable<EmotionResult> results, {
    required EmotionTaxonomy taxonomy,
    double defaultConfidence = 0.5,
  }) {
    final totals = <String, double>{};
    var weightSum = 0.0;
    var coverage = 0;
    var valenceSum = 0.0;
    var valenceWeight = 0.0;
    var arousalSum = 0.0;
    var arousalWeight = 0.0;

    for (final result in results) {
      final scores = _normalizedScores(result);
      if (scores.isEmpty) continue;

      final weight = (result.confidence ?? defaultConfidence).clamp(0.0, 1.0);
      if (weight <= 0) continue;

      scores.forEach((label, share) {
        totals[label] = (totals[label] ?? 0) + weight * share;
      });
      weightSum += weight;
      coverage++;

      final valence = result.valence;
      if (valence != null) {
        valenceSum += weight * valence;
        valenceWeight += weight;
      }
      final arousal = result.arousal;
      if (arousal != null) {
        arousalSum += weight * arousal;
        arousalWeight += weight;
      }
    }

    if (coverage == 0 || weightSum <= 0) return null;

    final distribution = {
      for (final entry in totals.entries) entry.key: entry.value / weightSum,
    };

    final labels = distribution.keys.toList()..sort();
    var dominant = labels.first;
    for (final label in labels) {
      if (distribution[label]! > distribution[dominant]! + 1e-12) {
        dominant = label;
      }
    }

    final affectShare = {for (final group in AffectGroup.values) group: 0.0};
    distribution.forEach((label, share) {
      final group = taxonomy.affectGroupOf(label);
      affectShare[group] = affectShare[group]! + share;
    });

    return EmotionDaily(
      distribution: Map.unmodifiable(distribution),
      dominantLabel: dominant,
      dominantShare: distribution[dominant]!,
      entropy: _normalizedEntropy(distribution, taxonomy),
      affectShare: Map.unmodifiable(affectShare),
      coverage: coverage,
      meanConfidence: weightSum / coverage,
      meanValence: valenceWeight > 0 ? valenceSum / valenceWeight : null,
      meanArousal: arousalWeight > 0 ? arousalSum / arousalWeight : null,
    );
  }

  /// Groups results by the local day they were made and aggregates each day.
  /// [origins], when given, limits which sources count.
  static Map<String, EmotionDaily> byDay(
    Iterable<EmotionResult> results, {
    required EmotionTaxonomy taxonomy,
    Set<EmotionOrigin>? origins,
    double defaultConfidence = 0.5,
  }) {
    final grouped = <String, List<EmotionResult>>{};
    for (final result in results) {
      if (origins != null && !origins.contains(result.origin)) continue;
      grouped.putIfAbsent(dayKey(result.timestamp), () => []).add(result);
    }
    return {
      for (final entry in grouped.entries)
        if (aggregate(
              entry.value,
              taxonomy: taxonomy,
              defaultConfidence: defaultConfidence,
            )
            case final daily?)
          entry.key: daily,
    };
  }

  /// A result's label scores as shares of 1. Labels are lower-cased and
  /// trimmed so "Calm" and "calm " are one class. With no scores at all the
  /// labels split the result equally; otherwise a missing score counts as zero.
  static Map<String, double> _normalizedScores(EmotionResult result) {
    final labels = result.labels;
    if (labels == null || labels.isEmpty) return const {};

    final raw = <String, double>{};
    var anyScore = false;
    for (final label in labels) {
      final name = label.label.trim().toLowerCase();
      if (name.isEmpty) continue;
      final score = label.score;
      if (score != null) anyScore = true;
      raw[name] = (raw[name] ?? 0) + (score ?? 0).clamp(0.0, 1.0);
    }
    if (raw.isEmpty) return const {};

    if (!anyScore) {
      final even = 1 / raw.length;
      return {for (final name in raw.keys) name: even};
    }
    final sum = raw.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return const {};
    return {for (final entry in raw.entries) entry.key: entry.value / sum};
  }

  static double _normalizedEntropy(
    Map<String, double> distribution,
    EmotionTaxonomy taxonomy,
  ) {
    // The ceiling is the larger of the taxonomy and what was actually seen, so
    // an unfamiliar label can never push the value past 1.
    final classes = math.max(
      2,
      math.max(taxonomy.classes.length, distribution.length),
    );
    var entropy = 0.0;
    for (final share in distribution.values) {
      if (share > 0) entropy -= share * math.log(share);
    }
    return (entropy / math.log(classes)).clamp(0.0, 1.0);
  }
}
