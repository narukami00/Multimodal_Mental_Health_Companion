import '../../core/models/safety_event.dart';

abstract interface class SafetyEventRepository {
  Future<List<SafetyEvent>> listEvents();

  Future<void> save(SafetyEvent event);
}
