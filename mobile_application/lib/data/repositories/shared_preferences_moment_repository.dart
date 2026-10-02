import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/memory_moment.dart';
import '../contracts/moment_repository.dart';

class SharedPreferencesMomentRepository implements MomentRepository {
  SharedPreferencesMomentRepository(this._preferences);

  static const _momentsKey = 'memory.moments';
  static const _tombstonesKey = 'memory.momentTombstones';
  final SharedPreferences _preferences;

  List<Object?> _list(String key) {
    final encoded = _preferences.getString(key);
    if (encoded == null) return const [];
    try {
      final decoded = jsonDecode(encoded);
      return decoded is List ? decoded : const [];
    } on FormatException {
      // Unreadable memory is dropped: the worst case is a moment to say again.
      return const [];
    }
  }

  Map<String, MemoryMoment> _read() => {
    for (final entry in _list(_momentsKey))
      if (MemoryMoment.fromMap(entry) case final moment?) moment.id: moment,
  };

  Future<void> _write(Map<String, MemoryMoment> rows) => _preferences.setString(
    _momentsKey,
    jsonEncode([for (final m in rows.values) m.toMap()]),
  );

  @override
  Future<List<MemoryMoment>> loadAll() async {
    final all = _read().values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(all);
  }

  @override
  Future<void> save(MemoryMoment moment) async {
    await _write(_read()..[moment.id] = moment);
  }

  @override
  Future<void> delete(String id, {required DateTime at}) async {
    final rows = _read();
    if (rows.remove(id) == null) return;
    await _write(rows);
    final stones = [...await tombstones(), MomentTombstone(id: id, deletedAt: at)];
    await _preferences.setString(
      _tombstonesKey,
      jsonEncode([for (final s in stones) s.toMap()]),
    );
  }

  @override
  Future<List<MomentTombstone>> tombstones() async => [
    for (final entry in _list(_tombstonesKey))
      if (MomentTombstone.fromMap(entry) case final stone?) stone,
  ];

  @override
  Future<void> deleteAll() async {
    await _preferences.remove(_momentsKey);
    await _preferences.remove(_tombstonesKey);
  }
}
