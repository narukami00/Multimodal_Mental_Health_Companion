import '../../core/models/emotion_result.dart';
import '../../core/models/session_input.dart';
import '../../data/contracts/provider_contracts.dart';
import '../../services/journal_analysis_client.dart';

/// The real emotion reading for typed check-ins and journal entries: the words
/// are sent to the companion server, and what comes back is the model's own
/// reading. Replaces the mock that returned the same made-up answer every time.
///
/// It never invents an answer: without the person's emotion consent, with no
/// text, or when the server cannot be reached or has no model running, the
/// result is simply empty and the entry is saved without an analysis.
class ServerEmotionAnalyzer implements EmotionAnalyzer {
  ServerEmotionAnalyzer({
    required this.client,
    required this.consentGranted,
  });

  final JournalAnalysisClient client;

  /// Whether the person agreed to their entries being read for emotion (the voice-and-text consent).
  final bool Function() consentGranted;

  @override
  Future<List<EmotionResult>> analyze(SessionInput input) async {
    final text = input.text?.trim() ?? '';
    if (text.isEmpty || !consentGranted()) return const [];
    final analysis = await client.analyzeText(input.sessionId, text);
    if (analysis == null) return const [];
    return analysis.toResults(sessionId: input.sessionId);
  }
}
