import '../../core/models/daily_features.dart';

/// Groups of features that tend to move together.
///
/// Screen time and pickups rise and fall as one, so two of them shifting is one
/// event seen twice, not two pieces of evidence. A shift is only treated as
/// worth mentioning when it shows in more than one family.
enum PatternFamily {
  /// How much and how often the screen is used.
  screen,

  /// When the day starts and ends, and sleep.
  rhythm,

  /// How time is split between kinds of app.
  apps,

  /// What the person said about how they feel.
  mood,
}

/// A number a day that can be compared with the person's own usual.
///
/// Deliberately the phone's behavior and the person's own mood word, and not
/// how much they use Solace: check-ins, words written and chat time are left
/// out. A quiet spell in the app is not something to chase someone about.
enum PatternFeature {
  screenOnMinutes(PatternFamily.screen, 'screen time', 10),
  unlockCount(PatternFamily.screen, 'unlocks', 5),
  sessionCount(PatternFamily.screen, 'pickups', 5),
  longestSessionMinutes(PatternFamily.screen, 'longest stretch', 5),
  appSwitchRate(PatternFamily.screen, 'app switching', 1),

  firstPickupMinute(PatternFamily.rhythm, 'first pickup', 30),
  lastUseMinute(PatternFamily.rhythm, 'last use', 30),
  sleepOnset(PatternFamily.rhythm, 'phone-down time', 30),
  sleepMinutes(PatternFamily.rhythm, 'time phone was down overnight', 30),
  screenMinutesInSleepWindow(PatternFamily.rhythm, 'use in sleep hours', 5),

  socialMinutes(PatternFamily.apps, 'social time', 10),
  messagingMinutes(PatternFamily.apps, 'messaging time', 10),
  videoMinutes(PatternFamily.apps, 'video time', 10),
  gamesMinutes(PatternFamily.apps, 'games time', 10),

  moodScore(PatternFamily.mood, 'mood', 0.25);

  const PatternFeature(this.family, this.label, this.minScale);

  final PatternFamily family;

  /// Plain words for the feature, for context lines. Never shown as a score.
  final String label;

  /// The smallest spread worth treating as real, in the feature's own unit.
  /// Without it a person who is very regular would have a spread near zero and
  /// every ordinary wobble would look like a break.
  final double minScale;

  /// The feature's value for [row], or null if the row did not collect it.
  double? valueOf(DailyFeatures row) {
    switch (this) {
      case PatternFeature.screenOnMinutes:
        return _d(row.screenOnMinutes);
      case PatternFeature.unlockCount:
        return _d(row.unlockCount);
      case PatternFeature.sessionCount:
        return _d(row.sessionCount);
      case PatternFeature.longestSessionMinutes:
        return _d(row.longestSessionMinutes);
      case PatternFeature.appSwitchRate:
        return row.appSwitchRate;
      case PatternFeature.firstPickupMinute:
        return _d(row.firstPickupMinute);
      case PatternFeature.lastUseMinute:
        return _d(row.lastUseMinute);
      case PatternFeature.sleepOnset:
        return _shiftedOnset(row.estimatedSleepStartMinute);
      case PatternFeature.sleepMinutes:
        return _d(row.estimatedSleepMinutes);
      case PatternFeature.screenMinutesInSleepWindow:
        return _d(row.screenMinutesInSleepWindow);
      case PatternFeature.socialMinutes:
        return _category(row, 'social');
      case PatternFeature.messagingMinutes:
        return _category(row, 'messaging');
      case PatternFeature.videoMinutes:
        return _category(row, 'video');
      case PatternFeature.gamesMinutes:
        return _category(row, 'games');
      case PatternFeature.moodScore:
        return row.selfMoodMedian;
    }
  }

  static double? _d(int? value) => value?.toDouble();

  /// Category minutes, where the row has category totals at all. A category with
  /// no entry in a row that has totals is a real zero for that day.
  static double? _category(DailyFeatures row, String name) {
    final totals = row.categoryMinutes;
    if (totals == null) return null;
    return (totals[name] ?? 0).toDouble();
  }

  /// Phone-down time as minutes after 18:00, so 23:30 and 00:30 are an hour
  /// apart instead of most of a day. Nights fall between 18:00 and 18:00.
  static double? _shiftedOnset(int? minuteOfDay) {
    if (minuteOfDay == null) return null;
    const evening = 18 * 60;
    return ((minuteOfDay - evening) % 1440).toDouble();
  }
}
