import '../personalization/personal_calibration.dart';

enum LifePulseStatus { shown, answered, dismissed }

class LifePulseEntry {
  const LifePulseEntry({
    required this.key,
    required this.status,
    required this.shownAt,
    this.decidedAt,
    this.moodTag,
    this.note,
  });

  final String key;
  final LifePulseStatus status;
  final DateTime shownAt;
  final DateTime? decidedAt;
  final String? moodTag;
  final String? note;

  LifePulseEntry answered({
    required String moodTag,
    required DateTime at,
    String? note,
  }) =>
      LifePulseEntry(
        key: key,
        status: LifePulseStatus.answered,
        shownAt: shownAt,
        decidedAt: at,
        moodTag: moodTag,
        note: note,
      );

  LifePulseEntry dismissed({required DateTime at}) => LifePulseEntry(
        key: key,
        status: LifePulseStatus.dismissed,
        shownAt: shownAt,
        decidedAt: at,
      );

  Map<String, Object?> toMap() => {
        'key': key,
        'status': status.name,
        'shownAt': shownAt.toIso8601String(),
        if (decidedAt != null) 'decidedAt': decidedAt!.toIso8601String(),
        if (moodTag != null) 'moodTag': moodTag,
        if (note != null) 'note': note,
      };

  static LifePulseEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final shownAt = DateTime.tryParse(raw['shownAt'] as String? ?? '');
    if (key is! String || key.isEmpty || shownAt == null) return null;
    return LifePulseEntry(
      key: key,
      status: LifePulseStatus.values.firstWhere(
        (v) => v.name == raw['status'],
        orElse: () => LifePulseStatus.dismissed,
      ),
      shownAt: shownAt,
      decidedAt: DateTime.tryParse(raw['decidedAt'] as String? ?? ''),
      moodTag: raw['moodTag'] as String?,
      note: raw['note'] as String?,
    );
  }
}

/// How long one unanswered gentle check-in lingers on Home before fading.
const lifePulseVisibleFor = Duration(hours: 24);

/// Gentle periodic check-in cadence (~36 hours) even without extreme usage shifts.
const lifePulseCadence = Duration(hours: 36);

/// Key identifying the current check-in window.
String lifePulseKeyFor(DateTime now) {
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final half = now.hour < 14 ? 'am' : 'pm';
  return '$y-$m-$d-$half';
}

/// Decides whether the gentle "Is everything alright?" pulse widget should be shown right now.
LifePulseEntry? currentLifePulse({
  required List<LifePulseEntry> entries,
  required DateTime now,
  required bool enabled,
  required bool safetyActive,
  required bool breakPromptActive,
}) {
  if (!enabled || safetyActive || breakPromptActive) return null;

  final sorted = [...entries]..sort((a, b) => a.shownAt.compareTo(b.shownAt));
  if (sorted.isNotEmpty) {
    final latest = sorted.last;
    if (latest.status == LifePulseStatus.shown) {
      if (now.difference(latest.shownAt) < lifePulseVisibleFor) {
        return latest;
      }
      // Expired unanswered shown entry behaves like a quiet cooldown from expiry.
      final expiredAt = latest.shownAt.add(lifePulseVisibleFor);
      if (now.difference(expiredAt) < lifePulseCadence) {
        return null;
      }
    } else {
      final at = latest.decidedAt ?? latest.shownAt;
      if (now.difference(at) < lifePulseCadence) {
        return null;
      }
    }
  }

  return LifePulseEntry(
    key: lifePulseKeyFor(now),
    status: LifePulseStatus.shown,
    shownAt: now,
  );
}

/// Extracts the most recent answered check-in within [horizon] for Companion personalization.
LifePulseSignal? latestFreshLifePulse(
  List<LifePulseEntry> entries,
  DateTime now, {
  Duration horizon = const Duration(hours: 72),
}) {
  final answered = [
    for (final e in entries)
      if (e.status == LifePulseStatus.answered &&
          e.moodTag != null &&
          e.decidedAt != null &&
          now.difference(e.decidedAt!) <= horizon)
        e,
  ]..sort((a, b) => b.decidedAt!.compareTo(a.decidedAt!));

  if (answered.isEmpty) return null;
  final top = answered.first;
  return LifePulseSignal(
    moodTag: top.moodTag!,
    at: top.decidedAt!,
    note: top.note,
  );
}
