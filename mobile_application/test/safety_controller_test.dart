import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/safety_assessment.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  test('non-clear text is recorded and can be marked handled', () async {
    final controller = SafetyController(
      screener: const KeywordSafetyScreener(),
      repository: InMemorySafetyEventRepository(),
    );

    final assessment = await controller.assessText(
      source: 'text_check_in',
      text: 'I feel completely overwhelmed.',
    );

    expect(assessment.level, SafetyLevel.supportSuggested);
    expect(controller.hasActiveFlag, isTrue);
    expect(controller.latestEvent?.source, 'text_check_in');

    await controller.markSupportShown();

    expect(controller.hasActiveFlag, isFalse);
    expect(controller.latestEvent?.handledBy, 'support_resources');
  });
}
