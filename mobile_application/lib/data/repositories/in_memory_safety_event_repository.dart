import '../../core/models/safety_event.dart';
import '../contracts/safety_repository.dart';

class InMemorySafetyEventRepository implements SafetyEventRepository {
  final List<SafetyEvent> _events = [];

  @override
  Future<List<SafetyEvent>> listEvents() async {
    return List.unmodifiable(_events);
  }

  @override
  Future<void> save(SafetyEvent event) async {
    final existingIndex = _events.indexWhere((item) => item.id == event.id);
    if (existingIndex == -1) {
      _events.add(event);
    } else {
      _events[existingIndex] = event;
    }
  }
}
