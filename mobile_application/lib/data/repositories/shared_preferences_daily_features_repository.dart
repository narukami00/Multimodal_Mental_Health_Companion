import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/daily_features.dart';
import '../contracts/daily_features_repository.dart';

/// Keeps daily rows as one JSON object keyed by day.
///
/// Rows are small and retention caps them near a year, which is well within
/// what preferences handle; a real database can replace this behind the same
/// contract.
class SharedPreferencesDailyFeaturesRepository
    implements DailyFeaturesRepository {
  SharedPreferencesDailyFeaturesRepository(this._preferences);

  static const _rowsKey = 'footprint.dailyFeatures';
  final SharedPreferences _preferences;

  Map<String, DailyFeatures> _read() {
    final encoded = _preferences.getString(_rowsKey);
    if (encoded == null) return {};

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return {};
      final rows = <String, DailyFeatures>{};
      for (final entry in decoded.values) {
        if (entry is! Map<String, dynamic>) continue;
        final row = DailyFeatures.fromMap(entry);
        if (row != null) rows[row.dayKey] = row;
      }
      return rows;
    } on FormatException {
      // Unreadable derived data is dropped rather than blocking startup; it is
      // rebuilt from the next collection.
      return {};
    }
  }

  Future<void> _write(Map<String, DailyFeatures> rows) async {
    await _preferences.setString(
      _rowsKey,
      jsonEncode({for (final row in rows.values) row.dayKey: row.toMap()}),
    );
  }

  @override
  Future<List<DailyFeatures>> loadAll() async {
    final rows = _read();
    final keys = rows.keys.toList()..sort();
    return List.unmodifiable([for (final key in keys) rows[key]!]);
  }

  @override
  Future<void> upsert(DailyFeatures features) async {
    final rows = _read();
    final existing = rows[features.dayKey];
    rows[features.dayKey] = existing == null
        ? features
        : existing.mergedWith(features);
    await _write(rows);
  }

  @override
  Future<int> deleteBefore(String dayKey) async {
    final rows = _read();
    final stale = rows.keys.where((key) => key.compareTo(dayKey) < 0).toList();
    if (stale.isEmpty) return 0;
    stale.forEach(rows.remove);
    await _write(rows);
    return stale.length;
  }

  @override
  Future<void> removeAppNames() async {
    final rows = _read();
    if (rows.values.every((row) => row.topApps == null)) return;
    await _write({
      for (final entry in rows.entries) entry.key: entry.value.withoutAppNames(),
    });
  }

  @override
  Future<void> removeUsageData() async {
    final rows = _read();
    if (!rows.values.any((row) => row.hasUsage)) return;
    final kept = <String, DailyFeatures>{};
    for (final entry in rows.entries) {
      final stripped = entry.value.withoutUsage();
      if (stripped.sources.isNotEmpty) kept[entry.key] = stripped;
    }
    await _write(kept);
  }

  @override
  Future<void> deleteAll() async {
    await _preferences.remove(_rowsKey);
  }
}
