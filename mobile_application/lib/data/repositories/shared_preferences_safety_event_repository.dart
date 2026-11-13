import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/safety_event.dart';
import '../../services/secure_storage.dart';
import '../contracts/safety_repository.dart';

class SharedPreferencesSafetyEventRepository implements SafetyEventRepository {
  SharedPreferencesSafetyEventRepository(this._preferences, {SecureKeyValueStore? secureStore})
      : _secureStore = secureStore;

  static const _eventsKey = 'safety.events';

  final SharedPreferences _preferences;
  final SecureKeyValueStore? _secureStore;

  @override
  Future<List<SafetyEvent>> listEvents() async {
    final encodedEvents = _secureStore != null
        ? await _secureStore.readStringList(_eventsKey, legacyPreferences: _preferences)
        : (_preferences.getStringList(_eventsKey) ?? const []);
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

    final encoded = events.map((item) => jsonEncode(item.toMap())).toList();
    if (_secureStore != null) {
      await _secureStore.writeStringList(_eventsKey, encoded);
    } else {
      await _preferences.setStringList(_eventsKey, encoded);
    }
  }
}
