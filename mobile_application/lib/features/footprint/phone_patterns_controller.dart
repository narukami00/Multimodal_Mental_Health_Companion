import 'package:flutter/foundation.dart';

import '../../core/models/consent.dart';
import '../../core/models/daily_features.dart';
import '../../data/contracts/daily_features_repository.dart';
import '../../services/usage_collector_service.dart';
import '../consent/consent_controller.dart';

/// Where "phone patterns" stands for this person right now.
enum PhonePatternsStatus {
  /// Not turned on, or turned off. Nothing is read.
  off,

  /// They said yes, but Android's usage access is not granted, so nothing is
  /// being read. Android owns that switch and may have been changed by the user
  /// in system settings at any time.
  needsAndroidAccess,

  /// Both agreed: Solace reads and keeps daily patterns on this phone.
  on,
}

/// Ties together the three things that must all be true before any device usage
/// is read: the person's consent, Android's usage access, and what is already
/// stored.
///
/// The OS state is read, never assumed. A person can revoke access in system
/// settings without telling Solace, so [refresh] is called whenever the app
/// returns to the foreground, and collection runs only while [status] is
/// [PhonePatternsStatus.on].
class PhonePatternsController extends ChangeNotifier {
  PhonePatternsController({
    required ConsentController consent,
    required UsageCollectorService collector,
    required DailyFeaturesRepository repository,
  }) : _consent = consent,
       _collector = collector,
       _repository = repository {
    _consent.addListener(notifyListeners);
  }

  final ConsentController _consent;
  final UsageCollectorService _collector;
  final DailyFeaturesRepository _repository;
  bool _androidAccess = false;

  PhonePatternsStatus get status {
    if (!_consent.isGranted(ConsentKey.usageFootprint)) {
      return PhonePatternsStatus.off;
    }
    return _androidAccess
        ? PhonePatternsStatus.on
        : PhonePatternsStatus.needsAndroidAccess;
  }

  /// Whether collection may run right now.
  bool get isCollecting => status == PhonePatternsStatus.on;

  /// Whether the person agreed to keep the names of individual apps. Only
  /// meaningful while [isCollecting].
  bool get keepsAppNames =>
      isCollecting && _consent.isGranted(ConsentKey.topAppNames);

  /// Tells listeners that stored days changed underneath them, so a page that
  /// is open shows new data as it arrives instead of only on its next visit.
  void dataChanged() => notifyListeners();

  /// Re-reads Android's usage access. Safe to call often.
  Future<void> refresh() async {
    final granted = await _collector.hasAccess();
    if (granted == _androidAccess) return;
    _androidAccess = granted;
    notifyListeners();
  }

  /// Records agreement, then sends the person to Android's screen if usage
  /// access is not yet on. Returns false only when that screen could not open.
  Future<bool> turnOn() async {
    await _consent.grant(ConsentKey.usageFootprint);
    await refresh();
    if (_androidAccess) return true;
    return _collector.openAccessSettings();
  }

  /// Opens Android's usage access screen, for someone who already agreed.
  Future<bool> openAndroidSettings() => _collector.openAccessSettings();

  /// Withdraws consent. Nothing more is read. [deleteStored] also removes the
  /// days already kept; without it they stay, since turning something off and
  /// erasing it are different requests. Names of individual apps always go,
  /// because their separate consent ends with this one.
  Future<void> turnOff({bool deleteStored = false}) async {
    await _consent.revoke(ConsentKey.topAppNames);
    await _consent.revoke(ConsentKey.usageFootprint);
    if (deleteStored) {
      await _repository.removeUsageData();
    } else {
      await _repository.removeAppNames();
    }
    notifyListeners();
  }

  /// Agrees, or stops agreeing, to keep the names of the most-used apps.
  Future<void> setKeepAppNames(bool keep) async {
    if (keep) {
      await _consent.grant(ConsentKey.topAppNames);
    } else {
      await _consent.revoke(ConsentKey.topAppNames);
      await _repository.removeAppNames();
    }
    notifyListeners();
  }

  /// How many days of phone patterns are stored, for saying so before deleting
  /// them. Days that hold only what the app recorded itself are not counted:
  /// nothing was read from the phone for them.
  Future<int> storedDayCount() async =>
      (await _repository.loadAll()).where((row) => row.hasUsage).length;

  /// Every stored day, oldest first, for showing the person their own patterns.
  Future<List<DailyFeatures>> storedDays() => _repository.loadAll();

  /// Removes stored days older than the retention the person chose, straight
  /// away, so shortening it takes effect now rather than at the next cleanup.
  /// Returns how many days went.
  Future<int> pruneTo(int retentionDays, {DateTime? now}) async {
    final removed = await _repository.deleteBefore(
      retentionCutoffDayKey(now ?? DateTime.now(), retentionDays),
    );
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// The one-tap delete of everything read from the phone. What the app
  /// recorded itself (check-in counts and the like) is not phone data and stays.
  Future<void> deleteStored() async {
    await _repository.removeUsageData();
    notifyListeners();
  }

  @override
  void dispose() {
    _consent.removeListener(notifyListeners);
    super.dispose();
  }
}
