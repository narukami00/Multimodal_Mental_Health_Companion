import '../../core/models/safety_assessment.dart';
import '../../core/models/session_input.dart';
import '../../domain/rhythm/quick_reply.dart';
import '../safety/safety_controller.dart';
import '../sessions/session_controller.dart';

/// Saves check-ins that were typed outside the app (the reminder's reply box, the home-screen pop-up) as
/// ordinary text check-ins, dated when they were written.
///
/// They go through the same safety check as every other typed word. The person already wrote and sent them, so
/// the entry is always kept; if the words call for support, that is offered right after, never instead.
class QuickReplyImporter {
  QuickReplyImporter({
    required this.drain,
    required this.safety,
    required this.sessions,
    required this.showSupport,
  });

  /// Takes the waiting replies out of the inbox.
  final Future<List<QuickReply>> Function() drain;
  final SafetyController safety;
  final SessionController sessions;

  /// Offers the support screen for words that call for it. Only one is shown per run, for the most serious.
  final Future<void> Function(SafetyAssessment assessment) showSupport;

  bool _running = false;

  /// Returns how many check-ins were saved.
  Future<int> run() async {
    if (_running) return 0;
    _running = true;
    try {
      final replies = await drain();
      SafetyAssessment? worst;
      var saved = 0;
      for (final reply in replies) {
        final assessment = await safety.assessText(source: 'quick_reply', text: reply.text);
        await sessions.saveSession(mode: CaptureMode.text, text: reply.text, at: reply.at);
        saved++;
        if (assessment.level != SafetyLevel.clear && (worst == null || assessment.level.index > worst.level.index)) {
          worst = assessment;
        }
      }
      if (worst != null) await showSupport(worst);
      return saved;
    } finally {
      _running = false;
    }
  }
}
