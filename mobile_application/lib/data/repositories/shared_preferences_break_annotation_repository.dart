import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/break_annotation.dart';
import '../contracts/break_annotation_repository.dart';

class SharedPreferencesBreakAnnotationRepository
    implements BreakAnnotationRepository {
  SharedPreferencesBreakAnnotationRepository(this._preferences);

  static const _key = 'footprint.breakAnnotations';
  final SharedPreferences _preferences;

  Map<String, BreakAnnotation> _read() {
    final encoded = _preferences.getString(_key);
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return {};
      return {
        for (final entry in decoded)
          if (BreakAnnotation.fromMap(entry) case final annotation?)
            annotation.breakKey: annotation,
      };
    } on FormatException {
      // Unreadable history is dropped; the worst case is one repeated question.
      return {};
    }
  }

  @override
  Future<List<BreakAnnotation>> loadAll() async {
    final all = _read().values.toList()
      ..sort((a, b) => a.shownAt.compareTo(b.shownAt));
    return List.unmodifiable(all);
  }

  @override
  Future<void> save(BreakAnnotation annotation) async {
    final all = _read()..[annotation.breakKey] = annotation;
    await _preferences.setString(
      _key,
      jsonEncode([for (final item in all.values) item.toMap()]),
    );
  }

  @override
  Future<void> deleteAll() async {
    await _preferences.remove(_key);
  }
}
