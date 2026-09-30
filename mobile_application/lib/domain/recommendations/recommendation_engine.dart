import 'dart:math' as math;

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
    required this.source,
  });

  final Activity activity;
  final double confidence;
  final bool isProactive;
  final String explanation;

  /// Why this was chosen. Only [SuggestionSource.learned] means the app thinks
  /// it fits; the other two are offered because it does not know yet.
  final SuggestionSource source;
}

/// The lower bound of the Wilson score interval at z = 1.645 (one-sided 95%).
///
/// Chosen over a plain success ratio because it accounts for how little
/// evidence there is: one success out of one scores 0.27 rather than 1.0, so an
/// activity cannot be trusted on a single good day. It is kept as a pure
/// function so the curve itself can be tested against known values.
double wilsonLowerBound(double successes, double n, {double z = 1.645}) {
  if (n <= 0) return 0;
  final p = (successes / n).clamp(0.0, 1.0);
  final zSquared = z * z;
  final denominator = 1 + zSquared / n;
  final centre = p + zSquared / (2 * n);
  final spread = z * math.sqrt((p * (1 - p) + zSquared / (4 * n)) / n);
  return ((centre - spread) / denominator).clamp(0.0, 1.0);
}

class RecommendationEngine {
  const RecommendationEngine();

  /// Days of curated starter suggestions before any learned pick is offered.
  static const starterTourDays = 14;

  /// Beyond this the explore share settles at its long-run value.
  static const exploreShareSettlesAfterDays = 57;

  static const _exploreShareEarly = 0.5;
  static const _exploreShareLater = 0.3;
  static const _exploreFloor = 0.2;
  static const _exploreWindow = 10;

  /// Below this much evidence, an activity borrows from its own type.
  static const _poolingThreshold = 5.0;
  static const _poolingWeight = 0.5;

  static const _halfLifeDays = 60.0;

  /// Honest limit: at prototype volume this gate is not provably better than
  /// editorial ordering. It stops thin evidence from being presented as a
  /// personal fit, and it is deliberately the only claim the app makes.
  static const _confidenceGate = 0.60;
  static const _evidenceGate = 4.0;

  static const _dismissalSuppression = Duration(hours: 12);
  static const _completionCooldown = Duration(days: 2);
  static const _firstRejectionHide = Duration(days: 30);
  static const _secondRejectionHide = Duration(days: 90);
  static const _effortCeilingWindow = Duration(days: 14);

  /// The longest an activity may be to count as a gentle starter.
  static const starterDurationCeiling = 6;

  Recommendation? choose({
    required Iterable<Activity> activities,
    required UserProfile profile,
    required RecommendationContext context,
    required Iterable<SuggestionRecord> history,
    DateTime? now,
    bool userInitiated = false,
    bool ignoreBudget = false,
  }) {
    if (context.safetyActive) return null;

    final currentTime = now ?? DateTime.now();
    final records = history.toList(growable: false);
    final library = activities.toList(growable: false);
    if (library.isEmpty) return null;

    final ageDays = context.profileAgeDays;
    final dailyCap = ageDays != null && ageDays < starterTourDays ? 1 : 2;
    if (!userInitiated &&
        !ignoreBudget &&
        _shownToday(records, currentTime) >= dailyCap) {
      return null;
    }

    final tags = context.normalizedTags;
    final typeOf = {for (final activity in library) activity.id: activity.type};
    final effortCeiling = _effortCeiling(records, context, currentTime);

    final eligible = library
        .where((activity) => activity.review.isApprovedForPrototype)
        .where(ActivitySafetyPolicy.isAllowed)
        .where((activity) => !_isNeverSuggested(activity, profile))
        .where((activity) => !_isSuppressed(activity, records, currentTime))
        .where((activity) => _withinEffort(activity, effortCeiling))
        .toList(growable: false);
    if (eligible.isEmpty) return null;

    final source = _selectSource(records, ageDays);
    final pick = switch (source) {
      SuggestionSource.starter => _starterPick(eligible, records, typeOf),
      SuggestionSource.explore => _explorePick(eligible, records),
      SuggestionSource.learned => _learnedPick(
        eligible,
        profile,
        context,
        tags,
        records,
        typeOf,
        currentTime,
      ),
    };

    // An empty learned slot falls through to an exploratory pick. Going quiet
    // to protect the gate would be worse than offering something unproven, and
    // lowering the gate to fill the slot would make it meaningless.
    final chosen = pick ?? (source == SuggestionSource.learned
        ? _explorePick(eligible, records)
        : null);
    if (chosen == null) return null;

    final resolvedSource = pick == null ? SuggestionSource.explore : source;
    final confidence = _confidence(chosen, tags, records, typeOf, currentTime);
    final matches = _contextMatches(chosen, tags);

    return Recommendation(
      activity: chosen,
      confidence: confidence,
      // Starter and explore picks are editorial, so they are safe to surface
      // unasked. A learned pick has to clear the gate first.
      isProactive: resolvedSource != SuggestionSource.learned ||
          (confidence >= _confidenceGate && matches > 0),
      explanation: _explanation(chosen, context, matches, resolvedSource),
      source: resolvedSource,
    );
  }

  SuggestionSource _selectSource(
    List<SuggestionRecord> records,
    int? ageDays,
  ) {
    if (ageDays != null && ageDays < starterTourDays) {
      return SuggestionSource.starter;
    }
    return _shouldExplore(records, ageDays)
        ? SuggestionSource.explore
        : SuggestionSource.learned;
  }

  bool _shouldExplore(List<SuggestionRecord> records, int? ageDays) {
    final recent = _recentShown(records, _exploreWindow);
    if (recent.isEmpty) return true;

    final target = (ageDays ?? 0) < exploreShareSettlesAfterDays
        ? _exploreShareEarly
        : _exploreShareLater;
    final exploreCount = recent
        .where((record) => record.source == SuggestionSource.explore)
        .length;
    final share = exploreCount / recent.length;

    // The floor guarantees a minimum share of unfamiliar options even if the
    // target is later tuned down.
    if (share < _exploreFloor) return true;
    return share < target;
  }

  List<SuggestionRecord> _recentShown(List<SuggestionRecord> records, int take) {
    final shown = records.toList()..sort((a, b) => b.shownAt.compareTo(a.shownAt));
    return shown.take(take).toList(growable: false);
  }

  Activity? _starterPick(
    List<Activity> eligible,
    List<SuggestionRecord> records,
    Map<String, ActivityType> typeOf,
  ) {
    final starterCandidates = eligible
        .where(isStarterCandidate)
        .toList(growable: false);
    // If nothing in the library is short and gentle enough, offer the gentlest
    // eligible option rather than going silent for the whole tour.
    if (starterCandidates.isEmpty) return _leastExposed(eligible, records);

    final previousType = _lastSuggestedType(records, typeOf);
    final varied = starterCandidates
        .where((activity) => activity.type != previousType)
        .toList(growable: false);
    // If the only starter options are the type just shown, show the type again
    // rather than going silent.
    return _leastExposed(
      varied.isEmpty ? starterCandidates : varied,
      records,
    );
  }

  Activity? _explorePick(List<Activity> eligible, List<SuggestionRecord> records) {
    final gentle = eligible
        .where((activity) => activity.effort == ActivityEffort.low)
        .toList(growable: false);
    // The gentle tier is where unfamiliar options are offered from. If it is
    // empty, offer the least-exposed eligible option instead of nothing.
    return _leastExposed(gentle.isEmpty ? eligible : gentle, records);
  }

  Activity? _learnedPick(
    List<Activity> eligible,
    UserProfile profile,
    RecommendationContext context,
    Set<String> tags,
    List<SuggestionRecord> records,
    Map<String, ActivityType> typeOf,
    DateTime now,
  ) {
    final passing = <_ScoredActivity>[];
    for (final activity in eligible) {
      final confidence = _confidence(activity, tags, records, typeOf, now);
      final evidence = _evidence(activity, tags, records, typeOf, now).n;
      if (confidence < _confidenceGate || evidence < _evidenceGate) continue;
      passing.add(
        _ScoredActivity(
          activity: activity,
          score: _score(activity, profile, context, tags, confidence),
          confidence: confidence,
          contextMatches: _contextMatches(activity, tags),
        ),
      );
    }
    if (passing.isEmpty) return null;

    passing.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore == 0 ? a.activity.id.compareTo(b.activity.id) : byScore;
    });
    return passing.first.activity;
  }

  Activity? _leastExposed(
    List<Activity> pool,
    List<SuggestionRecord> records,
  ) {
    if (pool.isEmpty) return null;
    Activity? best;
    var bestExposure = 1 << 30;
    for (final activity in pool) {
      final exposure = _exposureCount(activity, records);
      final better = exposure < bestExposure ||
          (exposure == bestExposure &&
              best != null &&
              activity.id.compareTo(best.id) < 0);
      if (best == null || better) {
        best = activity;
        bestExposure = exposure;
      }
    }
    return best;
  }

  /// How often the user actually saw this activity.
  ///
  /// A card declined with "not now" was never really considered, so it does not
  /// count as exposure and stays eligible for the tour.
  int _exposureCount(Activity activity, List<SuggestionRecord> records) {
    return records.where((record) {
      if (record.activityId != activity.id) return false;
      if (record.status == SuggestionStatus.skipped &&
          record.skipReason == SuggestionSkipReason.notNow) {
        return false;
      }
      return true;
    }).length;
  }

  ActivityType? _lastSuggestedType(
    List<SuggestionRecord> records,
    Map<String, ActivityType> typeOf,
  ) {
    if (records.isEmpty) return null;
    final latest = records.reduce(
      (a, b) => a.shownAt.isAfter(b.shownAt) ? a : b,
    );
    return typeOf[latest.activityId];
  }

  int _shownToday(List<SuggestionRecord> records, DateTime now) {
    // Only proactive nudges count against the daily cap. A suggestion the user
    // went and asked for themselves is not a nudge and must never use up the
    // slot for one — otherwise viewing an idea on the You page would silence
    // the Home card for the rest of the day.
    return records
        .where((record) => record.proactive)
        .where((record) => _sameDate(record.shownAt, now))
        .length;
  }

  /// Whether this activity was shown too recently to show again.
  ///
  /// Suppression is measured as a duration rather than "until the end of the
  /// day", so an activity declined at 23:50 is not offered again at 00:05.
  bool _isSuppressed(
    Activity activity,
    List<SuggestionRecord> records,
    DateTime now,
  ) {
    if (_isShelved(activity, records)) return true;
    return _suppressionUntil(activity, records, now) != null;
  }

  /// Three refusals take an activity out of the library for good.
  ///
  /// Repeating an offer someone has turned down three times is not persistence,
  /// it is not listening.
  bool _isShelved(Activity activity, List<SuggestionRecord> records) {
    return _rejections(activity, records).length >= 3;
  }

  List<SuggestionRecord> _rejections(
    Activity activity,
    List<SuggestionRecord> records,
  ) {
    return records
        .where(
          (record) =>
              record.activityId == activity.id &&
              record.status == SuggestionStatus.skipped &&
              record.skipReason == SuggestionSkipReason.notForMe,
        )
        .toList(growable: false);
  }

  DateTime? _suppressionUntil(
    Activity activity,
    List<SuggestionRecord> records,
    DateTime now,
  ) {
    // A repeated "not for me" hides an activity for longer each time: a month,
    // then a season. The third refusal shelves it outright.
    final rejections = _rejections(activity, records);
    if (rejections.isNotEmpty) {
      final latestRejection = rejections.reduce(
        (a, b) => a.shownAt.isAfter(b.shownAt) ? a : b,
      );
      final hideFor = rejections.length >= 2
          ? _secondRejectionHide
          : _firstRejectionHide;
      final until = latestRejection.shownAt.add(hideFor);
      if (now.isBefore(until)) return until;
    }

    final activityRecords = records.where(
      (record) => record.activityId == activity.id,
    );
    if (activityRecords.isEmpty) return null;
    final latest = activityRecords.reduce(
      (a, b) => a.shownAt.isAfter(b.shownAt) ? a : b,
    );
    final window = _didIt(latest) == true
        ? _completionCooldown
        : _dismissalSuppression;
    final until = latest.shownAt.add(window);
    return now.isBefore(until) ? until : null;
  }

  ActivityEffort _effortCeiling(
    List<SuggestionRecord> records,
    RecommendationContext context,
    DateTime now,
  ) {
    final tooHardRecently = records.any(
      (record) =>
          record.status == SuggestionStatus.skipped &&
          record.skipReason == SuggestionSkipReason.tooHard &&
          now.difference(record.shownAt) < _effortCeilingWindow,
    );
    if (tooHardRecently || context.preferGentle) return ActivityEffort.low;
    return ActivityEffort.high;
  }

  bool _withinEffort(Activity activity, ActivityEffort ceiling) {
    return activity.effort.index <= ceiling.index;
  }

  double _confidence(
    Activity activity,
    Set<String> contextTags,
    List<SuggestionRecord> records,
    Map<String, ActivityType> typeOf,
    DateTime now,
  ) {
    final evidence = _evidence(activity, contextTags, records, typeOf, now);
    return wilsonLowerBound(evidence.successes, evidence.n);
  }

  /// Weighted outcome totals for one activity, plus its type when thin.
  ///
  /// Pooling matters because a single activity rarely accumulates enough
  /// outcomes to judge on its own. Below the threshold it borrows from other
  /// activities of the same type in the same context, at half weight, so a
  /// borrowed conclusion can never outweigh a first-hand one.
  ({double successes, double n}) _evidence(
    Activity activity,
    Set<String> contextTags,
    List<SuggestionRecord> records,
    Map<String, ActivityType> typeOf,
    DateTime now,
  ) {
    var ownSuccesses = 0.0;
    var ownN = 0.0;
    var typeSuccesses = 0.0;
    var typeN = 0.0;

    for (final record in records) {
      final outcome = _outcome(record);
      if (outcome == null) continue;
      if (!_sharesContext(record, contextTags)) continue;

      final decay = _decay(record.shownAt, now);
      final weight = outcome.weight * decay;
      if (record.activityId == activity.id) {
        ownSuccesses += outcome.value * weight;
        ownN += weight;
      } else if (typeOf[record.activityId] == activity.type) {
        typeSuccesses += outcome.value * weight;
        typeN += weight;
      }
    }

    if (ownN >= _poolingThreshold) {
      return (successes: ownSuccesses, n: ownN);
    }
    return (
      successes: ownSuccesses + typeSuccesses * _poolingWeight,
      n: ownN + typeN * _poolingWeight,
    );
  }

  /// Recency weight, halving every 60 days.
  double _decay(DateTime shownAt, DateTime now) {
    final ageDays = now.difference(shownAt).inMinutes / (60 * 24);
    if (ageDays <= 0) return 1;
    return math.pow(0.5, ageDays / _halfLifeDays).toDouble();
  }

  bool _sharesContext(SuggestionRecord record, Set<String> contextTags) {
    return record.contextTags
        .map(_normalize)
        .toSet()
        .intersection(contextTags)
        .isNotEmpty;
  }

  /// What a record says about whether this activity helped, if anything.
  ///
  /// Returns null for records that carry no verdict: a card merely shown and
  /// abandoned, an explicit "not now", and "too hard" — which is about the
  /// effort of the moment, not about whether it helps.
  ({double value, double weight})? _outcome(SuggestionRecord record) {
    final didIt = _didIt(record);
    final useful = record.useful ?? _usefulnessFromRating(record.rating);

    if (useful == SuggestionUsefulness.up) {
      return (value: 1, weight: didIt == true ? 1.0 : 0.5);
    }
    if (useful == SuggestionUsefulness.down) {
      return (value: 0, weight: didIt == true ? 1.0 : 0.5);
    }
    // Did it, but did not say how it went: counted, at reduced weight.
    if (didIt == true) return (value: 0.6, weight: 0.5);
    if (record.status == SuggestionStatus.skipped &&
        record.skipReason == SuggestionSkipReason.notForMe) {
      return (value: 0, weight: 1.0);
    }
    return null;
  }

  bool? _didIt(SuggestionRecord record) {
    if (record.done != null) return record.done;
    // Records written before `done` existed: the old flow only wrote
    // SuggestionStatus.completed when the user marked it complete, so reading
    // that as a completion is a faithful migration rather than a guess.
    if (record.status == SuggestionStatus.completed) return true;
    return null;
  }

  SuggestionUsefulness? _usefulnessFromRating(int? rating) {
    if (rating == null) return null;
    if (rating >= 4) return SuggestionUsefulness.up;
    if (rating <= 2) return SuggestionUsefulness.down;
    // Three stars is neutral and is not treated as either verdict.
    return null;
  }

  double _score(
    Activity activity,
    UserProfile profile,
    RecommendationContext context,
    Set<String> contextTags,
    double confidence,
  ) {
    var score = _contextMatches(activity, contextTags) * 2 + confidence * 4;

    final preferred = profile.preferredActivities
        .map(_normalize)
        .toSet();
    if (preferred.contains(_normalize(activity.type.name))) score += 2;

    if (context.preferGentle && activity.effort == ActivityEffort.low) {
      score += 1;
    }

    // profile.constraints is deliberately not interpreted here. The values are
    // things like "quiet at home", which cannot be matched against a library
    // field without inventing a meaning they do not have.
    return score;
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
    SuggestionSource source,
  ) {
    switch (source) {
      case SuggestionSource.starter:
        return "A gentle starter idea, since we're just getting to know what fits you.";
      case SuggestionSource.explore:
        return "Something we haven't tried together yet.";
      case SuggestionSource.learned:
        if (contextMatches > 0 && context.currentState != null) {
          return 'A small option that fits your ${context.currentState} moment.';
        }
        return 'A small option that has been worth trying before.';
    }
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

/// Whether an activity is gentle and short enough for the starter tour.
///
/// Public, because the content check is written against this rather than a copy
/// of it. The pool is derived from effort and duration rather than a
/// hand-maintained list, so it cannot fall out of step with the library — and
/// neither can the check that guards it.
bool isStarterCandidate(Activity activity) {
  return activity.effort == ActivityEffort.low &&
      activity.durationMinutes <= RecommendationEngine.starterDurationCeiling;
}
