/// Phase of the paced breathing cycle.
enum BreathPhase { inhale, hold, exhale }

/// Pure timing model behind the paced breathing guide.
///
/// Defaults to a calm in-4 / hold-4 / out-6 pattern. Kept free of Flutter
/// imports so the pacing can be verified directly.
class BreathingPattern {
  const BreathingPattern({
    this.inhaleMs = 4000,
    this.holdMs = 4000,
    this.exhaleMs = 6000,
  });

  final int inhaleMs;
  final int holdMs;
  final int exhaleMs;

  /// Total length of one breathing cycle.
  int get cycleMs => inhaleMs + holdMs + exhaleMs;

  /// Smallest circle scale, at the start of an inhale.
  static const minScale = 0.62;

  static const _span = 1.0 - minScale;

  /// Which phase the cycle is in at [progress] (0..1 through one cycle).
  BreathPhase phaseAt(double progress) {
    final ms = progress.clamp(0.0, 1.0) * cycleMs;
    if (ms < inhaleMs) return BreathPhase.inhale;
    if (ms < inhaleMs + holdMs) return BreathPhase.hold;
    return BreathPhase.exhale;
  }

  /// Circle scale at [progress], so the guide visibly breathes.
  double scaleAt(double progress) {
    final ms = progress.clamp(0.0, 1.0) * cycleMs;
    if (ms < inhaleMs) {
      return minScale + _span * BreathEase.easeInOut(ms / inhaleMs);
    }
    if (ms < inhaleMs + holdMs) return 1.0;
    final t = (ms - inhaleMs - holdMs) / exhaleMs;
    return 1.0 - _span * BreathEase.easeInOut(t);
  }

  /// The short cue shown inside the circle for [phase].
  String cueFor(BreathPhase phase) {
    return switch (phase) {
      BreathPhase.inhale => 'Breathe in',
      BreathPhase.hold => 'Hold',
      BreathPhase.exhale => 'Breathe out',
    };
  }
}

/// Minimal ease-in-out helper, so this model stays Flutter-free.
abstract final class BreathEase {
  /// Smooth acceleration then deceleration across t (0..1).
  static double easeInOut(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return clamped < 0.5
        ? 2 * clamped * clamped
        : 1 - ((-2 * clamped + 2) * (-2 * clamped + 2)) / 2;
  }
}
