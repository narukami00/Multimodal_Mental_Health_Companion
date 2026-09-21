import '../../core/models/suggestion_record.dart';

abstract interface class SuggestionRepository {
  Future<List<SuggestionRecord>> listRecords();
  Future<void> saveRecord(SuggestionRecord record);
}
