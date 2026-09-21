import '../../core/models/suggestion_record.dart';
import '../contracts/suggestion_repository.dart';

class InMemorySuggestionRepository implements SuggestionRepository {
  final List<SuggestionRecord> _records = [];

  @override
  Future<List<SuggestionRecord>> listRecords() async {
    return List.unmodifiable(_records);
  }

  @override
  Future<void> saveRecord(SuggestionRecord record) async {
    final index = _records.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      _records.add(record);
    } else {
      _records[index] = record;
    }
  }
}
