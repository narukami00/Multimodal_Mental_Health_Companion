import 'package:flutter/foundation.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/safety_event.dart';
import '../../data/contracts/provider_contracts.dart';
import '../../data/contracts/safety_repository.dart';

class SafetyController extends ChangeNotifier {
  SafetyController({
    required SafetyScreener screener,
    required SafetyEventRepository repository,
  })  : _screener = screener,
        _repository = repository;

  final SafetyScreener _screener;
  final SafetyEventRepository _repository;
  SafetyEvent? _latestEvent;
  SafetyAssessment? _activeAssessment;

  SafetyEvent? get latestEvent => _latestEvent;
  SafetyAssessment? get activeAssessment => _activeAssessment;
  bool get hasActiveFlag => _activeAssessment != null;

  Future<void> load() async {
    final events = await _repository.listEvents();
    if (events.isEmpty) return;

    _latestEvent = events.first;
    if (_latestEvent!.handledBy != 'support_resources') {
      _activeAssessment = SafetyAssessment(
        level: _latestEvent!.level,
        matchedSignals: _latestEvent!.matchedSignals,
      );
    }
    notifyListeners();
  }

  Future<SafetyAssessment> assessText({
    required String source,
    required String text,
  }) async {
    final assessment = _screener.assess(text);
    if (assessment.level == SafetyLevel.clear) return assessment;

    final event = SafetyEvent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      source: source,
      level: assessment.level,
      matchedSignals: assessment.matchedSignals,
      handledBy: 'support_resources_pending',
    );
    await _repository.save(event);
    _latestEvent = event;
    _activeAssessment = assessment;
    notifyListeners();
    return assessment;
  }

  Future<void> markSupportShown() async {
    final event = _latestEvent;
    if (event == null) return;

    final handledEvent = SafetyEvent(
      id: event.id,
      createdAt: event.createdAt,
      source: event.source,
      level: event.level,
      matchedSignals: event.matchedSignals,
      handledBy: 'support_resources',
    );
    await _repository.save(handledEvent);
    _latestEvent = handledEvent;
    _activeAssessment = null;
    notifyListeners();
  }
}
