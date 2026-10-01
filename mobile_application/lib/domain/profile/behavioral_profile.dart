import '../../core/day_key.dart';
import '../../core/models/activity.dart';
import '../../core/models/session_record.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/models/user_profile.dart';
import '../recommendations/recommendation_engine.dart';
import 'quiz_bank.dart';

/// Everything the "How Solace decides" page shows, computed once.
///
/// Pure function of the state passed in: no I/O, no clock reads beyond the
/// injected [now]. The page renders it; nothing on the page reasons about raw
/// records, so the page can never quietly disagree with the engine about what
/// the user's behavior has been.
///
/// [context] must be the same context the engine is being fed — the page
/// describes the standing the picker actually has, which is why evidence and
/// confidence here move with the latest check-in exactly as they do for the
/// next suggestion.
class BehavioralProfile {
  const BehavioralProfile({
    required this.preferences,
    required this.baseline,
    required this.typeAcceptance,
    required this.engineState,
    required this.momentum,
    required this.shelvedActivities,
    required this.neverSuggestedTypes,
    required this.totalAccepted,
    required this.totalAnswered,
  });

  factory BehavioralProfile.compute({
    required UserProfile profile,
    required List<SessionRecord> sessions,
    required List<SuggestionRecord> suggestionHistory,
    required List<Activity> library,
    required RecommendationContext context,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();

    final standings = const RecommendationEngine().standingOf(
      activities: library,
      profile: profile,
      context: context,
      history: suggestionHistory,
      now: currentTime,
    );

    return BehavioralProfile(
      preferences: PreferenceSnapshot.of(profile),
      baseline: BaselineSnapshot.of(profile),
      typeAcceptance: _typeAcceptance(suggestionHistory, library),
      engineState: EngineState.of(
        profile: profile,
        history: suggestionHistory,
        standings: standings,
        now: currentTime,
      ),
      momentum: MomentumSnapshot.of(
        profile: profile,
        sessions: sessions,
        now: currentTime,
      ),
      shelvedActivities: [
        for (final standing in standings)
          if (standing.shelved) standing.activity,
      ],
      neverSuggestedTypes: _neverSuggestedTypes(profile, library),
      totalAccepted: suggestionHistory.where((record) => _didIt(record)).length,
      totalAnswered: suggestionHistory.where(_hasVerdict).length,
    );
  }

  /// What the user picked in the onboarding preferences step.
  final PreferenceSnapshot preferences;

  /// How the baseline reflections went, and what they currently cause.
  final BaselineSnapshot baseline;

  /// Acceptance statistics per activity type, from real decisions.
  final Map<ActivityType, TypeAcceptance> typeAcceptance;

  /// Where the recommendation engine currently stands for this user.
  final EngineState engineState;

  /// Check-in and rest rhythm over the last two weeks.
  final MomentumSnapshot momentum;

  /// Activities turned down three times: out of rotation entirely.
  final List<Activity> shelvedActivities;

  /// Types the user asked never to see, as they are actually enforced.
  final List<String> neverSuggestedTypes;

  /// Suggestions the user said they did.
  final int totalAccepted;

  /// Suggestions with an actual verdict, completed or declined.
  final int totalAnswered;

  /// Whether the user said they did the activity, per the engine's reading.
  static bool _didIt(SuggestionRecord record) {
    if (record.done != null) return record.done!;
    return record.status == SuggestionStatus.completed;
  }

  /// Decisions with an actual verdict: completed, or declined as not-for-me /
  /// too-hard. "Not now" and ignored records carry no verdict and are excluded,
  /// matching how the engine reads them.
  static bool _hasVerdict(SuggestionRecord record) {
    if (_didIt(record)) return true;
    if (record.status == SuggestionStatus.skipped) {
      return record.skipReason == SuggestionSkipReason.notForMe ||
          record.skipReason == SuggestionSkipReason.tooHard;
    }
    return false;
  }

  static Map<ActivityType, TypeAcceptance> _typeAcceptance(
    List<SuggestionRecord> history,
    List<Activity> library,
  ) {
    final typeOf = {for (final activity in library) activity.id: activity.type};
    final stats = <ActivityType, _MutableTypeStats>{};
    for (final record in history) {
      final type = typeOf[record.activityId];
      if (type == null) continue;
      final stat = stats.putIfAbsent(type, _MutableTypeStats.new);
      if (_didIt(record)) stat.completed++;
      if (record.status == SuggestionStatus.skipped) {
        if (record.skipReason == SuggestionSkipReason.notForMe ||
            record.skipReason == SuggestionSkipReason.tooHard) {
          stat.declined++;
        } else if (record.skipReason == SuggestionSkipReason.notNow) {
          stat.notNow++;
        }
      }
      switch (record.useful) {
        case SuggestionUsefulness.up:
          stat.usefulUp++;
        case SuggestionUsefulness.down:
          stat.usefulDown++;
        case null:
          break;
      }
      stat.shown++;
    }
    return {for (final entry in stats.entries) entry.key: entry.value.snapshot()};
  }

  static List<String> _neverSuggestedTypes(
    UserProfile profile,
    List<Activity> library,
  ) {
    final never = profile.neverSuggest
        .map((value) => value.trim().toLowerCase())
        .toSet();
    final matched = <String>{};
    for (final activity in library) {
      final type = activity.type.name.toLowerCase();
      final aliases = {
        type,
        activity.title.trim().toLowerCase(),
        if (type == 'movement') 'exercise',
        if (type == 'mindfulness') 'breathing exercises',
        if (type == 'social') 'social activities',
      };
      if (aliases.any(never.contains)) matched.add(activity.type.name);
    }
    return matched.toList()..sort();
  }
}

/// What the user told the onboarding preferences step, verbatim.
class PreferenceSnapshot {
  const PreferenceSnapshot({
    required this.preferredActivities,
    required this.constraints,
    required this.interactionPreferences,
    required this.neverSuggest,
    required this.completed,
  });

  factory PreferenceSnapshot.of(UserProfile profile) {
    return PreferenceSnapshot(
      preferredActivities: List.unmodifiable(profile.preferredActivities),
      constraints: List.unmodifiable(profile.constraints),
      interactionPreferences: List.unmodifiable(profile.interactionPreferences),
      neverSuggest: List.unmodifiable(profile.neverSuggest),
      completed: profile.preferencesCompleted,
    );
  }

  final List<String> preferredActivities;
  final List<String> constraints;
  final List<String> interactionPreferences;
  final List<String> neverSuggest;
  final bool completed;
}

/// The baseline reflections and what the app does because of them.
class BaselineSnapshot {
  const BaselineSnapshot({required this.blocks, required this.preferGentle});

  factory BaselineSnapshot.of(UserProfile profile) {
    return BaselineSnapshot(
      blocks: [
        BaselineBlock.of(QuizBlock.erqS, profile),
        BaselineBlock.of(QuizBlock.gad7, profile),
        BaselineBlock.of(QuizBlock.phq9, profile),
      ],
      preferGentle: prefersGentleStart(profile),
    );
  }

  /// One row per instrument: Handling emotions, Worry, Mood.
  final List<BaselineBlock> blocks;

  /// Whether the app is offering gentler options first because of these
  /// scores. Deliberately phrased as an effort preference, never a judgement.
  final bool preferGentle;

  bool get allAnsweredOrSkipped => blocks.every(
        (block) => block.skipped || block.answeredCount == block.totalCount,
      );
}

class BaselineBlock {
  const BaselineBlock({
    required this.block,
    required this.answeredCount,
    required this.totalCount,
    required this.score,
    required this.skipped,
  });

  factory BaselineBlock.of(QuizBlock block, UserProfile profile) {
    final questions = questionsFor(block);
    final answers = answersFor(profile, block);
    final skipped = switch (block) {
      QuizBlock.erqS => profile.erqSSkipped,
      QuizBlock.gad7 => profile.gad7Skipped,
      QuizBlock.phq9 => profile.phq9Skipped,
    };
    return BaselineBlock(
      block: block,
      answeredCount: questions
          .where((question) => answers.containsKey(question.id))
          .length,
      totalCount: questions.length,
      score: scoreFor(profile, block),
      skipped: skipped,
    );
  }

  final QuizBlock block;
  final int answeredCount;
  final int totalCount;
  final int? score;
  final bool skipped;

  String get label => switch (block) {
        QuizBlock.erqS => 'Handling emotions',
        QuizBlock.gad7 => 'Worry',
        QuizBlock.phq9 => 'Mood',
      };

  /// The conventional instrument range: answers are option indexes, so the
  /// ceiling is one less than the option count, per question.
  int get maxScore => questionsFor(block).fold(
        0,
        (total, question) => total + question.options.length - 1,
      );

  String get summary {
    if (skipped) return 'Skipped by choice';
    if (score == null) return 'Not started';
    return 'Done · $score of $maxScore';
  }
}

/// Real decisions per activity type, from the suggestion history.
class TypeAcceptance {
  const TypeAcceptance({
    required this.shown,
    required this.completed,
    required this.declined,
    required this.notNow,
    required this.usefulUp,
    required this.usefulDown,
  });

  final int shown;
  final int completed;
  final int declined;

  /// Shown and dismissed with "not now": no verdict either way.
  final int notNow;
  final int usefulUp;
  final int usefulDown;

  /// Completed versus actually decided, for the honest little bar. Unanswered
  /// shows are deliberately excluded rather than read as either outcome.
  double get completionShare {
    final decided = completed + declined;
    if (decided == 0) return 0;
    return (completed / decided).clamp(0.0, 1.0);
  }

  String get subtitle {
    if (shown == 0) return 'Not offered yet';
    final decided = completed + declined;
    if (decided == 0) {
      return shown == 1
          ? 'Offered once, no answer yet'
          : 'Offered $shown times, no answer yet';
    }
    return '$completed of $decided completed';
  }
}

/// Where the recommendation engine stands right now, in the same arithmetic
/// the picker uses.
class EngineState {
  const EngineState({
    required this.profileAgeDays,
    required this.daysLeftOfStarterTour,
    required this.exploreShare,
    required this.exploreTargetShare,
    required this.effortCapped,
    required this.typesClearingGate,
    required this.hiddenCount,
  });

  factory EngineState.of({
    required UserProfile profile,
    required List<SuggestionRecord> history,
    required List<ActivityStanding> standings,
    required DateTime now,
  }) {
    final started = profile.firstRunAt;
    final ageDays = started == null ? 0 : now.difference(started).inDays;

    final recentShown = history.toList()
      ..sort((a, b) => b.shownAt.compareTo(a.shownAt));
    final recent = recentShown.take(RecommendationEngine.exploreWindow).toList();
    final exploreCount = recent
        .where((record) => record.source == SuggestionSource.explore)
        .length;
    final share = recent.isEmpty ? 0.0 : exploreCount / recent.length;
    final target = ageDays < RecommendationEngine.exploreShareSettlesAfterDays
        ? RecommendationEngine.exploreShareEarly
        : RecommendationEngine.exploreShareLater;

    // Mirrors the engine's effort ceiling: a recent "too hard" caps offers at
    // low effort for two weeks.
    final effortCapped = history.any(
      (record) =>
          record.status == SuggestionStatus.skipped &&
          record.skipReason == SuggestionSkipReason.tooHard &&
          now.difference(record.shownAt).inDays < 14,
    );

    return EngineState(
      profileAgeDays: ageDays,
      daysLeftOfStarterTour: ageDays >= RecommendationEngine.starterTourDays
          ? 0
          : RecommendationEngine.starterTourDays - ageDays,
      exploreShare: share,
      exploreTargetShare: target,
      effortCapped: effortCapped,
      typesClearingGate: ({
        for (final standing in standings)
          if (standing.clearsLearnedGate &&
              !standing.shelved &&
              !standing.hiddenByPreference)
            standing.activity.type.name,
      }).toList()
        ..sort(),
      hiddenCount: standings.where((standing) => standing.isHidden).length,
    );
  }

  /// How long the app has been in use, as the engine sees it.
  final int profileAgeDays;

  /// Days of curated starter tour remaining; zero once past it.
  final int daysLeftOfStarterTour;

  /// Explore share over the engine's own recent window, and what it aims for.
  final double exploreShare;
  final double exploreTargetShare;

  /// Whether a recent "too hard" has capped offers at gentle options.
  final bool effortCapped;

  /// Types with an idea trusted enough to be picked as a personal fit.
  final List<String> typesClearingGate;

  /// Ideas currently out of rotation by shelving or never-suggest.
  final int hiddenCount;
}

/// Check-in and rest rhythm over the last two weeks.
class MomentumSnapshot {
  const MomentumSnapshot({
    required this.checkInsLast14Days,
    required this.restDaysLast14Days,
  });

  factory MomentumSnapshot.of({
    required UserProfile profile,
    required List<SessionRecord> sessions,
    required DateTime now,
  }) {
    const window = 14;
    final checkInDays = {
      for (final session in sessions) dayKey(session.createdAt),
    };
    final restDays = profile.restDays.toSet();

    var checkIns = 0;
    var rest = 0;
    for (var i = 0; i < window; i++) {
      final key = dayKey(now.subtract(Duration(days: i)));
      if (checkInDays.contains(key)) checkIns++;
      if (restDays.contains(key)) rest++;
    }
    return MomentumSnapshot(
      checkInsLast14Days: checkIns,
      restDaysLast14Days: rest,
    );
  }

  final int checkInsLast14Days;
  final int restDaysLast14Days;
}

class _MutableTypeStats {
  int shown = 0;
  int completed = 0;
  int declined = 0;
  int notNow = 0;
  int usefulUp = 0;
  int usefulDown = 0;

  TypeAcceptance snapshot() => TypeAcceptance(
        shown: shown,
        completed: completed,
        declined: declined,
        notNow: notNow,
        usefulUp: usefulUp,
        usefulDown: usefulDown,
      );
}
