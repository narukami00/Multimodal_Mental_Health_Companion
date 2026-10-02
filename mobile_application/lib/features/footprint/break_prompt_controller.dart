import 'package:flutter/foundation.dart';

import '../../core/models/break_annotation.dart';
import '../../core/models/daily_features.dart';
import '../../core/models/session_record.dart';
import '../../data/contracts/break_annotation_repository.dart';
import '../../domain/footprint/break_prompt_policy.dart';
import '../../domain/footprint/trend_break_detector.dart';

/// Holds the one question, if any, to ask about the person's days looking
/// different, and what became of earlier ones.
///
/// It only decides and records. Whether the person has these questions turned
/// off, and whether safety support is active, are asked of the callbacks every
/// time, so a change takes effect on the next [refresh] without this holding a
/// stale copy.
class BreakPromptController extends ChangeNotifier {
  BreakPromptController({
    required BreakAnnotationRepository repository,
    required Future<List<DailyFeatures>> Function() rows,
    required List<SessionRecord> Function() sessions,
    required bool Function() muted,
    required bool Function() safetyActive,
    DateTime Function()? clock,
  }) : _repository = repository,
       _rows = rows,
       _sessions = sessions,
       _muted = muted,
       _safetyActive = safetyActive,
       _clock = clock ?? DateTime.now;

  final BreakAnnotationRepository _repository;
  final Future<List<DailyFeatures>> Function() _rows;
  final List<SessionRecord> Function() _sessions;
  final bool Function() _muted;
  final bool Function() _safetyActive;
  final DateTime Function() _clock;

  List<BreakAnnotation> _annotations = const [];
  BreakPrompt? _current;
  bool _refreshing = false;

  /// The question to show now, or null.
  BreakPrompt? get current => _current;

  /// Re-reads the days and decides. Safe to call often: it records a question
  /// as shown only the first time it appears, and never throws.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      _annotations = await _repository.loadAll();
      final now = _clock();
      final report = detectTrendBreaks(rows: await _rows(), asOf: now);
      var prompt = currentBreakPrompt(
        report: report,
        sessions: _sessions(),
        annotations: _annotations,
        now: now,
        muted: _muted(),
        safetyActive: _safetyActive(),
      );

      if (prompt != null && prompt.isNew) {
        // Recorded the moment it first appears, so it counts against the cap
        // and cannot be shown a second time as new.
        final annotation = BreakAnnotation(
          breakKey: prompt.key,
          status: BreakAnnotationStatus.shown,
          shownAt: now,
        );
        await _repository.save(annotation);
        _annotations = [..._annotations, annotation];
      }

      if (prompt?.key != _current?.key) {
        _current = prompt;
        notifyListeners();
      } else {
        _current = prompt;
      }
    } catch (error) {
      debugPrint('BreakPromptController warning: $error');
    } finally {
      _refreshing = false;
    }
  }

  /// Records their answer: a theme, or null for "nothing in particular".
  Future<void> answer(String? theme) => _decide(
    (annotation, now) => annotation.answered(theme: theme, at: now),
  );

  /// Records that they said not now.
  Future<void> dismiss() =>
      _decide((annotation, now) => annotation.dismissed(at: now));

  Future<void> _decide(
    BreakAnnotation Function(BreakAnnotation annotation, DateTime now) change,
  ) async {
    final prompt = _current;
    if (prompt == null) return;
    final now = _clock();

    BreakAnnotation? existing;
    for (final annotation in _annotations) {
      if (annotation.breakKey == prompt.key) existing = annotation;
    }
    final decided = change(
      existing ??
          BreakAnnotation(
            breakKey: prompt.key,
            status: BreakAnnotationStatus.shown,
            shownAt: now,
          ),
      now,
    );
    await _repository.save(decided);
    _annotations = [
      for (final annotation in _annotations)
        if (annotation.breakKey != prompt.key) annotation,
      decided,
    ];
    _current = null;
    notifyListeners();
  }

  /// Themes they chose recently, for use as context when choosing what to offer.
  List<String> activeThemes() => recentChosenThemes(_annotations, _clock());

  /// Forgets every answer, for when they delete their pattern data.
  Future<void> deleteAll() async {
    await _repository.deleteAll();
    _annotations = const [];
    _current = null;
    notifyListeners();
  }
}
