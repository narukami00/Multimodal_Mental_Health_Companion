import '../../core/models/consent.dart';
import '../../core/models/session_record.dart';
import '../../core/research/ablations.dart';
import '../../domain/capacity/capacity_estimator.dart';
import '../../domain/capacity/mood_trend.dart';
import '../../domain/memory/profile_snippet_builder.dart';
import '../../domain/personalization/personal_calibration.dart';
import '../consent/consent_controller.dart';
import '../profile/profile_controller.dart';
import '../suggestions/suggestion_context.dart';
import 'moments_controller.dart';
import 'user_facts_controller.dart';
export 'user_facts_controller.dart' show UserFact, UserFactsController;

/// Exactly what the companion server is told about the person, and nothing else.
///
/// The "What Sol remembers" page shows [snippet] and [momentLines] from here and
/// the connection sends [payload] from here, so the preview and the wire cannot
/// drift apart. Each part needs its own consent and is empty without it.
class CompanionMemoryContext {
  CompanionMemoryContext({
    required this.consent,
    required this.profile,
    required this.moments,
    required this.sessions,
    required this.themes,
    this.userFacts,
    this.personalization,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ConsentController consent;
  final ProfileController profile;
  final MomentsController moments;
  final UserFactsController? userFacts;

  /// The person's check-ins, newest first.
  final List<SessionRecord> Function() sessions;

  /// Themes they chose recently, in their own words.
  final List<String> Function() themes;

  /// Learned on-device personalization patterns and recent life check-ins.
  final PersonalPatternProfile? Function()? personalization;
  final DateTime Function() _clock;

  bool get snippetOn =>
      Ablations.current.companionMemory &&
      consent.isGranted(ConsentKey.profileSnippet);
  bool get momentsOn =>
      Ablations.current.companionMemory &&
      consent.isGranted(ConsentKey.memoryMoments);

  /// The short description of the person, empty without consent.
  ProfileSnippet snippet() => _build(consented: snippetOn);

  /// What the snippet would say if it were turned on, for showing the person
  /// before they decide. Never sent.
  ProfileSnippet previewSnippet() => _build(consented: true);

  ProfileSnippet _build({required bool consented}) {
    final now = _clock();
    final all = sessions();
    Capacity? capacity;
    try {
      capacity = buildRecommendationContext(
        profile: profile.profile,
        sessions: all,
        now: now,
      ).capacity;
    } on Object {
      capacity = null;
    }
    final personalLines =
        personalization?.call()?.safePersonalizationPhrases(now: now) ??
            const <String>[];
    return buildProfileSnippet(
      consented: consented,
      profile: profile.profile,
      capacity: capacity,
      recentMoodScores: dailyMoodScores(sessions: all, now: now, days: 7),
      recentThemes: themes(),
      personalContextLines: personalLines,
    );
  }

  /// The confirmed moments Sol may be told, empty without consent.
  List<String> momentLines() => momentsOn ? previewMomentLines() : const [];

  /// The moments that would be told if it were turned on. Never sent.
  List<String> previewMomentLines() => [for (final m in moments.forSol) m.text];

  /// Learned identity portrait shown in "What Sol remembers".
  String previewIdentitySummary() => userFacts?.identitySummary ?? '';

  /// Learned atomic facts shown in "What Sol remembers".
  List<String> previewUserFacts() =>
      userFacts?.factLines(maxCount: 32) ?? const [];

  /// The block sent to the server, or null when there is nothing to send.
  Map<String, Object?>? payload() {
    final snippet = this.snippet();
    final forSolMoments = momentsOn ? moments.forSol : const [];
    final lines = [for (final m in forSolMoments) m.text];
    final identitySummary = snippetOn ? (userFacts?.identitySummary ?? '') : '';
    final userFactLines = snippetOn
        ? (userFacts?.factLines(maxCount: 32) ?? const <String>[])
        : const <String>[];
    final userFactRecency = snippetOn && userFactLines.isNotEmpty
        ? (userFacts?.factRecencyScores(maxCount: 32) ?? const <double>[])
        : const <double>[];
    if (snippet.isEmpty &&
        lines.isEmpty &&
        identitySummary.isEmpty &&
        userFactLines.isEmpty) {
      return null;
    }

    final pinnedCount = forSolMoments.where((m) => m.pinned).length;
    final styleNotes = snippetOn ? _styleDirective() : '';
    final copingWorked = snippetOn
        ? (personalization?.call()?.helpfulTags.take(3).toList() ?? const [])
        : const <String>[];

    return {
      'v': ProfileSnippet.version,
      if (!snippet.isEmpty) 'profile_snippet': snippet.text,
      if (lines.isNotEmpty) 'memory_facts': lines,
      if (pinnedCount > 0) 'pinned_count': pinnedCount,
      if (identitySummary.isNotEmpty) 'identity_summary': identitySummary,
      if (userFactLines.isNotEmpty) 'user_facts': userFactLines,
      if (userFactRecency.length == userFactLines.length &&
          userFactRecency.isNotEmpty)
        'user_facts_recency': userFactRecency,
      if (styleNotes.isNotEmpty) 'style_notes': styleNotes,
      if (copingWorked.isNotEmpty) 'coping_worked': copingWorked,
    };
  }

  String _styleDirective() {
    final p = profile.profile;
    final parts = <String>[];
    for (final pref in p.interactionPreferences) {
      switch (pref) {
        case 'Gentle tone':
          parts.add('keep a gentle, unhurried tone');
        case 'Direct tone':
          parts.add('be warm but clear and direct without fluff');
        case 'Quiet prompts':
          parts.add('avoid ending every reply with a question');
        case 'More context':
          parts.add('give brief context when offering an idea');
      }
    }
    for (final c in p.constraints) {
      switch (c) {
        case 'Short moments':
          parts.add('keep any idea to 1-2 minutes');
        case 'Low energy options':
          parts.add('stick to low-energy ideas');
        case 'Quiet at home':
          parts.add('prefer quiet things doable at home');
        case 'Limited mobility':
          parts.add('avoid physical exertion ideas');
      }
    }
    return parts.join('; ');
  }
}
