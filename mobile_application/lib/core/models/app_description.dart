/// What the platform says an app is, for grouping usage by category.
class AppDescription {
  const AppDescription({
    required this.label,
    this.category,
    this.ignore = false,
    this.visible = true,
  });

  /// The name the user knows the app by. Only used when they have separately
  /// agreed to keep app names, and never leaves the device.
  final String label;

  /// The platform's own category where it is one of the few that matter, else
  /// null and the grouping rules decide.
  final String? category;

  /// Launchers, system UI and this app itself: screen time, but not an app the
  /// person chose to spend time in.
  final bool ignore;

  /// False when Android hides the package from this app. It is then grouped as
  /// "other", never guessed at.
  final bool visible;

  static AppDescription? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    return AppDescription(
      label: label is String && label.isNotEmpty ? label : '',
      category: raw['category'] as String?,
      ignore: raw['ignore'] as bool? ?? false,
      visible: raw['visible'] as bool? ?? true,
    );
  }
}
