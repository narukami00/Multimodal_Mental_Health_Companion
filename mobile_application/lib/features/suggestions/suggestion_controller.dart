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
    bool userInitiated = false,
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
      userInitiated: userInitiated,
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
