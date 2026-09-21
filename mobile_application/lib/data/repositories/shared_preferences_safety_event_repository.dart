import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/safety_event.dart';
import '../contracts/safety_repository.dart';

class SharedPreferencesSafetyEventRepository implements SafetyEventRepository {
  SharedPreferencesSafetyEventRepository(this._preferences);

  static const _eventsKey = 'safety.events';

  final SharedPreferences _preferences;

  @override
  Future<List<SafetyEvent>> listEvents() async {
    final encodedEvents = _preferences.getStringList(_eventsKey) ?? const [];
    final events = <SafetyEvent>[];
    for (final encoded in encodedEvents) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) {
          events.add(SafetyEvent.fromMap(decoded));
        }
      } on FormatException {
        // A malformed local event must not prevent support resources opening.
      }
    }
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(events);
  }

  @override
  Future<void> save(SafetyEvent event) async {
    final events = (await listEvents())
        .where((item) => item.id != event.id)
        .toList()
      ..add(event);
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    await _preferences.setStringList(
      _eventsKey,
      events.map((item) => jsonEncode(item.toMap())).toList(),
    );
  }
}
