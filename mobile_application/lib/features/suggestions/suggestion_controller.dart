import 'package:flutter/foundation.dart';

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
  bool _isLoaded = false;
  Recommendation? _current;
  SuggestionRecord? _currentRecord;

  bool get isLoaded => _isLoaded;
  Recommendation? get current => _current;

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

  Future<Recommendation?> suggest({
    required UserProfile profile,
    required RecommendationContext context,
    DateTime? now,
    bool userInitiated = false,
  }) async {
    if (!_isLoaded) await load();
    final activities = await _libraryRepository.load();
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
  }) async {
    final record = _currentRecord;
    if (record == null) return;
    final updated = SuggestionRecord(
      id: record.id,
      activityId: record.activityId,
      shownAt: record.shownAt,
      contextTags: record.contextTags,
      status: status,
      rating: rating,
      skipReason: skipReason,
      comment: comment,
    );
    await _suggestionRepository.saveRecord(updated);
    _history = [
      for (final item in _history) item.id == updated.id ? updated : item,
    ];
    _currentRecord = updated;
    notifyListeners();
  }
}
