import '../../core/models/session_record.dart';
import '../../core/models/user_profile.dart';
import '../../domain/recommendations/event_tagging.dart';
import '../../domain/recommendations/recommendation_engine.dart';
import '../profile/quiz_questions.dart';

/// Builds the context a suggestion is chosen in, from what the app already
/// knows.
///
/// Everything here is derived on-device from data the user chose to give —
/// their most recent check-in, and the baseline they filled in. No new
/// collection, no permission, no server.
RecommendationContext buildRecommendationContext({
  required UserProfile profile,
  required List<SessionRecord> sessions,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  // Sessions arrive newest first.
  final latest = sessions.isEmpty ? null : sessions.first;

  final text = latest?.text?.trim();
  final tags = text == null || text.isEmpty
      ? const <String>[]
      : const EventTaggingService()
          .extractKnownTags(text)
          .map((tag) => tag.canonicalLabel)
          .toList();

  return RecommendationContext(
    currentState: latest?.mood,
    eventTags: tags,
    profileAgeDays: profileAgeInDays(profile, now: current),
    preferGentle: prefersGentleStart(profile),
  );
}

/// How long the app has been in use, used for the early-day suggestion cap.
int? profileAgeInDays(UserProfile profile, {DateTime? now}) {
  final started = profile.firstRunAt;
  if (started == null) return null;
  return (now ?? DateTime.now()).difference(started).inDays;
}

/// Whether the user's own baseline screening suggests starting gently.
///
/// This is an effort preference, not a clinical judgement: it only softens
/// which options are offered first, and it is never shown to the user as
/// reasoning. A score at or above the conventional moderate threshold on
/// either instrument is the trigger.
bool prefersGentleStart(UserProfile profile) {
  final anxiety = scoreFor(profile, QuizBlock.gad7);
  final lowMood = scoreFor(profile, QuizBlock.phq9);
  const moderateThreshold = 10;
  return (anxiety != null && anxiety >= moderateThreshold) ||
      (lowMood != null && lowMood >= moderateThreshold);
}
