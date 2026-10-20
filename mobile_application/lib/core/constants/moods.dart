/// The mood words offered on a check-in.
///
/// One tap is a complete check-in: these are deliberately few, plain, and not
/// clinical. Shared so the text check-in and the one-word path cannot drift
/// apart.
abstract final class Moods {
  /// The internal five-step scale (kept so every earlier entry, baseline and insight still works).
  /// What a PERSON sees is [display]: plain words that describe how an entry read.
  static const values = ['Steady', 'Bright', 'Tender', 'Wobbly', 'Quiet'];

  /// The plain word shown for an internal mood: Bright -> Upbeat, Steady -> Calm, Quiet -> Even,
  /// Tender -> Low, Wobbly -> Tense. Unknown words are shown as they are.
  static String display(String? mood) => switch (mood?.trim().toLowerCase()) {
        'bright' => 'Upbeat',
        'steady' => 'Calm',
        'quiet' => 'Even',
        'tender' => 'Low',
        'wobbly' => 'Tense',
        _ => mood ?? '',
      };

  /// The internal mood for a model reading's own mood word ('upbeat', 'calm or content', 'low or tired',
  /// 'tense or upset'); an unsure reading (null) is 'Quiet' (Even).
  static String fromReadingMood(String? readingMood) => switch (readingMood) {
        'upbeat' => 'Bright',
        'calm or content' => 'Steady',
        'low or tired' => 'Tender',
        'tense or upset' => 'Wobbly',
        _ => 'Quiet',
      };

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
