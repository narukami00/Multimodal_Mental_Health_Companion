import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/suggestion_record.dart';
import '../contracts/suggestion_repository.dart';

class SharedPreferencesSuggestionRepository implements SuggestionRepository {
  SharedPreferencesSuggestionRepository(this._preferences);

  static const _recordsKey = 'suggestions.records';
  final SharedPreferences _preferences;

  @override
  Future<List<SuggestionRecord>> listRecords() async {
    final encoded = _preferences.getString(_recordsKey);
    if (encoded == null) return const [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is List<dynamic>) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(SuggestionRecord.fromMap)
            .toList();
      }
    } on FormatException {
      // Corrupt local suggestion history should not block app startup.
    }
    return const [];
  }

  @override
  Future<void> saveRecord(SuggestionRecord record) async {
    final records = await listRecords();
    final updated = [...records];
    final index = updated.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      updated.add(record);
    } else {
      updated[index] = record;
    }
    await _preferences.setString(
      _recordsKey,
      jsonEncode(updated.map((item) => item.toMap()).toList()),
    );
  }
}
