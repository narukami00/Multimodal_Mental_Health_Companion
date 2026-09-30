/// Temporary switches for trying the design out.
///
/// This exists so the budget rules can be switched off without touching any of
/// the logic that implements them, and switched back on by changing one line.
/// Nothing in the engine or the schedule reads this: the caller passes it in,
/// so the real rules stay testable while it is on.
abstract final class SuggestionTuning {
  /// While true, the daily cap, the minimum gap and the check-in requirement are
  /// all ignored, so a suggestion keeps coming back however many times it is
  /// answered. For design testing only.
  ///
  /// Set back to false to restore the real behaviour.
  static const alwaysOfferForTesting = true;
}
