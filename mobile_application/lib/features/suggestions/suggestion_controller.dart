import 'package:flutter/foundation.dart';

import '../../core/models/activity.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/models/user_profile.dart';
import '../../data/contracts/activity_library_repository.dart';
import '../../data/contracts/suggestion_repository.dart';
import '../../domain/recommendations/recommendation_engine.dart';

class SuggestionController extends ChangeNotifier {
  SuggestionController({
    required ActivityLibraryRepository libraryRepository,
    required SuggestionRepository suggestionRepository,
    RecommendationEngine engine = const RecommendationEngine(),
  }) : _libraryRepository = libraryRepository,
       _suggestionRepository = suggestionRepository,
       _engine = engine;

  final ActivityLibraryRepository _libraryRepository;
  final SuggestionRepository _suggestionRepository;
  final RecommendationEngine _engine;
  List<SuggestionRecord> _history = const [];
  List<Activity> _library = const [];
  bool _isLoaded = false;
  Recommendation? _current;
  SuggestionRecord? _currentRecord;

  bool get isLoaded => _isLoaded;
  Recommendation? get current => _current;

  /// The record behind the suggestion currently on screen.
  SuggestionRecord? get currentRecord => _currentRecord;

  /// Every suggestion record, including ones that were only shown.
  ///
  /// Read-only: callers must not mutate history, and anything reasoning about
  /// what the user actually decided should filter out `shown` records.
  List<SuggestionRecord> get history => List.unmodifiable(_history);

  bool get shouldHelpMeKnowYouBetter => _rejections >= 3;
  int get _rejections => _history
      .where(
        (record) =>
            record.status == SuggestionStatus.skipped &&
            (record.skipReason == SuggestionSkipReason.notForMe ||
                record.skipReason == SuggestionSkipReason.tooHard),
      )
      .length;

  /// Whether a suggestion would be offered, without recording one.
  ///
  /// Home asks this on every rebuild, so it must leave history and the current
  /// suggestion untouched. The engine is pure, which is what makes it safe.
  /// A peek is never written down; [commit] does that, and only once the user
  /// actually responds to what they were shown.
  Recommendation? peek({
    required UserProfile profile,
    required RecommendationContext context,
    DateTime? now,
  }) {
    if (_library.isEmpty) return null;
    return _engine.choose(
      activities: _library,
      profile: profile,
      context: context,
      history: _history,
      now: now,
    );
  }

  /// Records that an idea was put in front of the user, or finds the record
  /// that already says so.
  ///
  /// Idempotent per activity and day, because Home asks again on every rebuild
  /// and the same idea must never be counted twice. It is the only write Home
  /// makes: a `shown` record carries no verdict, so it cannot move the
  /// confidence gate, but it is a real impression and counts against the budget.
  /// Proactive marks it as offered unasked, which is what the budget counts.
  Future<SuggestionRecord> commit(
    Recommendation recommendation, {
    required RecommendationContext context,
    DateTime? now,
    bool proactive = false,
  }) async {
    final shownAt = now ?? DateTime.now();
    for (final existing in _history) {
      if (existing.activityId == recommendation.activity.id &&
          existing.proactive == proactive &&
          _sameDay(existing.shownAt, shownAt)) {
        _current = recommendation;
        _currentRecord = existing;
        return existing;
      }
    }
    final record = SuggestionRecord(
      id: shownAt.microsecondsSinceEpoch.toString(),
      activityId: recommendation.activity.id,
      shownAt: shownAt,
      contextTags: [
        ...context.eventTags,
        if (context.currentState != null) context.currentState!,
      ],
      source: recommendation.source,
      proactive: proactive,
    );
    // In memory first: a second rebuild before the save returns must find this
    // record rather than write its own.
    _history = [..._history, record];
    _current = recommendation;
    _currentRecord = record;
    await _suggestionRepository.saveRecord(record);
    notifyListeners();
    return record;
  }

  /// An idea Home showed that the user has neither answered nor outlived.
  ///
  /// It keeps being offered, rather than a fresh pick, until it is answered or
  /// [expiry] passes. Expiring writes nothing: an ignored idea records no
  /// outcome, and its record has already counted against the day.
  ({SuggestionRecord record, Recommendation recommendation})? pendingProactive({
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    for (final record in _history.reversed) {
      if (!record.proactive ||
          record.status != SuggestionStatus.shown ||
          current.difference(record.shownAt) >= expiry) {
        continue;
      }
      final activity = activityFor(record.activityId);
      if (activity == null) continue;
      return (
        record: record,
        recommendation: Recommendation.restored(activity, record.source),
      );
    }
    return null;
  }

  /// How long an unanswered idea stays on Home before it quietly goes.
  static const expiry = Duration(hours: 24);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Loads the activity library ahead of the first peek.
  ///
  /// Home peeks synchronously so that a rebuild never waits on I/O, which is
  /// what this makes possible. It is called once at app start rather than from
  /// [load], because [load] runs in widget tests and an asset read never
  /// completes under fake async.
  Future<void> warmUp() async {
    _library = await _libraryRepository.load();
    notifyListeners();
  }

  Future<void> load() async {
    _history = await _suggestionRepository.listRecords();
    _isLoaded = true;
    notifyListeners();
  }

  /// The activity behind a record, if it is still in the library.
  ///
  /// Needed to name an earlier suggestion that is being rated later, since the
  /// record itself only stores an id. The library is the one cached by the most
  /// recent [suggest], so this is only populated once a suggestion has been
  /// looked up — which is always the case before anything can be rated.
  Activity? activityFor(String activityId) {
    for (final activity in _library) {
      if (activity.id == activityId) return activity;
    }
    return null;
  }

  Future<Recommendation?> suggest({
    required UserProfile profile,
    required RecommendationContext context,
    DateTime? now,
  }) async {
    if (!_isLoaded) await load();
    final activities = await _libraryRepository.load();
    _library = activities;
    final recommendation = _engine.choose(
      activities: activities,
      profile: profile,
      context: context,
      history: _history,
      now: now,
    );
    if (recommendation == null) {
      _current = null;
      _currentRecord = null;
      notifyListeners();
      return null;
    }

    final shownAt = now ?? DateTime.now();
    final record = SuggestionRecord(
      id: shownAt.microsecondsSinceEpoch.toString(),
      activityId: recommendation.activity.id,
      shownAt: shownAt,
      contextTags: [
        ...context.eventTags,
        if (context.currentState != null) context.currentState!,
      ],
      // Recorded so later picks can tell how much of what the user has seen was
      // exploratory, which is what the explore quota is measured against.
      source: recommendation.source,
    );
    await _suggestionRepository.saveRecord(record);
    _history = [..._history, record];
    _current = recommendation;
    _currentRecord = record;
    notifyListeners();
    return recommendation;
  }

  Future<void> submitFeedback({
    required SuggestionStatus status,
    int? rating,
    SuggestionSkipReason? skipReason,
    String? comment,
    bool? done,
    SuggestionUsefulness? useful,
  }) async {
    final record = _currentRecord;
    if (record == null) return;
    // copyWith rather than a fresh record: rebuilding it dropped the source,
    // and would drop the completion once a rating arrived separately.
    await _write(
      record.copyWith(
        status: status,
        rating: rating,
        skipReason: skipReason,
        comment: comment,
        done: done,
        useful: useful,
      ),
    );
  }

  /// Records that the user did the activity.
  ///
  /// Written the moment they say so, before any rating. Someone who did the
  /// activity and then ignored the rating step has still done it, and leaving
  /// `done` unset until a rating arrives would be inferring it later.
  Future<void> recordCompletion() {
    return submitFeedback(status: SuggestionStatus.completed, done: true);
  }

  /// Records how a suggestion went, for one specific record.
  ///
  /// Separate from completion on purpose: usefulness is about whether the
  /// activity helped, which is a different question from whether it happened.
  Future<void> recordRating({
    required String recordId,
    SuggestionUsefulness? usefulness,
    int? rating,
    String? comment,
  }) async {
    final record = _recordById(recordId);
    if (record == null) return;
    await _write(
      record.copyWith(
        // A rating can arrive for something already marked done, so the
        // completion is preserved rather than assumed.
        done: record.done,
        useful: usefulness,
        rating: rating,
        comment: comment,
      ),
    );
  }

  /// Records that the user declined a specific suggestion.
  ///
  /// Separate from [submitFeedback] because the Home card declines a record it
  /// already committed, rather than one currently on screen. Declining stays
  /// free: the engine counts "not now" as no verdict at all.
  Future<void> dismissRecord(
    String recordId, {
    required SuggestionSkipReason reason,
  }) async {
    final record = _recordById(recordId);
    if (record == null) return;
    await _write(
      record.copyWith(status: SuggestionStatus.skipped, skipReason: reason),
    );
  }

  /// A completion from the last 48 hours that was never rated.
  ///
  /// Offered quietly so a rating can still be given later. This is never
  /// pushed at the user, and it expires on its own.
  SuggestionRecord? pendingRating({DateTime? now}) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(ratingWindow);
    final candidates = _history
        .where(
          (record) =>
              record.done == true &&
              record.useful == null &&
              !record.shownAt.isBefore(cutoff),
        )
        .toList()
      ..sort((a, b) => b.shownAt.compareTo(a.shownAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  /// How long an unrated completion stays available to rate.
  static const ratingWindow = Duration(hours: 48);

  SuggestionRecord? _recordById(String id) {
    for (final record in _history) {
      if (record.id == id) return record;
    }
    return null;
  }

  Future<void> _write(SuggestionRecord updated) async {
    await _suggestionRepository.saveRecord(updated);
    _history = [
      for (final item in _history) item.id == updated.id ? updated : item,
    ];
    if (_currentRecord?.id == updated.id) _currentRecord = updated;
    notifyListeners();
  }
}
