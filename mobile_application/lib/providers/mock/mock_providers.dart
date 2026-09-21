import '../../core/models/emotion_result.dart';
import '../../core/models/footprint_daily_summary.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/models/session_input.dart';
import '../../data/contracts/provider_contracts.dart';

class MockEmotionAnalyzer implements EmotionAnalyzer {
  const MockEmotionAnalyzer();

  @override
  Future<List<EmotionResult>> analyze(SessionInput input) async {
    final modality = switch (input.mode) {
      CaptureMode.text => EmotionModality.text,
      CaptureMode.voice => EmotionModality.voice,
      CaptureMode.video => EmotionModality.face,
    };

    return [
      EmotionResult(
        sessionId: input.sessionId,
        modality: modality,
        timestamp: DateTime.now(),
        valence: 0.25,
        arousal: 0.32,
        labels: const [EmotionLabel(label: 'steady', score: 0.68)],
        confidence: 0.68,
        modelVersion: 'mock-v1',
      ),
    ];
  }
}

class MockLlmProvider implements LlmProvider {
  const MockLlmProvider();

  @override
  Future<String> generateReply({
    required String prompt,
    List<String> context = const [],
  }) async {
    return 'I am here with you. We can take this one moment at a time.';
  }
}

class MockSttProvider implements SttProvider {
  const MockSttProvider();

  @override
  Future<String?> transcribe(String audioPath) async => null;
}

class MockTtsProvider implements TtsProvider {
  const MockTtsProvider();

  @override
  Future<void> speak(String text) async {}
}

class MockFootprintProvider implements FootprintProvider {
  const MockFootprintProvider();

  @override
  Future<FootprintDailySummary?> readToday() async => null;
}

class PassThroughSafetyScreener implements SafetyScreener {
  const PassThroughSafetyScreener();

  @override
  SafetyAssessment assess(String text) => const SafetyAssessment.clear();
}

class MockProviders {
  const MockProviders({
    required this.emotionAnalyzer,
    required this.llmProvider,
    required this.sttProvider,
    required this.ttsProvider,
    required this.footprintProvider,
    required this.safetyScreener,
  });

  factory MockProviders.defaults() {
    return const MockProviders(
      emotionAnalyzer: MockEmotionAnalyzer(),
      llmProvider: MockLlmProvider(),
      sttProvider: MockSttProvider(),
      ttsProvider: MockTtsProvider(),
      footprintProvider: MockFootprintProvider(),
      safetyScreener: PassThroughSafetyScreener(),
    );
  }

  final EmotionAnalyzer emotionAnalyzer;
  final LlmProvider llmProvider;
  final SttProvider sttProvider;
  final TtsProvider ttsProvider;
  final FootprintProvider footprintProvider;
  final SafetyScreener safetyScreener;
}
