/// The few kinds of device event the daily reduction cares about.
///
/// Platform events are mapped onto these by the collector, so the logic that
/// reads them is the same whatever produced them and can be tested with plain
/// lists.
enum UsageEventType {
  /// An app came to the foreground (Android ACTIVITY_RESUMED).
  appForeground,

  /// An app left the foreground (Android ACTIVITY_PAUSED).
  appBackground,

  /// The screen became interactive.
  screenOn,

  /// The screen stopped being interactive.
  screenOff,

  /// The lock screen appeared.
  keyguardShown,

  /// The lock screen was dismissed: an unlock.
  keyguardHidden,
}

/// One device event, with only what the reduction needs. There is no
/// notification, content, or window information here, by design.
class UsageEvent {
  const UsageEvent({required this.time, required this.type, this.package});

  final DateTime time;
  final UsageEventType type;

  /// The app involved. Only app foreground and background events carry one.
  final String? package;

  Map<String, Object?> toMap() => {
    'time': time.millisecondsSinceEpoch,
    'type': type.name,
    'package': package,
  };

  /// Reads an event from a platform channel map, or null if it is unusable.
  static UsageEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final millis = raw['time'];
    final typeName = raw['type'];
    if (millis is! num || typeName is! String) return null;
    for (final type in UsageEventType.values) {
      if (type.name == typeName) {
        return UsageEvent(
          time: DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
          type: type,
          package: raw['package'] as String?,
        );
      }
    }
    return null;
  }
}
