import '../../core/models/daily_features.dart';
import '../contracts/daily_features_repository.dart';

class InMemoryDailyFeaturesRepository implements DailyFeaturesRepository {
  final Map<String, DailyFeatures> _rows = {};

  @override
  Future<List<DailyFeatures>> loadAll() async {
    final keys = _rows.keys.toList()..sort();
    return List.unmodifiable([for (final key in keys) _rows[key]!]);
  }

  @override
  Future<void> upsert(DailyFeatures features) async {
    final existing = _rows[features.dayKey];
    _rows[features.dayKey] = existing == null
        ? features
        : existing.mergedWith(features);
  }

  @override
  Future<int> deleteBefore(String dayKey) async {
    final stale = _rows.keys.where((key) => key.compareTo(dayKey) < 0).toList();
    stale.forEach(_rows.remove);
    return stale.length;
  }

  @override
  Future<void> removeAppNames() async {
    for (final key in _rows.keys.toList()) {
      _rows[key] = _rows[key]!.withoutAppNames();
    }
  }

  @override
  Future<void> removeUsageData() async {
    for (final key in _rows.keys.toList()) {
      final stripped = _rows[key]!.withoutUsage();
      if (stripped.sources.isEmpty) {
        _rows.remove(key);
      } else {
        _rows[key] = stripped;
      }
    }
  }

  @override
  Future<void> deleteAll() async => _rows.clear();
}
