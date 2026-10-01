import '../../core/models/consent.dart';

abstract interface class ConsentRepository {
  Future<ConsentLedger> load();
  Future<void> save(ConsentLedger ledger);
}
