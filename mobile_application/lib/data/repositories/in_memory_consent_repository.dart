import '../../core/models/consent.dart';
import '../contracts/consent_repository.dart';

class InMemoryConsentRepository implements ConsentRepository {
  ConsentLedger _ledger = const ConsentLedger();

  @override
  Future<ConsentLedger> load() async => _ledger;

  @override
  Future<void> save(ConsentLedger ledger) async {
    _ledger = ledger;
  }
}
