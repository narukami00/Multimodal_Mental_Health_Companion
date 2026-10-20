/// The one gentle line shown during a call when the person has opted in to
/// Sol noticing how they sound.
///
/// Always hedged: it is a weak guess from voice and words, never a diagnosis.
/// A "clear" estimate says "sound", a "hint" says "might". Neutral or unsure
/// turns (null mood) show nothing at all. Valence and arousal never reach the
/// screen; only plain words do.
String? moodNoteFor(String? mood, String? tier) {
  if (mood == null || tier == null) return null;
  final feeling = switch (mood) {
    'low or tired' => 'a bit low or tired',
    'tense or upset' => 'a bit tense or upset',
    'upbeat' => 'upbeat',
    'calm or content' => 'calm',
    _ => null,
  };
  if (feeling == null) return null;
  return switch (tier) {
    'clear' => 'You sound $feeling.',
    'hint' => 'You might be feeling $feeling.',
    _ => null,
  };
}
