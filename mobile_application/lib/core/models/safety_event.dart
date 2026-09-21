import 'safety_assessment.dart';

class SafetyEvent {
  const SafetyEvent({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.level,
    required this.matchedSignals,
    required this.handledBy,
  });

  final String id;
  final DateTime createdAt;
  final String source;
  final SafetyLevel level;
  final List<String> matchedSignals;
  final String handledBy;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'source': source,
      'level': level.name,
      'matchedSignals': matchedSignals,
      'handledBy': handledBy,
    };
  }

  factory SafetyEvent.fromMap(Map<String, dynamic> map) {
    final levelName = map['level'] as String?;
    final level = SafetyLevel.values.firstWhere(
      (item) => item.name == levelName,
      orElse: () => SafetyLevel.supportSuggested,
    );
    final signals = map['matchedSignals'] as List<dynamic>? ?? const [];

    return SafetyEvent(
      id: map['id'] as String? ?? '',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      source: map['source'] as String? ?? 'unknown',
      level: level,
      matchedSignals: signals.whereType<String>().toList(),
      handledBy: map['handledBy'] as String? ?? 'support_resources',
    );
  }
}
