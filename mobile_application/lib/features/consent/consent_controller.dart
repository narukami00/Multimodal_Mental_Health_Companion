import 'package:flutter/foundation.dart';

import '../../core/models/consent.dart';
import '../../data/contracts/consent_repository.dart';

/// Holds what the user has agreed to, for the few things that need it.
///
/// Everything fails closed: until [load] completes, and for anything never
/// asked, declined, revoked or out of date, [isGranted] is false.
class ConsentController extends ChangeNotifier {
  ConsentController({
    required ConsentRepository repository,
    DateTime Function()? clock,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now;

  final ConsentRepository _repository;
  final DateTime Function() _clock;
  ConsentLedger _ledger = const ConsentLedger();
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Every decision made so far, oldest first.
  List<ConsentEvent> get history => _ledger.events;

  Future<void> load() async {
    _ledger = await _repository.load();
    _isLoaded = true;
    notifyListeners();
  }

  /// Whether the feature behind [key] may run right now.
  bool isGranted(ConsentKey key) => _ledger.isGranted(key);

  ConsentStatus statusOf(ConsentKey key) => _ledger.statusOf(key);

  /// Records agreement to the text currently on offer for [key].
  Future<void> grant(ConsentKey key) =>
      _decide(key, ConsentStatus.granted);

  /// Records a considered "no". A completed choice, so callers must not ask
  /// again unprompted.
  Future<void> decline(ConsentKey key) =>
      _decide(key, ConsentStatus.declined);

  /// Withdraws an earlier grant. A key never granted is left alone, since
  /// "revoked" would claim something that did not happen.
  Future<void> revoke(ConsentKey key) async {
    final status = _ledger.statusOf(key);
    if (status != ConsentStatus.granted &&
        status != ConsentStatus.needsReconsent) {
      return;
    }
    await _decide(key, ConsentStatus.revoked);
  }

  Future<void> _decide(ConsentKey key, ConsentStatus status) async {
    _ledger = _ledger.record(
      ConsentEvent(
        key: key.key,
        status: status,
        textVersion: key.currentVersion,
        occurredAt: _clock(),
      ),
    );
    await _repository.save(_ledger);
    notifyListeners();
  }
}
