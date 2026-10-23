import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the person's face is read in a video journal.
enum FaceReadingPlace {
  /// Video frames go to the companion server, which reads them (as it always has).
  server,

  /// The phone reads the frames itself; only 1,400 numbers describing the face ever leave it, never pictures.
  phone,
}

/// The person's choice of [FaceReadingPlace]. The server stays the default: nothing changes until they choose the phone.
class FaceReadingChoice extends ChangeNotifier {
  FaceReadingChoice({SharedPreferences? preferences})
      : _preferences = preferences,
        _place = _read(preferences);

  static const preferenceKey = 'face_reading_place';

  final SharedPreferences? _preferences;
  FaceReadingPlace _place;

  FaceReadingPlace get place => _place;

  static FaceReadingPlace _read(SharedPreferences? preferences) {
    final stored = preferences?.getString(preferenceKey);
    return FaceReadingPlace.values.firstWhere((p) => p.name == stored, orElse: () => FaceReadingPlace.server);
  }

  Future<void> set(FaceReadingPlace place) async {
    if (place == _place) return;
    _place = place;
    notifyListeners();
    try {
      await _preferences?.setString(preferenceKey, place.name);
    } catch (_) {}
  }
}
