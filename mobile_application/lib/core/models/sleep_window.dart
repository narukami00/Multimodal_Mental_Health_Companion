/// A usual sleep window as minutes past local midnight.
///
/// The window usually crosses midnight (22:00 to 07:00), so [startMinutes] may
/// exceed [endMinutes]. A window whose ends are equal is empty rather than a
/// full day: it is what an unset or degenerate pair of pickers produces, and
/// treating it as "always asleep" would be the worse failure.
class SleepWindow {
  const SleepWindow({required this.startMinutes, required this.endMinutes});

  static const minutesPerDay = 24 * 60;

  final int startMinutes;
  final int endMinutes;

  bool get isEmpty => startMinutes == endMinutes;

  /// Length of the window, wrapping past midnight when needed.
  int get durationMinutes {
    if (isEmpty) return 0;
    final span = endMinutes - startMinutes;
    return span > 0 ? span : span + minutesPerDay;
  }

  /// Whether [minute] (past local midnight) falls inside the window.
  bool contains(int minute) {
    if (isEmpty) return false;
    return startMinutes < endMinutes
        ? minute >= startMinutes && minute < endMinutes
        : minute >= startMinutes || minute < endMinutes;
  }

  @override
  bool operator ==(Object other) =>
      other is SleepWindow &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);

  @override
  String toString() => 'SleepWindow($startMinutes-$endMinutes)';
}
