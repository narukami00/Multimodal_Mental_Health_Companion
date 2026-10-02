import '../../core/models/memory_moment.dart';
import '../contracts/moment_repository.dart';

class InMemoryMomentRepository implements MomentRepository {
  final Map<String, MemoryMoment> _rows = {};
  final List<MomentTombstone> _tombstones = [];

  @override
  Future<List<MemoryMoment>> loadAll() async {
    final all = _rows.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(all);
  }

  @override
  Future<void> save(MemoryMoment moment) async => _rows[moment.id] = moment;

  @override
  Future<void> delete(String id, {required DateTime at}) async {
    if (_rows.remove(id) != null) {
      _tombstones.add(MomentTombstone(id: id, deletedAt: at));
    }
  }

  @override
  Future<List<MomentTombstone>> tombstones() async => List.unmodifiable(_tombstones);

  @override
  Future<void> deleteAll() async {
    _rows.clear();
    _tombstones.clear();
  }
}
