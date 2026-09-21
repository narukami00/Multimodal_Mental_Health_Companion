import '../../core/models/emotion_result.dart';
import '../../core/models/footprint_daily_summary.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/models/session_input.dart';

abstract interface class EmotionAnalyzer {
  Future<List<EmotionResult>> analyze(SessionInput input);
}

abstract interface class LlmProvider {
  Future<String> generateReply({
    required String prompt,
    List<String> context,
  });
}

abstract interface class SttProvider {
  Future<String?> transcribe(String audioPath);
}

abstract interface class TtsProvider {
  Future<void> speak(String text);
}

abstract interface class FootprintProvider {
  Future<FootprintDailySummary?> readToday();
}

abstract interface class SafetyScreener {
  SafetyAssessment assess(String text);
}
