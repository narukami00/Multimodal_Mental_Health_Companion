import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/session_input.dart';
import '../../domain/forest/forest_garden.dart';
import '../goals/goals_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';

/// What the forest remembers: the waterings (append-only, so a tree never shrinks even if an entry is later deleted),
/// which entries have already been looked at, and how far the person has watched.
class ForestData {
  ForestData({this.initialised = false, Set<String>? seen, List<WaterEvent>? events, this.watchedThrough})
      : seen = seen ?? <String>{},
        events = events ?? <WaterEvent>[];

  /// False until the first scan has run.
  bool initialised;
  final Set<String> seen;
  final List<WaterEvent> events;
  DateTime? watchedThrough;

  Map<String, Object?> toMap() => {
        'initialised': initialised,
        'seen': seen.toList(),
        'events': [for (final e in events) e.toMap()],
        'watchedThrough': watchedThrough?.toIso8601String(),
      };

  static ForestData fromMap(Object? raw) {
    if (raw is! Map) return ForestData();
    return ForestData(
      initialised: raw['initialised'] == true,
      seen: {for (final s in (raw['seen'] as List? ?? const [])) '$s'},
      events: [for (final e in (raw['events'] as List? ?? const [])) ?WaterEvent.fromMap(e)],
      watchedThrough: DateTime.tryParse('${raw['watchedThrough']}'),
    );
  }
}

abstract interface class ForestStore {
  Future<ForestData> load();
  Future<void> save(ForestData data);
}

class InMemoryForestStore implements ForestStore {
  ForestData _data = ForestData();
  @override
  Future<ForestData> load() async => ForestData.fromMap(_data.toMap());
  @override
  Future<void> save(ForestData data) async => _data = ForestData.fromMap(data.toMap());
}

class SharedPreferencesForestStore implements ForestStore {
  SharedPreferencesForestStore(this._preferences);
  final SharedPreferences _preferences;
  static const _key = 'forest_v1';

  @override
  Future<ForestData> load() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return ForestData();
    try {
      return ForestData.fromMap(jsonDecode(raw));
    } catch (_) {
      return ForestData();
    }
  }

  @override
  Future<void> save(ForestData data) => _preferences.setString(_key, jsonEncode(data.toMap()));
}

/// Turns what the person does (typed or recorded entries, tasks they finish) into waterings of the current tree, and says
/// what the garden looks like now and what is still waiting to be poured.
class ForestController extends ChangeNotifier {
  ForestController({
    required ForestStore store,
    required SessionController sessions,
    SuggestionController? suggestions,
    GoalsController? goals,
    this.config = const ForestConfig(),
    DateTime Function()? clock,
  })  : _store = store,
        _sessions = sessions,
        _suggestions = suggestions,
        _goals = goals,
        _clock = clock ?? DateTime.now;

  final ForestStore _store;
  final SessionController _sessions;
  final SuggestionController? _suggestions;
  final GoalsController? _goals;
  final ForestConfig config;
  final DateTime Function() _clock;

  ForestData _data = ForestData();
  bool _loaded = false;
  bool _scanning = false;

  bool get isLoaded => _loaded;
  DateTime get now => _clock();

  Future<void> load() async {
    _data = await _store.load();
    _loaded = true;
    await _scan();
    _sessions.addListener(_scan);
    _suggestions?.addListener(_scan);
    _goals?.addListener(_scan);
    // The card's sky follows the hour, so tell listeners now and then that time has moved on.
    _clockTick = Timer.periodic(const Duration(minutes: 10), (_) => notifyListeners());
    notifyListeners();
  }

  Timer? _clockTick;

  @override
  void dispose() {
    _clockTick?.cancel();
    _sessions.removeListener(_scan);
    _suggestions?.removeListener(_scan);
    _goals?.removeListener(_scan);
    super.dispose();
  }

  /// Notices new entries and finished tasks. Safe to call any time: each thing is counted once.
  Future<void> _scan() async {
    if (!_loaded || _scanning) return;
    _scanning = true;
    try {
      var changed = false;
      // Everything the person has done counts, history included: each entry and finished task is replayed with its own
      // date through the same daily rules, so the forest never starts from nothing for someone who has been here a while.
      void take(String id, WaterKind kind, DateTime at) {
        if (!_data.seen.add(id)) return;
        changed = true;
        _data.events.add(WaterEvent(id: id, kind: kind, at: at));
      }

      for (final s in _sessions.sessions) {
        take('s:${s.id}', s.mode == CaptureMode.text ? WaterKind.text : WaterKind.journal, s.createdAt);
      }
      for (final r in _suggestions?.history ?? const []) {
        if (r.done == true) take('t:${r.id}', WaterKind.task, r.completedAt ?? r.acceptedAt ?? r.shownAt);
      }
      // A day on which a phone goal was met waters once. It is noticed the morning after, so it is dated then
      // (or at nine the next morning for older days), which lets today's pour play when the forest is opened.
      for (final day in _goals?.metDayKeys ?? const <String>[]) {
        final parsed = DateTime.tryParse(day);
        if (parsed == null) continue;
        final nineNext = DateTime(parsed.year, parsed.month, parsed.day + 1, 9);
        take('g:$day', WaterKind.goal, nineNext.isAfter(now) ? now : nineNext);
      }
      if (!_data.initialised) {
        _data.initialised = true;
        changed = true;
      }
      if (changed) {
        await _store.save(_data);
        notifyListeners();
      }
    } finally {
      _scanning = false;
    }
  }

  List<WaterEvent> get events => List.unmodifiable(_data.events);

  /// The garden as it is drawn now: everything before today, plus today's waters the person has already watched.
  Garden get garden => growGarden(displayedEvents(_data.events, _data.watchedThrough, now), config);

  /// Today's waters that have not been poured in front of the person yet, oldest first.
  List<WaterEvent> get waiting => unwatchedToday(_data.events, _data.watchedThrough, now);

  /// Whether the can should be standing by the tree.
  bool get waterWaiting => waiting.isNotEmpty;

  /// The garden after the first [count] waiting waters have been poured, for playing them one at a time.
  Garden gardenAfter(int count) {
    final shown = displayedEvents(_data.events, _data.watchedThrough, now);
    return growGarden([...shown, ...waiting.take(count)], config);
  }

  /// The person has watched everything that was waiting.
  Future<void> markWatched() async {
    final last = waiting.isEmpty ? null : waiting.last.at;
    if (last == null) return;
    _data.watchedThrough = last;
    await _store.save(_data);
    notifyListeners();
  }
}
