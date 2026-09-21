import '../../core/models/safety_assessment.dart';
import '../../data/contracts/provider_contracts.dart';

class KeywordSafetyScreener implements SafetyScreener {
  const KeywordSafetyScreener();

  // This is a deterministic floor, not a complete crisis detector. Additional
  // languages and a reviewed classifier must be added before external testing.
  static const _urgentPhrases = [
    'kill myself',
    'end my life',
    'take my own life',
    'want to die',
    'wish i were dead',
    'hurt myself',
    'self harm',
    'suicide',
    'no reason to live',
    'not safe with myself',
  ];

  static const _supportPhrases = [
    'not safe',
    'cannot keep myself safe',
    'can\'t keep myself safe',
    'hopeless',
    'panic attack',
    'completely overwhelmed',
  ];

  @override
  SafetyAssessment assess(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final urgentMatches = _matches(normalized, _urgentPhrases);
    if (urgentMatches.isNotEmpty) {
      return SafetyAssessment(
        level: SafetyLevel.urgentSupport,
        matchedSignals: urgentMatches,
      );
    }

    final supportMatches = _matches(normalized, _supportPhrases);
    if (supportMatches.isNotEmpty) {
      return SafetyAssessment(
        level: SafetyLevel.supportSuggested,
        matchedSignals: supportMatches,
      );
    }

    return const SafetyAssessment.clear();
  }

  List<String> _matches(String text, List<String> phrases) {
    return [for (final phrase in phrases) if (text.contains(phrase)) phrase];
  }
}
