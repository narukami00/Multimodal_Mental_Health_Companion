import '../../core/models/daily_features.dart';
import '../../core/models/user_profile.dart';
import '../../data/contracts/daily_features_repository.dart';
import '../../domain/capacity/capacity_estimator.dart';
import '../../domain/footprint/app_categories.dart';
import '../../domain/footprint/sleep_estimator.dart';
import '../../domain/footprint/usage_day_reducer.dart';
import '../../services/usage_collector_service.dart';

/// Marks a row whose day had ended when it was collected, so it is complete and
/// never needs reading again. A row collected during its own day lacks it.
const usageFinalSource = 'usageFinal';

/// How many days back catch-up reaches. The spike found Android keeps about ten
/// days of events on a real device; seven leaves margin for phones that keep
/// less.
const usageBackfillDays = 7;

/// Reads device usage for a day, reduces it, and merges the result into that
/// day's row.
///
/// Usage is queried after the fact, so there is nothing running in the
/// background: whenever the app is opened it fills in whatever the last week
/// left uncollected. Nothing is read unless [isCollecting] says both consent and
/// Android's access are in place, and nothing from the raw events outlives the
/// call: only the reduced numbers are written.
class UsageRecorder {
  UsageRecorder({
    required UsageCollectorService collector,
    required DailyFeaturesRepository repository,
    required UserProfile Function() profile,
    required bool Function() isCollecting,
    required bool Function() keepsAppNames,
    DateTime Function()? clock,
  }) : _collector = collector,
       _repository = repository,
       _profile = profile,
       _isCollecting = isCollecting,
       _keepsAppNames = keepsAppNames,
       _clock = clock ?? DateTime.now;

  final UsageCollectorService _collector;
  final DailyFeaturesRepository _repository;
  final UserProfile Function() _profile;
  final bool Function() _isCollecting;
  final bool Function() _keepsAppNames;
  final DateTime Function() _clock;

  /// Reads and records one day. Returns false when nothing was written: not
  /// collecting, or the platform gave no events at all for the window.
  ///
  /// An empty answer is treated as "no data", not as a day of zeros: a phone in
  /// use always produces screen events, so silence means access was lost or the
  /// day is beyond what Android kept, and writing zeros would claim otherwise.
  Future<bool> collectDay(DateTime day) async {
    if (!_isCollecting()) return false;

    final now = _clock();
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    final dataEnd = now.isBefore(dayEnd) ? now : dayEnd;
    if (!dataEnd.isAfter(dayStart)) return false;

    // From noon the day before, so a session running at midnight is seen and the
    // evening before is there for the sleep estimate.
    final from = DateTime(day.year, day.month, day.day - 1, 12);
    final events = await _collector.events(from: from, to: dataEnd);
    if (events.isEmpty) return false;

    final profile = _profile();
    final described = await _collector.describeApps(packagesIn(events).toList());
    final labels = {
      for (final entry in described.entries)
        if (entry.value.label.isNotEmpty) entry.key: entry.value.label,
    };

    final reduced = reduceUsageDay(
      day: dayStart,
      events: events,
      dataEnd: dataEnd,
      // The window for tonight; the early hours of the day belong to last
      // night's, which differs only for someone whose weekend hours differ.
      sleepWindow: resolveSleepWindow(
        profile: profile,
        now: DateTime(day.year, day.month, day.day, 20),
      ),
      categoryOf: categoryResolverFor(described),
      includeTopApps: _keepsAppNames(),
      labelOf: (package) => labels[package] ?? package,
    );
    if (reduced == null) return false;

    var row = reduced;
    final sleep = estimateSleep(
      morning: dayStart,
      events: events,
      dataEnd: dataEnd,
      sleepWindow: resolveSleepWindow(
        profile: profile,
        // Eight in the morning of the day the night ended on.
        now: DateTime(day.year, day.month, day.day, 8),
      ),
    );
    if (sleep != null) row = row.mergedWith(sleep.toFeatures(row.dayKey));

    if (!now.isBefore(dayEnd)) {
      row = row.mergedWith(
        DailyFeatures(dayKey: row.dayKey, sources: const {usageFinalSource}),
      );
    }
    await _repository.upsert(row);
    return true;
  }

  /// Fills in the last [days] days that are not yet complete, oldest first.
  /// Today is always read again, since it is still changing. Returns how many
  /// days were written.
  Future<int> catchUp({int days = usageBackfillDays}) async {
    if (!_isCollecting()) return 0;

    final now = _clock();
    final existing = {
      for (final row in await _repository.loadAll()) row.dayKey: row,
    };

    var written = 0;
    for (var back = days - 1; back >= 0; back--) {
      final day = DateTime(now.year, now.month, now.day - back);
      final key = _key(day);
      final isToday = back == 0;
      if (!isToday && existing[key]?.sources.contains(usageFinalSource) == true) {
        continue;
      }
      if (await collectDay(day)) written++;
    }
    return written;
  }

  static String _key(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
