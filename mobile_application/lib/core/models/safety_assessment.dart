enum SafetyLevel { clear, supportSuggested, urgentSupport }

class SafetyAssessment {
  const SafetyAssessment({
    required this.level,
    this.matchedSignals = const [],
  });

  const SafetyAssessment.clear() : this(level: SafetyLevel.clear);

  final SafetyLevel level;
  final List<String> matchedSignals;
}
