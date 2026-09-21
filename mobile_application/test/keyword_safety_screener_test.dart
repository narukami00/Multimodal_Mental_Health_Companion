import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/safety_assessment.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  const screener = KeywordSafetyScreener();

  test('clear text remains clear', () {
    expect(screener.assess('The morning felt manageable.').level, SafetyLevel.clear);
  });

  test('urgent phrases take the highest-priority support path', () {
    final assessment = screener.assess('I want to die and I do not feel safe with myself.');

    expect(assessment.level, SafetyLevel.urgentSupport);
    expect(assessment.matchedSignals, contains('want to die'));
  });

  test('support language is surfaced without an urgent classification', () {
    final assessment = screener.assess('I feel completely overwhelmed today.');

    expect(assessment.level, SafetyLevel.supportSuggested);
    expect(assessment.matchedSignals, contains('completely overwhelmed'));
  });
}
