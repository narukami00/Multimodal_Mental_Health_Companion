import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/domain/home/baseline_progress.dart';

UserProfile _profile({
  bool preferencesCompleted = false,
  Map<String, int> erqS = const {},
  Map<String, int> gad7 = const {},
  Map<String, int> phq9 = const {},
  List<String> skipped = const [],
}) {
  return UserProfile(
    preferencesCompleted: preferencesCompleted,
    erqSAnswers: erqS,
    gad7Answers: gad7,
    phq9Answers: phq9,
    skippedBlocks: skipped,
  );
}

final _fullErqS = {for (var i = 1; i <= 6; i++) 'erqS_$i': 2};
final _fullGad7 = {for (var i = 1; i <= 7; i++) 'gad7_$i': 1};
final _fullPhq9 = {for (var i = 1; i <= 9; i++) 'phq9_$i': 1};

void main() {
  test('nothing done yet', () {
    final progress = BaselineProgress.of(_profile());

    expect(progress.completed, 0);
    expect(progress.percent, 0);
    expect(progress.isComplete, isFalse);
    expect(progress.hasStarted, isFalse);
  });

  test('counts each part once', () {
    final progress = BaselineProgress.of(
      _profile(preferencesCompleted: true, erqS: _fullErqS),
    );

    expect(progress.completed, 2);
    expect(progress.percent, 50);
    expect(progress.isComplete, isFalse);
  });

  test('a skipped part counts as done', () {
    // Declining a questionnaire is an answer, not a gap, and nothing here
    // should make someone look behind for it.
    final progress = BaselineProgress.of(
      _profile(
        preferencesCompleted: true,
        skipped: const ['erqS', 'gad7', 'phq9'],
      ),
    );

    expect(progress.completed, 4);
    expect(progress.isComplete, isTrue);
    expect(progress.percent, 100);
  });

  test('everything answered is complete', () {
    final progress = BaselineProgress.of(
      _profile(
        preferencesCompleted: true,
        erqS: _fullErqS,
        gad7: _fullGad7,
        phq9: _fullPhq9,
      ),
    );

    expect(progress.isComplete, isTrue);
    expect(progress.fraction, 1);
  });

  test('a partly answered questionnaire is not a finished part', () {
    final progress = BaselineProgress.of(
      _profile(erqS: const {'erqS_1': 2, 'erqS_2': 1}),
    );

    expect(progress.completed, 0);
  });

  test('agrees with the profile\'s own notion of completion', () {
    // Two definitions of "done" would drift apart. The You page shows this
    // percentage and Home shows the same number, so they must match.
    final profiles = [
      _profile(),
      _profile(preferencesCompleted: true),
      _profile(preferencesCompleted: true, erqS: _fullErqS),
      _profile(
        preferencesCompleted: true,
        erqS: _fullErqS,
        gad7: _fullGad7,
        phq9: _fullPhq9,
      ),
      _profile(
        preferencesCompleted: true,
        skipped: const ['erqS', 'gad7', 'phq9'],
      ),
      _profile(erqS: _fullErqS, skipped: const ['gad7']),
    ];

    for (final profile in profiles) {
      expect(
        BaselineProgress.of(profile).isComplete,
        profile.baselineComplete,
        reason: 'disagreed for $profile',
      );
    }
  });
}
