import '../../core/models/activity.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/models/user_profile.dart';
import 'activity_safety_policy.dart';

class RecommendationContext {
  const RecommendationContext({
    this.currentState,
    this.eventTags = const [],
    this.safetyActive = false,
    this.profileAgeDays,
    this.preferGentle = false,
  });

  final String? currentState;
  final List<String> eventTags;
  final bool safetyActive;
  final int? profileAgeDays;

  /// True when the user's own baseline screening suggests offering gentler
  /// options first. Deliberately never surfaced as reasoning.
  final bool preferGentle;

  Set<String> get normalizedTags => {
    ...eventTags.map(_normalize),
    if (currentState != null) _normalize(currentState!),
  };
}

class Recommendation {
  const Recommendation({
    required this.activity,
    required this.confidence,
    required this.isProactive,
    required this.explanation,
  });

  final Activity activity;
  final double confidence;
  final bool isProactive;
  final String explanation;
}

class RecommendationEngine {
  const RecommendationEngine();

  Recommendation? choose({
    required Iterable<Activity> activities,
    required UserProfile profile,
    required RecommendationContext context,
    required Iterable<SuggestionRecord> history,
    DateTime? now,
    bool userInitiated = false,
  }) {
    if (context.safetyActive) return null;

    final currentTime = now ?? DateTime.now();
    final records = history.toList(growable: false);
    final dailyCap =
        context.profileAgeDays != null && context.profileAgeDays! < 14 ? 1 : 2;
    if (!userInitiated && _shownToday(records, currentTime) >= dailyCap) {
      return null;
    }

    final tags = context.normalizedTags;
    final candidates = activities
        .where((activity) => activity.review.isApprovedForPrototype)
        .where(ActivitySafetyPolicy.isAllowed)
        .where((activity) => !_isNeverSuggested(activity, profile))
        .where((activity) => !_isCoolingDown(activity, records, currentTime))
        .map(
          (activity) => _ScoredActivity(
            activity: activity,
            score: _score(activity, tags, records),
            confidence: _confidence(activity, tags, records),
            contextMatches: _contextMatches(activity, tags),
          ),
        )
        .toList();

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      return scoreCompare == 0
          ? a.activity.id.compareTo(b.activity.id)
          : scoreCompare;
    });

    final selected = candidates.first;
    return Recommendation(
      activity: selected.activity,
      confidence: selected.confidence,
      isProactive: selected.confidence >= 0.6 && selected.contextMatches > 0,
      explanation: _explanation(
        selected.activity,
        context,
        selected.contextMatches,
      ),
    );
  }

  int _shownToday(List<SuggestionRecord> records, DateTime now) {
    return records.where((record) => _sameDate(record.shownAt, now)).length;
  }

  bool _isCoolingDown(
    Activity activity,
    List<SuggestionRecord> records,
    DateTime now,
  ) {
    final activityRecords = records.where(
      (record) => record.activityId == activity.id,
    );
    if (activityRecords.isEmpty) return false;
    final latest = activityRecords.reduce(
      (a, b) => a.shownAt.isAfter(b.shownAt) ? a : b,
    );
    final cooldown = latest.status == SuggestionStatus.completed
        ? const Duration(days: 2)
        : const Duration(days: 1);
    return now.isBefore(latest.shownAt.add(cooldown));
  }

  double _confidence(
    Activity activity,
    Set<String> contextTags,
    List<SuggestionRecord> records,
  ) {
    // Only records where the user actually decided something count toward
    // confidence. A suggestion that was merely shown, and then abandoned, is
    // not a decision; and "not now" is explicitly free, so it must not lower
    // this activity's standing. "Not for me" and "too hard" stay negative,
    // because those are real answers.
    final similar = records.where((record) {
      if (record.activityId != activity.id) return false;
      if (record.status == SuggestionStatus.shown) return false;
      if (record.status == SuggestionStatus.skipped &&
          record.skipReason == SuggestionSkipReason.notNow) {
        return false;
      }
      return record.contextTags
          .map(_normalize)
          .toSet()
          .intersection(contextTags)
          .isNotEmpty;
    }).toList();
    if (similar.isEmpty) return 0;

    final successful = similar
        .where(
          (record) =>
              record.status == SuggestionStatus.completed ||
              (record.rating ?? 0) >= 4,
        )
        .length;
    final consistency = successful / similar.length;
    return (similar.length / 5 * consistency).clamp(0, 1).toDouble();
  }

  double _score(
    Activity activity,
    Set<String> contextTags,
    List<SuggestionRecord> records,
  ) {
    final matches = _contextMatches(activity, contextTags);
    return matches * 2 + _confidence(activity, contextTags, records) * 4;
  }

  int _contextMatches(Activity activity, Set<String> contextTags) {
    final activityTags = {
      ...activity.contexts.map(_normalize),
      ...activity.targetStates.map(_normalize),
    };
    return activityTags.intersection(contextTags).length;
  }

  bool _isNeverSuggested(Activity activity, UserProfile profile) {
    final never = profile.neverSuggest.map(_normalize).toSet();
    final type = _normalize(activity.type.name);
    final aliases = {
      type,
      _normalize(activity.title),
      if (type == 'movement') 'exercise',
      if (type == 'mindfulness') 'breathing exercises',
      if (type == 'social') 'social activities',
    };
    return aliases.any(never.contains);
  }

  String _explanation(
    Activity activity,
    RecommendationContext context,
    int contextMatches,
  ) {
    if (contextMatches > 0 && context.currentState != null) {
      return 'A small option that fits your ${context.currentState} moment.';
    }
    if (context.eventTags.isNotEmpty) {
      return 'A small option shaped by what you have been noticing.';
    }
    return 'A low-pressure option from your reviewed library.';
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _ScoredActivity {
  const _ScoredActivity({
    required this.activity,
    required this.score,
    required this.confidence,
    required this.contextMatches,
  });

  final Activity activity;
  final double score;
  final double confidence;
  final int contextMatches;
}

String _normalize(String value) => value.trim().toLowerCase();
