/// Switches that turn one source of signal off, for studies that compare the app
/// with and without it.
///
/// Every switch is on by default and nothing in the app changes it. A study
/// build sets [Ablations.current] once at start-up. Turning a switch off removes
/// the signal at the single place it enters, so an arm of a study differs from
/// another in exactly one thing and the tests can prove the signal is truly
/// gone rather than hidden.
class Ablations {
  const Ablations({
    this.capacity = true,
    this.moodChangeOutcomes = true,
    this.phoneSignals = true,
    this.companionMemory = true,
  });

  /// Capacity (time of day, sleep hours, mood) shaping how much an idea asks of
  /// someone. Off: ideas are chosen as if capacity were unknown.
  final bool capacity;

  /// How the person said they felt after an idea counting for or against it.
  /// Off: ratings are read exactly as given.
  final bool moodChangeOutcomes;

  /// Anything derived from phone use: collection, patterns, shifts, and the
  /// question about them. Off: nothing is read and nothing is derived.
  final bool phoneSignals;

  /// What the companion is told about the person: the profile snippet and kept
  /// moments. Off: the companion is told nothing beyond the conversation.
  final bool companionMemory;

  /// The arm this build runs. Defaults to everything on.
  static Ablations current = const Ablations();

  /// Back to everything on. For tests, so one test's arm never leaks into the
  /// next.
  static void reset() => current = const Ablations();

  /// A short label such as `all-on` or `no-capacity+no-phone`, to stamp onto
  /// an export so an arm can always be told from its name.
  String get label {
    final off = [
      if (!capacity) 'no-capacity',
      if (!moodChangeOutcomes) 'no-mood-outcomes',
      if (!phoneSignals) 'no-phone',
      if (!companionMemory) 'no-companion-memory',
    ];
    return off.isEmpty ? 'all-on' : off.join('+');
  }
}
