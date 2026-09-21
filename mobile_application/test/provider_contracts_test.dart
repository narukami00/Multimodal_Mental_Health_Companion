import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/safety_assessment.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  test('default providers are injectable and nullable-safe', () async {
    final providers = MockProviders.defaults();
    const input = SessionInput(
      sessionId: 'session-1',
      mode: CaptureMode.text,
      text: 'A quiet check-in.',
    );

    expect(await providers.emotionAnalyzer.analyze(input), isEmpty);
    expect(
      await providers.llmProvider.generateReply(prompt: 'Say hello'),
      isNotEmpty,
    );
    expect(await providers.sttProvider.transcribe('missing-audio'), isNull);
    expect(await providers.footprintProvider.readToday(), isNull);
    expect(
      providers.safetyScreener.assess('').level,
      SafetyLevel.clear,
    );
  });
}
