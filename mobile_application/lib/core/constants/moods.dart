/// The mood words offered on a check-in.
///
/// One tap is a complete check-in: these are deliberately few, plain, and not
/// clinical. Shared so the text check-in and the one-word path cannot drift
/// apart.
abstract final class Moods {
  static const values = ['Steady', 'Bright', 'Tender', 'Wobbly', 'Quiet'];

  /// A coarse ordering of the mood words, from -1 (lowest) to 1 (brightest).
  ///
  /// The words are not a scale and were never meant to be one, so this is an
  /// approximation for one narrow job: letting a day's moods have a median, so
  /// a personal baseline can notice drift *relative to that person's own
  /// usual*. It is never shown, never compared between people, and never
  /// treated as a measurement. Unknown words have no score.
  static double? score(String? mood) {
    switch (mood?.trim().toLowerCase()) {
      case 'bright':
        return 1.0;
      case 'steady':
        return 0.25;
      case 'quiet':
        return 0.0;
      case 'tender':
        return -0.25;
      case 'wobbly':
        return -1.0;
      default:
        return null;
    }
  }
}
