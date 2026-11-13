import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/memory_moment.dart';
import '../../services/secure_storage.dart';
import '../contracts/moment_repository.dart';

class SharedPreferencesMomentRepository implements MomentRepository {
  SharedPreferencesMomentRepository(this._preferences, {SecureKeyValueStore? secureStore})
      : _secureStore = secureStore;

  static const _momentsKey = 'memory.moments';
  static const _tombstonesKey = 'memory.momentTombstones';
  final SharedPreferences _preferences;
  final SecureKeyValueStore? _secureStore;

  Future<List<Object?>> _list(String key) async {
    final encoded = _secureStore != null
        ? await _secureStore.readString(key, legacyPreferences: _preferences)
        : _preferences.getString(key);
    if (encoded == null) return const [];
    try {
      final decoded = jsonDecode(encoded);
      return decoded is List ? decoded : const [];
    } on FormatException {
      // Unreadable memory is dropped: the worst case is a moment to say again.
      return const [];
    }
  }

  Future<Map<String, MemoryMoment>> _read() async => {
    for (final entry in await _list(_momentsKey))
      if (MemoryMoment.fromMap(entry) case final moment?) moment.id: moment,
  };

  Future<void> _write(Map<String, MemoryMoment> rows) async {
    final encoded = jsonEncode([for (final m in rows.values) m.toMap()]);
    if (_secureStore != null) {
      await _secureStore.writeString(_momentsKey, encoded);
    } else {
      await _preferences.setString(_momentsKey, encoded);
    }
  }

  @override
  Future<List<MemoryMoment>> loadAll() async {
    final all = (await _read()).values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(all);
  }

  @override
  Future<void> save(MemoryMoment moment) async {
    await _write((await _read())..[moment.id] = moment);
  }

  @override
  Future<void> delete(String id, {required DateTime at}) async {
    final rows = await _read();
    if (rows.remove(id) == null) return;
    await _write(rows);
    final stones = [...await tombstones(), MomentTombstone(id: id, deletedAt: at)];
    final encodedStones = jsonEncode([for (final s in stones) s.toMap()]);
    if (_secureStore != null) {
      await _secureStore.writeString(_tombstonesKey, encodedStones);
    } else {
      await _preferences.setString(_tombstonesKey, encodedStones);
    }
  }

  @override
  Future<List<MomentTombstone>> tombstones() async => [
    for (final entry in await _list(_tombstonesKey))
      if (MomentTombstone.fromMap(entry) case final stone?) stone,
  ];

  @override
  Future<void> deleteAll() async {
    if (_secureStore != null) {
      await _secureStore.remove(_momentsKey, legacyPreferences: _preferences);
      await _secureStore.remove(_tombstonesKey, legacyPreferences: _preferences);
    } else {
      await _preferences.remove(_momentsKey);
      await _preferences.remove(_tombstonesKey);
    }
  }
}
