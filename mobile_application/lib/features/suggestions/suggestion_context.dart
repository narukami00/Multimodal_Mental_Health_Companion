import '../../core/models/session_record.dart';
import '../../core/research/ablations.dart';
import '../../core/models/user_profile.dart';
import '../../domain/capacity/capacity_estimator.dart';
import '../../domain/capacity/mood_trend.dart';
import '../../domain/recommendations/event_tagging.dart';
import '../../domain/profile/quiz_bank.dart';
import '../../domain/recommendations/mood_change.dart';
import '../../domain/recommendations/recommendation_engine.dart';

/// Builds the context a suggestion is chosen in, from what the app already
/// knows.
///
/// Everything here is derived on-device from data the user chose to give —
/// their most recent check-in, the baseline they filled in, and the sleep hours
/// they told us. No new collection, no permission, no server.
RecommendationContext buildRecommendationContext({
  required UserProfile profile,
  required List<SessionRecord> sessions,
  DateTime? now,
  List<String> extraTags = const [],
  String? moodNow,
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
    // [moodNow]: how they said they feel right now when asked directly, which is better than any check-in.
    currentState: moodNow ?? latest?.effectiveMood,
    // What they wrote about, then anything they chose themselves when asked what
    // was going on. Each once.
    eventTags: [
      ...tags,
      for (final tag in extraTags)
        if (!tags.contains(tag)) tag,
    ],
    profileAgeDays: profileAgeInDays(profile, now: current),
    preferGentle: prefersGentleStart(profile),
    capacity: !Ablations.current.capacity
        ? null
        : estimateCapacity(
            now: current,
            sleepWindow: resolveSleepWindow(profile: profile, now: current),
            // Only a check-in close enough to mean something about right now.
            latestMood: moodNow ?? moodBeforeFor(shownAt: current, sessions: sessions, window: moodContextWindow),
            recentMoodScores: dailyMoodScores(sessions: sessions, now: current),
          ),
  );
}

/// How long the app has been in use, used for the early-day suggestion cap.
int? profileAgeInDays(UserProfile profile, {DateTime? now}) {
  final started = profile.firstRunAt;
  if (started == null) return null;
  return (now ?? DateTime.now()).difference(started).inDays;
}
