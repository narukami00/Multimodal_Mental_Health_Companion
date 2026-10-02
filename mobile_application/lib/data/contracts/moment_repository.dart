import '../../core/models/memory_moment.dart';

abstract interface class MomentRepository {
  /// Every stored moment, oldest first.
  Future<List<MemoryMoment>> loadAll();

  /// Stores [moment], replacing any earlier one with the same id.
  Future<void> save(MemoryMoment moment);

  /// Removes one moment, leaving only a tombstone with its id and the time.
  Future<void> delete(String id, {required DateTime at});

  /// Ids of moments that were deleted, and when.
  Future<List<MomentTombstone>> tombstones();

  /// Removes every moment and tombstone, for when the person clears it all.
  Future<void> deleteAll();
}
