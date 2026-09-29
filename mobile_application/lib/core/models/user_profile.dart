enum QuizBlock { erqS, gad7, phq9 }

class UserProfile {
  const UserProfile({
    this.preferredActivities = const [],
    this.constraints = const [],
    this.interactionPreferences = const [],
    this.neverSuggest = const [],
    this.preferencesCompleted = false,
    this.skippedBlocks = const [],
    this.erqSAnswers = const {},
    this.gad7Answers = const {},
    this.phq9Answers = const {},
    this.baselineCompletedAt,
    this.displayName,
    this.avatarPath,
    this.hapticsEnabled = true,
    this.ambientAudioEnabled = false,
    this.paletteId = defaultPaletteId,
    this.firstRunAt,
    this.reminderEnabled = false,
    this.reminderMinutes = defaultReminderMinutes,
  });

  /// Identifier of the default colour palette.
  static const defaultPaletteId = 'warmCream';

  /// Default daily reminder time, 8:30 PM, as minutes past midnight.
  static const defaultReminderMinutes = 20 * 60 + 30;

  final List<String> preferredActivities;
  final List<String> constraints;
  final List<String> interactionPreferences;
  final List<String> neverSuggest;
  final bool preferencesCompleted;
  final List<String> skippedBlocks;
  final Map<String, int> erqSAnswers;
  final Map<String, int> gad7Answers;
  final Map<String, int> phq9Answers;
  final DateTime? baselineCompletedAt;

  /// User-chosen display name. Null until the user sets one from the You tab.
  final String? displayName;

  /// Absolute path to a user-picked profile photo in app-private storage.
  final String? avatarPath;

  /// Whether gentle haptic feedback is enabled across the app.
  final bool hapticsEnabled;

  /// Whether ambient breath audio may play during grounding and pause moments.
  final bool ambientAudioEnabled;

  /// Identifier of the active colour palette (see `SolaceColors`).
  final String paletteId;

  /// First launch time, used to show an honest "member since" date.
  final DateTime? firstRunAt;

  /// Whether the daily check-in reminder is scheduled.
  final bool reminderEnabled;

  /// Reminder time as minutes past midnight.
  final int reminderMinutes;

  bool get hasPreferences => preferredActivities.isNotEmpty;
  bool get erqSComplete => erqSAnswers.length == 6;
  bool get gad7Complete => gad7Answers.length == 7;
  bool get phq9Complete => phq9Answers.length == 9;
  bool get erqSSkipped => skippedBlocks.contains(QuizBlock.erqS.name);
  bool get gad7Skipped => skippedBlocks.contains(QuizBlock.gad7.name);
  bool get phq9Skipped => skippedBlocks.contains(QuizBlock.phq9.name);
  bool get baselineComplete =>
      preferencesCompleted &&
      (erqSComplete || erqSSkipped) &&
      (gad7Complete || gad7Skipped) &&
      (phq9Complete || phq9Skipped);

  UserProfile copyWith({
    List<String>? preferredActivities,
    List<String>? constraints,
    List<String>? interactionPreferences,
    List<String>? neverSuggest,
    bool? preferencesCompleted,
    List<String>? skippedBlocks,
    Map<String, int>? erqSAnswers,
    Map<String, int>? gad7Answers,
    Map<String, int>? phq9Answers,
    DateTime? baselineCompletedAt,
    String? displayName,
    String? avatarPath,
    bool? hapticsEnabled,
    bool? ambientAudioEnabled,
    String? paletteId,
    DateTime? firstRunAt,
    bool? reminderEnabled,
    int? reminderMinutes,
  }) {
    return UserProfile(
      preferredActivities: preferredActivities ?? this.preferredActivities,
      constraints: constraints ?? this.constraints,
      interactionPreferences:
          interactionPreferences ?? this.interactionPreferences,
      neverSuggest: neverSuggest ?? this.neverSuggest,
      preferencesCompleted: preferencesCompleted ?? this.preferencesCompleted,
      skippedBlocks: skippedBlocks ?? this.skippedBlocks,
      erqSAnswers: erqSAnswers ?? this.erqSAnswers,
      gad7Answers: gad7Answers ?? this.gad7Answers,
      phq9Answers: phq9Answers ?? this.phq9Answers,
      baselineCompletedAt: baselineCompletedAt ?? this.baselineCompletedAt,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      ambientAudioEnabled: ambientAudioEnabled ?? this.ambientAudioEnabled,
      paletteId: paletteId ?? this.paletteId,
      firstRunAt: firstRunAt ?? this.firstRunAt,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'preferredActivities': preferredActivities,
      'constraints': constraints,
      'interactionPreferences': interactionPreferences,
      'neverSuggest': neverSuggest,
      'preferencesCompleted': preferencesCompleted,
      'skippedBlocks': skippedBlocks,
      'erqSAnswers': erqSAnswers,
      'gad7Answers': gad7Answers,
      'phq9Answers': phq9Answers,
      'baselineCompletedAt': baselineCompletedAt?.toIso8601String(),
      'displayName': displayName,
      'avatarPath': avatarPath,
      'hapticsEnabled': hapticsEnabled,
      'ambientAudioEnabled': ambientAudioEnabled,
      'paletteId': paletteId,
      'firstRunAt': firstRunAt?.toIso8601String(),
      'reminderEnabled': reminderEnabled,
      'reminderMinutes': reminderMinutes,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      preferredActivities: _strings(map['preferredActivities']),
      constraints: _strings(map['constraints']),
      interactionPreferences: _strings(map['interactionPreferences']),
      neverSuggest: _strings(map['neverSuggest']),
      preferencesCompleted: map['preferencesCompleted'] as bool? ?? false,
      skippedBlocks: _strings(map['skippedBlocks']),
      erqSAnswers: _answers(map['erqSAnswers']),
      gad7Answers: _answers(map['gad7Answers']),
      phq9Answers: _answers(map['phq9Answers']),
      baselineCompletedAt: DateTime.tryParse(
        map['baselineCompletedAt'] as String? ?? '',
      ),
      displayName: _nonEmpty(map['displayName']),
      avatarPath: _nonEmpty(map['avatarPath']),
      hapticsEnabled: map['hapticsEnabled'] as bool? ?? true,
      ambientAudioEnabled: map['ambientAudioEnabled'] as bool? ?? false,
      paletteId: _nonEmpty(map['paletteId']) ?? defaultPaletteId,
      firstRunAt: DateTime.tryParse(map['firstRunAt'] as String? ?? ''),
      reminderEnabled: map['reminderEnabled'] as bool? ?? false,
      reminderMinutes:
          (map['reminderMinutes'] as num?)?.toInt() ?? defaultReminderMinutes,
    );
  }

  /// Returns a trimmed string, or null when absent or blank.
  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _strings(Object? value) {
    return (value as List<dynamic>? ?? const []).whereType<String>().toList();
  }

  static Map<String, int> _answers(Object? value) {
    final map = value as Map<dynamic, dynamic>?;
    if (map == null) return {};
    return {
      for (final entry in map.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
  }
}
