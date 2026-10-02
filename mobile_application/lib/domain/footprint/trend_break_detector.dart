import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../capacity/capacity_estimator.dart';
import 'pattern_features.dart';
import 'personal_baseline.dart';

enum BreakDirection { up, down }

/// How a departure was noticed.
enum BreakKind {
  /// Two or more days in a row well outside the person's usual.
  fast,

  /// A smaller shift that has held for a couple of weeks.
  slow,
}

/// One feature leaving the person's own usual.
class FeatureBreak {
  const FeatureBreak({
    required this.feature,
    required this.direction,
    required this.startDay,
    required this.latestDay,
    required this.days,
    required this.meanZ,
    required this.kind,
  });

  final PatternFeature feature;
  final BreakDirection direction;
  final DateTime startDay;
  final DateTime latestDay;

  /// How many days it has held.
  final int days;

  /// The average distance from usual over those days, in the person's own
  /// spreads, signed.
  final double meanZ;
  final BreakKind kind;

  double get strength => meanZ.abs();
}

/// A shift in more than one family of features at once: worth mentioning.
class TrendBreak {
  TrendBreak(List<FeatureBreak> features)
    : features = List.unmodifiable(features),
      families = {for (final f in features) f.feature.family},
      startDay = features.map((f) => f.startDay).reduce(_earlier),
      latestDay = features.map((f) => f.latestDay).reduce(_later);

  final List<FeatureBreak> features;
  final Set<PatternFamily> families;
  final DateTime startDay;
  final DateTime latestDay;

  /// The biggest departure among them, in the person's own spreads.
  double get strength =>
      features.map((f) => f.strength).reduce((a, b) => a > b ? a : b);

  /// Stable for the same shift as it goes on, so the same break is not asked
  /// about twice.
  String get key {
    final names = families.map((f) => f.name).toList()..sort();
    return '${dayKey(startDay)}:${names.join('+')}';
  }

  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
}

/// What the detector concluded.
class TrendBreakReport {
  const TrendBreakReport({
    required this.learning,
    this.surfaced,
    this.silent = const [],
  });

  /// There is not yet enough of the person's own history to say anything.
  final bool learning;

  /// A shift across families, if there is one. The only thing the person is
  /// ever told about.
  final TrendBreak? surfaced;

  /// Departures seen in a single family. Recorded, never mentioned: one feature
  /// moving on its own is far too often just a different kind of day.
  final List<FeatureBreak> silent;
}

/// Looks for the person's days leaving their own usual.
///
/// Pure. Days are compared with a baseline built from the weeks *before* the
/// stretch being judged, so a shift cannot hide itself by dragging the usual
/// along with it. Only finished days count: today, and any day whose device data
/// was read before it ended, are left out entirely.
///
/// [asOf] is the moment of asking; the latest day judged is the one before it.
/// Never fires inside the learning period.
TrendBreakReport detectTrendBreaks({
  required List<DailyFeatures> rows,
  required DateTime asOf,
  int fastDays = 7,
  int slowDays = 14,
  int referenceWindow = 28,
  double threshold = 2.0,
  int consecutive = 2,
  double cusumSlack = 0.5,
  double cusumLimit = 4.0,
  Set<int> weekendDays = defaultWeekendDays,
}) {
  final today = dateOnly(asOf);
  final todayKey = dayKey(today);
  final finished = [
    for (final row in rows)
      if (row.dayKey.compareTo(todayKey) < 0 && row.usageComplete) row,
  ];
  final byDay = {for (final row in finished) row.dayKey: row};

  FeatureBreakSet analyse(int recentDays, {required bool slow}) {
    final recentStart = DateTime(today.year, today.month, today.day - recentDays);
    final baseline = PersonalBaseline.build(
      finished,
      referenceEnd: recentStart,
      windowDays: referenceWindow,
      weekendDays: weekendDays,
    );
    final found = <FeatureBreak>[];
    if (!baseline.isReady) return FeatureBreakSet(baseline.isReady, found);

    for (final feature in baseline.features) {
      final series = <({DateTime day, double z})>[];
      for (var back = recentDays; back >= 1; back--) {
        final day = DateTime(today.year, today.month, today.day - back);
        final row = byDay[dayKey(day)];
        if (row == null) continue;
        final z = baseline.zScore(feature, row);
        if (z != null) series.add((day: day, z: z));
      }
      final detected = slow
          ? _slow(feature, series, cusumSlack, cusumLimit)
          : _fast(feature, series, threshold, consecutive, today);
      if (detected != null) found.add(detected);
    }
    return FeatureBreakSet(true, found);
  }

  final fast = analyse(fastDays, slow: false);
  final slow = analyse(slowDays, slow: true);

  if (!fast.ready && !slow.ready) return const TrendBreakReport(learning: true);

  // A feature seen both ways keeps its stronger reading.
  final byFeature = <PatternFeature, FeatureBreak>{};
  for (final found in [...fast.breaks, ...slow.breaks]) {
    final existing = byFeature[found.feature];
    if (existing == null || found.strength > existing.strength) {
      byFeature[found.feature] = found;
    }
  }
  final all = byFeature.values.toList()
    ..sort((a, b) => b.strength.compareTo(a.strength));

  final families = {for (final f in all) f.feature.family};
  if (families.length >= 2) {
    return TrendBreakReport(learning: false, surfaced: TrendBreak(all));
  }
  return TrendBreakReport(learning: false, silent: all);
}

/// The result of one pass, and whether a baseline existed to judge against.
class FeatureBreakSet {
  const FeatureBreakSet(this.ready, this.breaks);

  final bool ready;
  final List<FeatureBreak> breaks;
}

/// The latest run of consecutive days beyond [threshold] on the same side, if it
/// is still going (it reaches the latest day or the one before) and long enough.
FeatureBreak? _fast(
  PatternFeature feature,
  List<({DateTime day, double z})> series,
  double threshold,
  int consecutive,
  DateTime today,
) {
  if (series.isEmpty) return null;

  // A run may have ended yesterday, so one ordinary day at the very end is let
  // through. More than that and it is over, which the "still going" check below
  // also enforces by dates.
  final points = series.last.z.abs() <= threshold
      ? series.sublist(0, series.length - 1)
      : series;

  final run = <({DateTime day, double z})>[];
  for (final point in points.reversed) {
    final beyond = point.z.abs() > threshold;
    if (!beyond) break;
    if (run.isNotEmpty && (point.z > 0) != (run.first.z > 0)) break;
    // Days must be consecutive: a gap in the data ends the run.
    if (run.isNotEmpty &&
        run.last.day.difference(point.day).inHours > 36) {
      break;
    }
    run.add(point);
  }
  if (run.length < consecutive) return null;

  // Still going: the run has to reach yesterday or the day before.
  final latest = run.first.day;
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (yesterday.difference(latest).inHours > 36) return null;

  final mean = run.fold<double>(0, (sum, p) => sum + p.z) / run.length;
  return FeatureBreak(
    feature: feature,
    direction: mean > 0 ? BreakDirection.up : BreakDirection.down,
    startDay: run.last.day,
    latestDay: latest,
    days: run.length,
    meanZ: mean,
    kind: BreakKind.fast,
  );
}

/// The most a single day can add to the cumulative sum, in spreads.
const _cusumClip = 3.0;

/// A one-sided cumulative sum on each side of usual: it grows while days sit
/// consistently above [slack] spreads from it and drains when they do not. A
/// sustained shift too small for the fast rule still builds up past [limit].
FeatureBreak? _slow(
  PatternFeature feature,
  List<({DateTime day, double z})> series,
  double slack,
  double limit,
) {
  if (series.length < 7) return null;

  var up = 0.0;
  var down = 0.0;
  DateTime? upSince;
  DateTime? downSince;
  for (final point in series) {
    // Clipped, so one wild day cannot build a sustained shift on its own: that
    // is the fast rule's business, and it needs two days.
    final z = point.z.clamp(-_cusumClip, _cusumClip);
    final nextUp = up + z - slack;
    if (nextUp <= 0) {
      up = 0;
      upSince = null;
    } else {
      upSince ??= point.day;
      up = nextUp;
    }
    final nextDown = down - z - slack;
    if (nextDown <= 0) {
      down = 0;
      downSince = null;
    } else {
      downSince ??= point.day;
      down = nextDown;
    }
  }

  final goingUp = up > limit;
  final goingDown = down > limit;
  if (!goingUp && !goingDown) return null;

  final upward = goingUp && (!goingDown || up >= down);
  final since = upward ? upSince! : downSince!;
  final run = [
    for (final point in series)
      if (!point.day.isBefore(since)) point,
  ];
  final mean = run.fold<double>(0, (sum, p) => sum + p.z) / run.length;
  return FeatureBreak(
    feature: feature,
    direction: upward ? BreakDirection.up : BreakDirection.down,
    startDay: since,
    latestDay: series.last.day,
    days: run.length,
    meanZ: mean,
    kind: BreakKind.slow,
  );
}
