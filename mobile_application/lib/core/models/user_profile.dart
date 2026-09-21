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
  });

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
    );
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
