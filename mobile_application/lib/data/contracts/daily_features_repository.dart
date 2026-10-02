import '../../core/models/daily_features.dart';

abstract interface class DailyFeaturesRepository {
  /// Every stored row, oldest day first.
  Future<List<DailyFeatures>> loadAll();

  /// Stores [features], merging into any row already kept for that day so one
  /// source never erases another's fields.
  Future<void> upsert(DailyFeatures features);

  /// Removes every row older than [dayKey] (exclusive) and returns how many.
  Future<int> deleteBefore(String dayKey);

  /// Removes the names of individual apps from every row, keeping everything
  /// else. For when that separate consent ends: category totals are not apps.
  Future<void> removeAppNames();

  /// Removes everything read from the device, keeping what the app recorded
  /// itself. A day that held only device data is removed entirely.
  Future<void> removeUsageData();

  /// Removes everything. The user's one-tap delete.
  Future<void> deleteAll();
}
