import '../../core/day_key.dart';
import 'tree_geometry.dart';

/// The numbers that set the pace of the forest. All of them live here so they can be tuned in one place.
class ForestConfig {
  const ForestConfig({
    this.watersPerTree = 7,
    this.maxGrowthPerDay = 3,
    this.textCapPerDay = 3,
    this.taskCapPerDay = 3,
    this.journalFirstWorth = 2,
    this.journalExtraWorth = 1,
    this.journalExtraCapPerDay = 2,
  });

  /// Waters that make a fully grown tree: one per stage.
  final int watersPerTree;

  /// Waters that can actually advance the tree in one day. More are still "earned" and shown, but the tree needs time.
  final int maxGrowthPerDay;

  /// Typed check-ins and typed journals share this cap (1 water each).
  final int textCapPerDay;

  /// Tasks and exercises (1 water each).
  final int taskCapPerDay;

  /// The first voice or video journal of the day is worth this many waters...
  final int journalFirstWorth;

  /// ...and each further one is worth this many, up to [journalExtraCapPerDay] extra waters in the day.
  final int journalExtraWorth;
  final int journalExtraCapPerDay;
}

enum WaterKind { text, journal, task, goal }

/// One thing the person did that waters the tree.
class WaterEvent {
  const WaterEvent({required this.id, required this.kind, required this.at});

  /// The id of the entry or suggestion it came from, so the same thing is never counted twice.
  final String id;
  final WaterKind kind;
  final DateTime at;

  Map<String, Object?> toMap() => {'id': id, 'kind': kind.name, 'at': at.toIso8601String()};

  static WaterEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = WaterKind.values.where((k) => k.name == raw['kind']).firstOrNull;
    final at = DateTime.tryParse('${raw['at']}');
    final id = raw['id'];
    if (kind == null || at == null || id is! String) return null;
    return WaterEvent(id: id, kind: kind, at: at);
  }
}

/// What one event came to: the waters it earned, and how many of them the tree could take that day.
class AppliedWater {
  const AppliedWater({required this.event, required this.earned, required this.grown});
  final WaterEvent event;
  final int earned;
  final int grown;
}

class FinishedTree {
  const FinishedTree({required this.index, required this.species, required this.finishedAt, required this.waters});
  final int index;
  final int species;
  final DateTime finishedAt;

  /// The waters that grew it, oldest first.
  final List<AppliedWater> waters;
}

/// The whole garden, worked out from the list of waterings.
class Garden {
  const Garden({
    required this.finished,
    required this.currentIndex,
    required this.currentSpecies,
    required this.currentProgress,
    required this.currentWaters,
    required this.config,
  });

  final List<FinishedTree> finished;

  /// Which tree is growing now (0 for the first), its species, how many waters it has, and which ones they were.
  final int currentIndex;
  final int currentSpecies;
  final int currentProgress;
  final List<AppliedWater> currentWaters;
  final ForestConfig config;

  /// The stage to draw (0..7): one stage per water.
  double get stage => (currentProgress * 7 / config.watersPerTree).clamp(0, 7).toDouble();
}

/// Which species the tree with this [index] is. The first is an oak; after that it varies, and never repeats the last one.
int speciesFor(int index, int previous) {
  if (index == 0) return 0;
  final r = mulberry32(4242 + index * 977);
  int s;
  do {
    s = (r() * treeSpecies.length).floor();
  } while (s == previous);
  return s;
}

/// Works out the garden from [events] (any order): applies the daily rules and the daily growth guard, finishes trees and
/// starts new ones. Pure: the same events always give the same garden.
Garden growGarden(List<WaterEvent> events, ForestConfig cfg) {
  final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
  final finished = <FinishedTree>[];
  var index = 0, species = speciesFor(0, -1), progress = 0;
  var current = <AppliedWater>[];

  String? day;
  var text = 0, task = 0, journals = 0, extra = 0, grownToday = 0;
  var goalToday = false;

  for (final e in sorted) {
    final key = dayKey(e.at);
    if (key != day) {
      day = key;
      text = task = journals = extra = grownToday = 0;
      goalToday = false;
    }
    var earned = 0;
    switch (e.kind) {
      case WaterKind.text:
        if (text < cfg.textCapPerDay) {
          text++;
          earned = 1;
        }
      case WaterKind.task:
        if (task < cfg.taskCapPerDay) {
          task++;
          earned = 1;
        }
      case WaterKind.goal:
        // However many goals were met, a day of meeting them is one water.
        if (!goalToday) {
          goalToday = true;
          earned = 1;
        }
      case WaterKind.journal:
        if (journals == 0) {
          earned = cfg.journalFirstWorth;
        } else if (extra + cfg.journalExtraWorth <= cfg.journalExtraCapPerDay) {
          earned = cfg.journalExtraWorth;
          extra += earned;
        }
        journals++;
    }
    final room = cfg.maxGrowthPerDay - grownToday;
    final grown = earned == 0 ? 0 : (earned < room ? earned : room).clamp(0, earned);
    grownToday += grown;
    current.add(AppliedWater(event: e, earned: earned, grown: grown));
    progress += grown;
    while (progress >= cfg.watersPerTree) {
      finished.add(FinishedTree(index: index, species: species, finishedAt: e.at, waters: current));
      progress -= cfg.watersPerTree;
      index++;
      species = speciesFor(index, species);
      current = <AppliedWater>[];
    }
  }
  return Garden(
    finished: finished,
    currentIndex: index,
    currentSpecies: species,
    currentProgress: progress,
    currentWaters: current,
    config: cfg,
  );
}

/// The waters earned today that the person has not watched yet, oldest first: the ones that will be poured when they open
/// the forest. Earlier days' waters are applied quietly and never replayed.
List<WaterEvent> unwatchedToday(List<WaterEvent> events, DateTime? watchedThrough, DateTime now) {
  final today = dateOnly(now);
  final list = [
    for (final e in events)
      if (!dateOnly(e.at).isBefore(today) && (watchedThrough == null || e.at.isAfter(watchedThrough))) e,
  ]..sort((a, b) => a.at.compareTo(b.at));
  return list;
}

/// The events the garden is drawn from right now: everything before today, plus today's already-watched waters. The
/// unwatched ones wait to be poured in front of the person.
List<WaterEvent> displayedEvents(List<WaterEvent> events, DateTime? watchedThrough, DateTime now) {
  final waiting = unwatchedToday(events, watchedThrough, now).map((e) => e.id).toSet();
  return [for (final e in events) if (!waiting.contains(e.id)) e];
}
