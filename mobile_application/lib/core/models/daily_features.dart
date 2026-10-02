import '../day_key.dart';

/// Minutes an app category (or one app) was in the foreground in a day.
class AppUsage {
  const AppUsage({required this.name, required this.minutes});

  final String name;
  final int minutes;

  Map<String, Object?> toMap() => {'name': name, 'minutes': minutes};

  static AppUsage? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final minutes = raw['minutes'];
    if (name is! String || name.trim().isEmpty || minutes is! num) return null;
    return AppUsage(name: name, minutes: minutes.toInt().clamp(0, 24 * 60));
  }
}

/// One local day of derived behavior, the only thing kept from phone usage.
///
/// Raw usage events are read, reduced into this row and discarded, so a day is a
/// handful of numbers and never a trail of what was opened when.
///
/// Every field is nullable and **null means "not collected"**, never zero: a
/// day with no usage access has no screen time, not zero screen time. Rows are
/// built by separate sources (device usage, in-app activity, emotion results),
/// so [mergedWith] combines them without one erasing another.
class DailyFeatures {
  const DailyFeatures({
    required this.dayKey,
    this.sources = const {},
    this.schemaVersion = currentSchemaVersion,
    this.screenOnMinutes,
    this.unlockCount,
    this.sessionCount,
    this.longestSessionMinutes,
    this.appSwitchRate,
    this.hourlyActiveMinutes,
    this.firstPickupMinute,
    this.lastUseMinute,
    this.estimatedSleepStartMinute,
    this.estimatedSleepEndMinute,
    this.estimatedSleepMinutes,
    this.screenMinutesInSleepWindow,
    this.lastUseDelayVsStatedBedtimeMinutes,
    this.categoryMinutes,
    this.topApps,
    this.checkInCount,
    this.firstCheckInMinute,
    this.checkInLatencyMinutes,
    this.selfMoodMedian,
    this.journalWordCount,
    this.chatMinutes,
  });

  static const currentSchemaVersion = 1;

  /// Local `yyyy-MM-dd`, from [dayKey]. Sorts correctly as a string.
  final String dayKey;

  /// Which collectors contributed (`usage`, `inApp`, `emotion`).
  final Set<String> sources;
  final int schemaVersion;

  // Screen.
  final int? screenOnMinutes;
  final int? unlockCount;
  final int? sessionCount;
  final int? longestSessionMinutes;

  /// App switches per hour of screen-on time.
  final double? appSwitchRate;

  // Rhythm.
  /// Screen-on minutes in each local hour, 24 entries.
  final List<int>? hourlyActiveMinutes;
  final int? firstPickupMinute;
  final int? lastUseMinute;

  // Sleep, as an estimate with the limits that implies.
  final int? estimatedSleepStartMinute;
  final int? estimatedSleepEndMinute;
  final int? estimatedSleepMinutes;

  /// Screen-on minutes that fell inside the user's stated sleep window.
  final int? screenMinutesInSleepWindow;

  /// Minutes the last use of the evening ran past stated bedtime. Negative when
  /// the phone went down early.
  final int? lastUseDelayVsStatedBedtimeMinutes;

  // Apps. Category totals are the default; [topApps] exists only with the
  // separate on-device consent and is never sent anywhere.
  final Map<String, int>? categoryMinutes;
  final List<AppUsage>? topApps;

  // In-app activity.
  final int? checkInCount;

  /// Minute of the local day the first check-in happened.
  final int? firstCheckInMinute;

  /// Minutes from the daily reminder to the first check-in. Negative when the
  /// check-in came before the reminder.
  final int? checkInLatencyMinutes;
  final double? selfMoodMedian;
  final int? journalWordCount;
  final int? chatMinutes;

  /// The calendar date this row describes.
  DateTime get date {
    final parts = dayKey.split('-');
    return DateTime(
      int.tryParse(parts[0]) ?? 1970,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1,
      parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1,
    );
  }

  /// Whether any usage-derived signal is present.
  bool get hasUsage => sources.contains('usage');

  /// Whether the day's device data is complete. A day read while it was still
  /// going has only part of its usage, so it is not safe to compare with whole
  /// days. A row with no device data has nothing to be incomplete.
  bool get usageComplete => !hasUsage || sources.contains('usageFinal');

  /// Combines two rows for the same day. A value in [other] replaces the same
  /// field here; a field [other] has no value for keeps what this row had.
  DailyFeatures mergedWith(DailyFeatures other) {
    assert(
      other.dayKey == dayKey,
      'Rows for different days must not be merged.',
    );
    return DailyFeatures(
      dayKey: dayKey,
      sources: {...sources, ...other.sources},
      schemaVersion: schemaVersion > other.schemaVersion
          ? schemaVersion
          : other.schemaVersion,
      screenOnMinutes: other.screenOnMinutes ?? screenOnMinutes,
      unlockCount: other.unlockCount ?? unlockCount,
      sessionCount: other.sessionCount ?? sessionCount,
      longestSessionMinutes:
          other.longestSessionMinutes ?? longestSessionMinutes,
      appSwitchRate: other.appSwitchRate ?? appSwitchRate,
      hourlyActiveMinutes: other.hourlyActiveMinutes ?? hourlyActiveMinutes,
      firstPickupMinute: other.firstPickupMinute ?? firstPickupMinute,
      lastUseMinute: other.lastUseMinute ?? lastUseMinute,
      estimatedSleepStartMinute:
          other.estimatedSleepStartMinute ?? estimatedSleepStartMinute,
      estimatedSleepEndMinute:
          other.estimatedSleepEndMinute ?? estimatedSleepEndMinute,
      estimatedSleepMinutes:
          other.estimatedSleepMinutes ?? estimatedSleepMinutes,
      screenMinutesInSleepWindow:
          other.screenMinutesInSleepWindow ?? screenMinutesInSleepWindow,
      lastUseDelayVsStatedBedtimeMinutes:
          other.lastUseDelayVsStatedBedtimeMinutes ??
          lastUseDelayVsStatedBedtimeMinutes,
      categoryMinutes: other.categoryMinutes ?? categoryMinutes,
      topApps: other.topApps ?? topApps,
      checkInCount: other.checkInCount ?? checkInCount,
      firstCheckInMinute: other.firstCheckInMinute ?? firstCheckInMinute,
      checkInLatencyMinutes:
          other.checkInLatencyMinutes ?? checkInLatencyMinutes,
      selfMoodMedian: other.selfMoodMedian ?? selfMoodMedian,
      journalWordCount: other.journalWordCount ?? journalWordCount,
      chatMinutes: other.chatMinutes ?? chatMinutes,
    );
  }

  /// This row with the app names removed, for when that consent is withdrawn.
  DailyFeatures withoutAppNames() => DailyFeatures(
    dayKey: dayKey,
    sources: sources,
    schemaVersion: schemaVersion,
    screenOnMinutes: screenOnMinutes,
    unlockCount: unlockCount,
    sessionCount: sessionCount,
    longestSessionMinutes: longestSessionMinutes,
    appSwitchRate: appSwitchRate,
    hourlyActiveMinutes: hourlyActiveMinutes,
    firstPickupMinute: firstPickupMinute,
    lastUseMinute: lastUseMinute,
    estimatedSleepStartMinute: estimatedSleepStartMinute,
    estimatedSleepEndMinute: estimatedSleepEndMinute,
    estimatedSleepMinutes: estimatedSleepMinutes,
    screenMinutesInSleepWindow: screenMinutesInSleepWindow,
    lastUseDelayVsStatedBedtimeMinutes: lastUseDelayVsStatedBedtimeMinutes,
    categoryMinutes: categoryMinutes,
    checkInCount: checkInCount,
    firstCheckInMinute: firstCheckInMinute,
    checkInLatencyMinutes: checkInLatencyMinutes,
    selfMoodMedian: selfMoodMedian,
    journalWordCount: journalWordCount,
    chatMinutes: chatMinutes,
  );

  /// This row with everything read from the device removed, keeping what the
  /// app itself recorded (check-ins, mood words, words written, chat time).
  ///
  /// The result has no sources left when the row held only device data, which
  /// is how a repository knows the whole row can go.
  DailyFeatures withoutUsage() => DailyFeatures(
    dayKey: dayKey,
    sources: {
      for (final source in sources)
        if (source != 'usage' && source != 'usageFinal') source,
    },
    schemaVersion: schemaVersion,
    checkInCount: checkInCount,
    firstCheckInMinute: firstCheckInMinute,
    checkInLatencyMinutes: checkInLatencyMinutes,
    selfMoodMedian: selfMoodMedian,
    journalWordCount: journalWordCount,
    chatMinutes: chatMinutes,
  );

  /// Only fields with a value are written, so a stored row says exactly what
  /// was collected.
  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'dayKey': dayKey,
      'schemaVersion': schemaVersion,
      'sources': sources.toList()..sort(),
    };
    void put(String key, Object? value) {
      if (value != null) map[key] = value;
    }

    put('screenOnMinutes', screenOnMinutes);
    put('unlockCount', unlockCount);
    put('sessionCount', sessionCount);
    put('longestSessionMinutes', longestSessionMinutes);
    put('appSwitchRate', appSwitchRate);
    put('hourlyActiveMinutes', hourlyActiveMinutes);
    put('firstPickupMinute', firstPickupMinute);
    put('lastUseMinute', lastUseMinute);
    put('estimatedSleepStartMinute', estimatedSleepStartMinute);
    put('estimatedSleepEndMinute', estimatedSleepEndMinute);
    put('estimatedSleepMinutes', estimatedSleepMinutes);
    put('screenMinutesInSleepWindow', screenMinutesInSleepWindow);
    put(
      'lastUseDelayVsStatedBedtimeMinutes',
      lastUseDelayVsStatedBedtimeMinutes,
    );
    put('categoryMinutes', categoryMinutes);
    put('topApps', topApps?.map((app) => app.toMap()).toList());
    put('checkInCount', checkInCount);
    put('firstCheckInMinute', firstCheckInMinute);
    put('checkInLatencyMinutes', checkInLatencyMinutes);
    put('selfMoodMedian', selfMoodMedian);
    put('journalWordCount', journalWordCount);
    put('chatMinutes', chatMinutes);
    return map;
  }

  /// Reads a stored row, or null if it has no usable day. Out-of-range values
  /// become null ("not collected") instead of corrupting later statistics.
  static DailyFeatures? fromMap(Map<String, dynamic> map) {
    final key = map['dayKey'];
    if (key is! String || !_dayKeyPattern.hasMatch(key)) return null;

    return DailyFeatures(
      dayKey: key,
      sources: {
        for (final source in map['sources'] as List<dynamic>? ?? const [])
          if (source is String) source,
      },
      schemaVersion:
          (map['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
      screenOnMinutes: _minutesOfDay(map['screenOnMinutes'], max: 24 * 60),
      unlockCount: _count(map['unlockCount']),
      sessionCount: _count(map['sessionCount']),
      longestSessionMinutes: _minutesOfDay(
        map['longestSessionMinutes'],
        max: 24 * 60,
      ),
      appSwitchRate: _nonNegative(map['appSwitchRate']),
      hourlyActiveMinutes: _hourly(map['hourlyActiveMinutes']),
      firstPickupMinute: _minuteOfDay(map['firstPickupMinute']),
      lastUseMinute: _minuteOfDay(map['lastUseMinute']),
      estimatedSleepStartMinute: _minuteOfDay(map['estimatedSleepStartMinute']),
      estimatedSleepEndMinute: _minuteOfDay(map['estimatedSleepEndMinute']),
      estimatedSleepMinutes: _minutesOfDay(
        map['estimatedSleepMinutes'],
        max: 24 * 60,
      ),
      screenMinutesInSleepWindow: _minutesOfDay(
        map['screenMinutesInSleepWindow'],
        max: 24 * 60,
      ),
      lastUseDelayVsStatedBedtimeMinutes: _signedMinutes(
        map['lastUseDelayVsStatedBedtimeMinutes'],
      ),
      categoryMinutes: _categories(map['categoryMinutes']),
      topApps: _topApps(map['topApps']),
      checkInCount: _count(map['checkInCount']),
      firstCheckInMinute: _minuteOfDay(map['firstCheckInMinute']),
      checkInLatencyMinutes: _signedMinutes(map['checkInLatencyMinutes']),
      selfMoodMedian: (map['selfMoodMedian'] as num?)?.toDouble(),
      journalWordCount: _count(map['journalWordCount']),
      chatMinutes: _minutesOfDay(map['chatMinutes'], max: 24 * 60),
    );
  }

  static final _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static int? _count(Object? value) {
    if (value is! num) return null;
    final count = value.toInt();
    return count < 0 ? null : count;
  }

  static int? _minutesOfDay(Object? value, {required int max}) {
    if (value is! num) return null;
    final minutes = value.toInt();
    return minutes < 0 || minutes > max ? null : minutes;
  }

  static int? _minuteOfDay(Object? value) {
    if (value is! num) return null;
    final minute = value.toInt();
    return minute < 0 || minute >= 24 * 60 ? null : minute;
  }

  static int? _signedMinutes(Object? value) {
    if (value is! num) return null;
    final minutes = value.toInt();
    return minutes.abs() > 7 * 24 * 60 ? null : minutes;
  }

  static double? _nonNegative(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isFinite && number >= 0 ? number : null;
  }

  static List<int>? _hourly(Object? value) {
    if (value is! List || value.length != 24) return null;
    final hours = <int>[];
    for (final entry in value) {
      if (entry is! num) return null;
      final minutes = entry.toInt();
      if (minutes < 0 || minutes > 60) return null;
      hours.add(minutes);
    }
    return List.unmodifiable(hours);
  }

  static Map<String, int>? _categories(Object? value) {
    if (value is! Map) return null;
    final result = <String, int>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! num) continue;
      final minutes = (entry.value as num).toInt();
      if (minutes >= 0 && minutes <= 24 * 60) {
        result[entry.key as String] = minutes;
      }
    }
    return Map.unmodifiable(result);
  }

  static List<AppUsage>? _topApps(Object? value) {
    if (value is! List) return null;
    return List.unmodifiable([
      for (final entry in value)
        if (AppUsage.fromMap(entry) case final app?) app,
    ]);
  }
}

/// The oldest day key kept when rows are retained for [retentionDays].
///
/// Counts calendar days rather than 24-hour spans, so a daylight-saving change
/// cannot shift the cutoff by a day. Rows with a key before this are pruned.
String retentionCutoffDayKey(DateTime now, int retentionDays) {
  final today = dateOnly(now);
  return dayKey(
    DateTime(today.year, today.month, today.day - (retentionDays - 1)),
  );
}
