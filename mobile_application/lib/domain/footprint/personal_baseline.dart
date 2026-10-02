import '../../core/day_key.dart';
import '../../core/models/daily_features.dart';
import '../capacity/capacity_estimator.dart';
import 'pattern_features.dart';

/// The median of [values]. Empty input has no median.
double? median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// The median absolute deviation: how far values typically sit from their
/// median. Unlike a standard deviation, one very unusual day barely moves it.
double? medianAbsoluteDeviation(List<double> values) {
  final centre = median(values);
  if (centre == null) return null;
  return median([for (final v in values) (v - centre).abs()]);
}

/// What is usual for one feature: where it sits and how much it normally varies.
class FeatureBaseline {
  const FeatureBaseline({
    required this.median,
    required this.sigma,
    required this.samples,
    required this.daytypeSpecific,
  });

  final double median;

  /// A robust spread in the feature's own unit, never below its floor.
  final double sigma;

  /// How many days it was worked out from.
  final int samples;

  /// Whether it comes only from the same kind of day (weekday or weekend). When
  /// there were too few of those, it falls back to all days.
  final bool daytypeSpecific;

  /// How many spreads [value] is from usual, signed.
  double zScore(double value) => (value - median) / sigma;
}

/// A person's own usual, per feature, from a reference stretch of their days.
///
/// Everything is relative to *them*: nothing here knows what is typical for
/// anyone else. It is built from a window that ends before [referenceEnd], so
/// the days being judged are never part of what they are judged against.
///
/// Weekdays and weekends are kept apart, since a person's weekend is often a
/// different shape from their week, and a feature only gets a baseline once
/// there are enough days to mean something. Before that it is simply absent:
/// the model is still learning, and says nothing.
class PersonalBaseline {
  PersonalBaseline._(this._pooled, this._weekday, this._weekend, this._weekendDays);

  /// Fewer days than this and a feature has no baseline.
  static const defaultMinDays = 14;

  /// Fewer days of one kind (weekday or weekend) than this and the baseline for
  /// that kind falls back to all days.
  static const defaultMinSplitDays = 5;

  /// The spread is never smaller than this share of the usual value, so a
  /// regular person's ordinary wobble is not read as a departure.
  static const relativeSigmaFloor = 0.15;

  /// Turns a median absolute deviation into a standard-deviation-sized spread,
  /// for roughly normal data.
  static const madToSigma = 1.4826;

  final Map<PatternFeature, FeatureBaseline> _pooled;
  final Map<PatternFeature, FeatureBaseline> _weekday;
  final Map<PatternFeature, FeatureBaseline> _weekend;
  final Set<int> _weekendDays;

  /// Builds the baseline from days in [windowDays] before [referenceEnd]
  /// (exclusive), counting a day as weekend when its weekday is in
  /// [weekendDays].
  factory PersonalBaseline.build(
    List<DailyFeatures> rows, {
    required DateTime referenceEnd,
    int windowDays = 28,
    int minDays = defaultMinDays,
    int minSplitDays = defaultMinSplitDays,
    Set<int> weekendDays = defaultWeekendDays,
  }) {
    final end = dateOnly(referenceEnd);
    final startKey = dayKey(DateTime(end.year, end.month, end.day - windowDays));
    final endKey = dayKey(end);

    final inWindow = [
      for (final row in rows)
        if (row.dayKey.compareTo(startKey) >= 0 && row.dayKey.compareTo(endKey) < 0)
          row,
    ];

    final pooled = <PatternFeature, FeatureBaseline>{};
    final weekday = <PatternFeature, FeatureBaseline>{};
    final weekend = <PatternFeature, FeatureBaseline>{};

    for (final feature in PatternFeature.values) {
      final all = <double>[];
      final weekdays = <double>[];
      final weekends = <double>[];
      for (final row in inWindow) {
        final value = feature.valueOf(row);
        if (value == null) continue;
        all.add(value);
        (weekendDays.contains(row.date.weekday) ? weekends : weekdays).add(value);
      }
      if (all.length < minDays) continue;

      pooled[feature] = _baseline(feature, all, specific: false);
      if (weekdays.length >= minSplitDays) {
        weekday[feature] = _baseline(feature, weekdays, specific: true);
      }
      if (weekends.length >= minSplitDays) {
        weekend[feature] = _baseline(feature, weekends, specific: true);
      }
    }
    return PersonalBaseline._(pooled, weekday, weekend, weekendDays);
  }

  static FeatureBaseline _baseline(
    PatternFeature feature,
    List<double> values, {
    required bool specific,
  }) {
    final centre = median(values)!;
    final mad = medianAbsoluteDeviation(values)!;
    final sigma = [
      mad * madToSigma,
      centre.abs() * relativeSigmaFloor,
      feature.minScale,
    ].reduce((a, b) => a > b ? a : b);
    return FeatureBaseline(
      median: centre,
      sigma: sigma,
      samples: values.length,
      daytypeSpecific: specific,
    );
  }

  /// Whether any feature has a baseline yet. False means still learning.
  bool get isReady => _pooled.isNotEmpty;

  /// The features that have a baseline.
  Iterable<PatternFeature> get features => _pooled.keys;

  /// The baseline for [feature] on a day of [date]'s kind, or null while it is
  /// still learning.
  FeatureBaseline? of(PatternFeature feature, DateTime date) {
    final pooled = _pooled[feature];
    if (pooled == null) return null;
    final weekend = _weekendDays.contains(date.weekday);
    return (weekend ? _weekend : _weekday)[feature] ?? pooled;
  }

  /// How many of their own spreads [row] sits from usual on [feature], signed,
  /// or null when there is no baseline or the row did not collect it.
  double? zScore(PatternFeature feature, DailyFeatures row) {
    final value = feature.valueOf(row);
    if (value == null) return null;
    return of(feature, row.date)?.zScore(value);
  }
}
