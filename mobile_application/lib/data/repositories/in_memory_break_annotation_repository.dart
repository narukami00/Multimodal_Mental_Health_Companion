import '../../core/models/break_annotation.dart';
import '../contracts/break_annotation_repository.dart';

class InMemoryBreakAnnotationRepository implements BreakAnnotationRepository {
  final Map<String, BreakAnnotation> _rows = {};

  @override
  Future<List<BreakAnnotation>> loadAll() async {
    final all = _rows.values.toList()
      ..sort((a, b) => a.shownAt.compareTo(b.shownAt));
    return List.unmodifiable(all);
  }

  @override
  Future<void> save(BreakAnnotation annotation) async {
    _rows[annotation.breakKey] = annotation;
  }

  @override
  Future<void> deleteAll() async => _rows.clear();
}
