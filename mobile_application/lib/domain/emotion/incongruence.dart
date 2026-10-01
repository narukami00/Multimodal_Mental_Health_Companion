import '../../core/emotion/emotion_taxonomy.dart';
import 'emotion_daily.dart';

/// A clear mismatch between how someone said they felt and what the model read
/// from what they wrote or said.
///
/// Meant to be offered as a gentle noticing ("words and voice carried different
/// tones"), never as a finding about the person.
class Incongruence {
  const Incongruence({
    required this.selfMood,
    required this.selfGroup,
    required this.predictedGroup,
    required this.predictedShare,
    required this.confidence,
  });

  final String selfMood;
  final AffectGroup selfGroup;
  final AffectGroup predictedGroup;

  /// How much of the model's reading pointed the other way, 0 to 1.
  final double predictedShare;
  final double confidence;
}

/// Which side of feeling a mood word clearly sits on, or null when it is
/// ambiguous.
///
/// Only "Bright" and "Wobbly" are clear. "Steady", "Quiet" and "Tender" can sit
/// comfortably beside a positive or a negative reading, so they never count as
/// a mismatch: a false flag here would tell someone their own words were wrong.
AffectGroup? selfMoodGroup(String? mood) {
  switch (mood?.trim().toLowerCase()) {
    case 'bright':
      return AffectGroup.positive;
    case 'wobbly':
      return AffectGroup.negative;
    default:
      return null;
  }
}

/// Flags a mismatch only when it is unmistakable: a clearly positive or
/// negative self-report, a model reading that points the opposite way for at
/// least [minShare] of its weight, and enough confidence and coverage to trust
/// it. Everything else, including every unmapped label, returns null.
///
/// The model gives classes and confidence only, so the comparison runs on
/// affect groups, never on a valence number.
Incongruence? detectIncongruence({
  required String? selfMood,
  required EmotionDaily? emotion,
  double minConfidence = 0.6,
  double minShare = 0.6,
  int minCoverage = 1,
}) {
  if (emotion == null) return null;
  final selfGroup = selfMoodGroup(selfMood);
  if (selfGroup == null) return null;
  if (emotion.coverage < minCoverage) return null;
  if (emotion.meanConfidence < minConfidence) return null;

  final opposite = selfGroup == AffectGroup.positive
      ? AffectGroup.negative
      : AffectGroup.positive;
  final share = emotion.affectShare[opposite] ?? 0;
  if (share < minShare) return null;

  return Incongruence(
    selfMood: selfMood!.trim(),
    selfGroup: selfGroup,
    predictedGroup: opposite,
    predictedShare: share,
    confidence: emotion.meanConfidence,
  );
}
