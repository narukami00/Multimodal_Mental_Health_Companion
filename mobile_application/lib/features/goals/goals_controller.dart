import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../../domain/goals/goals.dart' as domain;
import '../../domain/goals/goals.dart';

/// The person's phone-use goals and how each day went against them.
///
/// Goals are stored; results are always worked out again from the stored daily rows, so they stay right when a row
/// is corrected, a copy is brought back, or a goal is changed. Judging happens for finished days only.
class GoalsController extends ChangeNotifier {
  GoalsController({
    required SharedPreferences preferences,
    required Future<List<DailyFeatures>> Function() loadRows,
    Set<String> Function()? restDays,
    DateTime Function()? clock,
  }) : _preferences = preferences,
       _loadRows = loadRows,
       _restDays = restDays ?? (() => const <String>{}),
       _clock = clock ?? DateTime.now;

  static const preferenceKey = 'goals.list';

  final SharedPreferences _preferences;
  final Future<List<DailyFeatures>> Function() _loadRows;
  final Set<String> Function() _restDays;
  final DateTime Function() _clock;

  List<Goal> _goals = const [];
  List<DailyFeatures> _rows = const [];
  List<GoalDay> _days = const [];
  bool _refreshing = false;

  List<Goal> get goals => List.unmodifiable(_goals);
  List<GoalDay> get days => List.unmodifiable(_days);
  bool get hasGoals => _goals.isNotEmpty;

  String get _yesterday {
    final n = _clock();
    return dayKey(DateTime(n.year, n.month, n.day - 1));
  }

  Future<void> load() async {
    final raw = _preferences.getString(preferenceKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) _goals = [for (final item in list) ?Goal.fromMap(item)];
      } catch (_) {
        _goals = const [];
      }
    }
    await refresh();
  }

  Future<void> _save() => _preferences.setString(preferenceKey, jsonEncode([for (final g in _goals) g.toMap()]));

  /// Works the results out again from the stored rows. Cheap enough to call whenever phone data may have moved.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      _rows = await _loadRows();
      _recompute();
    } finally {
      _refreshing = false;
    }
    notifyListeners();
  }

  void _recompute() {
    _days = judgeGoals(
      goals: _goals,
      rowsByDay: {for (final r in _rows) r.dayKey: r},
      restDays: _restDays(),
      lastDay: _yesterday,
    );
  }

  Future<Goal> add(GoalMeasure measure, int target, {bool weekdaysOnly = false}) async {
    final now = _clock();
    final goal = Goal(
      id: 'g${now.microsecondsSinceEpoch}',
      measure: measure,
      target: target.clamp(measure.minTarget, measure.maxTarget),
      weekdaysOnly: weekdaysOnly,
      createdDay: dayKey(now),
    );
    _goals = [..._goals, goal];
    await _save();
    _recompute();
    notifyListeners();
    return goal;
  }

  Future<void> update(String id, {int? target, bool? weekdaysOnly}) async {
    _goals = [
      for (final g in _goals)
        if (g.id == id)
          g.copyWith(target: target?.clamp(g.measure.minTarget, g.measure.maxTarget), weekdaysOnly: weekdaysOnly)
        else
          g,
    ];
    await _save();
    _recompute();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _goals = [for (final g in _goals) if (g.id != id) g];
    await _save();
    _recompute();
    notifyListeners();
  }

  /// A starting number from the person's own recent days, or null when there is not enough history yet.
  int? suggestionFor(GoalMeasure measure) => suggestedTarget(measure, _rows.reversed.take(14));

  /// Days on which at least one goal was met: each waters the tree once.
  List<String> get metDayKeys => [
    for (final d in _days)
      if (d.anyMet) d.day,
  ];

  /// The outcomes of one goal, oldest first, ending yesterday.
  List<GoalOutcome> outcomesFor(String goalId) => [
    for (final d in _days) d.results[goalId]?.outcome ?? GoalOutcome.skipped,
  ];

  /// A quiet offer to ease or firm up a goal, from how its last days went.
  GoalAdjustment? adjustmentOffer(Goal goal) => domain.adjustmentFor(goal, outcomesFor(goal.id));

  /// Over the last seven days: how many were judged and on how many at least one goal was met.
  ({int judged, int met}) get lastWeek {
    final recent = _days.length <= 7 ? _days : _days.sublist(_days.length - 7);
    return (judged: recent.where((d) => d.judged).length, met: recent.where((d) => d.anyMet).length);
  }
}
