/// A gentle reminder the user has set for themselves — a habit, hobby, or
/// anything they want to be nudged about.
///
/// There is no completion tracking, no streak, no penalty. The user owns the
/// reminder; whether they act on it is entirely their choice.
class HabitReminder {
  const HabitReminder({
    required this.id,
    required this.title,
    this.description = '',
    required this.hour,
    required this.minute,
    this.days = const {1, 2, 3, 4, 5, 6, 7},
    this.enabled = true,
  });

  final String id;
  final String title;
  final String description;

  /// Time of day in 24-hour format.
  final int hour;
  final int minute;

  /// Days of the week this reminder fires on.
  /// 1 = Monday, 7 = Sunday (ISO 8601).
  final Set<int> days;

  /// Whether notifications are currently active for this reminder.
  final bool enabled;

  bool get isEveryDay => days.length == 7;

  /// Human-readable time string like "8:30 AM".
  String get timeLabel {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  /// Short label for which days are active.
  String get daysLabel {
    if (isEveryDay) return 'Every day';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = days.toList()..sort();
    return sorted.map((d) => names[d - 1]).join(', ');
  }

  HabitReminder copyWith({
    String? title,
    String? description,
    int? hour,
    int? minute,
    Set<int>? days,
    bool? enabled,
  }) {
    return HabitReminder(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      days: days ?? this.days,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'hour': hour,
      'minute': minute,
      'days': days.toList()..sort(),
      'enabled': enabled,
    };
  }

  factory HabitReminder.fromMap(Map<String, dynamic> map) {
    return HabitReminder(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      hour: (map['hour'] as num?)?.toInt() ?? 8,
      minute: (map['minute'] as num?)?.toInt() ?? 0,
      days: _parseDays(map['days']),
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  static Set<int> _parseDays(Object? value) {
    if (value is! List) return const {1, 2, 3, 4, 5, 6, 7};
    final result = <int>{};
    for (final item in value) {
      if (item is num) {
        final day = item.toInt();
        if (day >= 1 && day <= 7) result.add(day);
      }
    }
    return result.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : result;
  }
}
