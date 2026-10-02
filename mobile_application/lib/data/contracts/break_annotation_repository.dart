import '../../core/models/break_annotation.dart';

abstract interface class BreakAnnotationRepository {
  /// Every annotation, oldest first.
  Future<List<BreakAnnotation>> loadAll();

  /// Stores [annotation], replacing any earlier one for the same shift.
  Future<void> save(BreakAnnotation annotation);

  /// Removes everything, for when the person deletes their pattern data.
  Future<void> deleteAll();
}
