import '../../core/models/consent.dart';
import '../../core/models/session_record.dart';
import '../../domain/capacity/capacity_estimator.dart';
import '../../domain/capacity/mood_trend.dart';
import '../../domain/memory/profile_snippet_builder.dart';
import '../consent/consent_controller.dart';
import '../profile/profile_controller.dart';
import '../suggestions/suggestion_context.dart';
import 'moments_controller.dart';

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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ConsentController consent;
  final ProfileController profile;
  final MomentsController moments;

  /// The person's check-ins, newest first.
  final List<SessionRecord> Function() sessions;

  /// Themes they chose recently, in their own words.
  final List<String> Function() themes;
  final DateTime Function() _clock;

  bool get snippetOn => consent.isGranted(ConsentKey.profileSnippet);
  bool get momentsOn => consent.isGranted(ConsentKey.memoryMoments);

  /// The short description of the person, empty without consent.
  ProfileSnippet snippet() {
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
    return buildProfileSnippet(
      consented: snippetOn,
      profile: profile.profile,
      capacity: capacity,
      recentMoodScores: dailyMoodScores(sessions: all, now: now, days: 7),
      recentThemes: themes(),
    );
  }

  /// The confirmed moments Sol may be told, empty without consent.
  List<String> momentLines() => momentsOn
      ? [for (final m in moments.forSol) m.text]
      : const [];

  /// The block sent to the server, or null when there is nothing to send.
  Map<String, Object?>? payload() {
    final snippet = this.snippet();
    final lines = momentLines();
    if (snippet.isEmpty && lines.isEmpty) return null;
    return {
      'v': ProfileSnippet.version,
      if (!snippet.isEmpty) 'profile_snippet': snippet.text,
      if (lines.isNotEmpty) 'memory_facts': lines,
    };
  }
}
