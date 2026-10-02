import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/domain/capacity/capacity_estimator.dart';
import 'package:solace_mobile/domain/memory/profile_snippet_builder.dart';

Capacity _capacity(CapacityLevel level, double confidence) => Capacity(
  level: level,
  confidence: confidence,
  reasons: const [CapacityReason.shortSleep],
  score: -2,
);

void main() {
  const profile = UserProfile(
    interactionPreferences: ['Gentle tone', 'Quiet prompts'],
    constraints: ['Short moments'],
  );

  test('nothing is built without consent, whatever the data says', () {
    final snippet = buildProfileSnippet(
      consented: false,
      profile: profile,
      capacity: _capacity(CapacityLevel.low, 0.9),
      recentMoodScores: const [-1, -1, -1],
      recentThemes: const ['work'],
    );
    expect(snippet.isEmpty, isTrue);
    expect(snippet.text, '');
  });

  test('says how they like to be spoken to, in plain words', () {
    final snippet = buildProfileSnippet(consented: true, profile: profile);
    expect(
      snippet.text,
      'Prefers a gentle tone, quiet, low-pressure prompts and short moments.',
    );
  });

  test('adds lately and right now, and keeps phone causes out of the words', () {
    final snippet = buildProfileSnippet(
      consented: true,
      profile: profile,
      capacity: _capacity(CapacityLevel.low, 0.8),
      recentMoodScores: const [0.25, 0.0, -1, -1, -1],
      recentThemes: const ['work', 'sleep'],
    );
    expect(
      snippet.text,
      'Prefers a gentle tone, quiet, low-pressure prompts and short moments. '
      'Lately: mood has felt lower than usual for a few days and work and sleep '
      'came up recently. Right now: may have limited energy, keep it gentle.',
    );
    for (final word in ['slept', 'phone', 'screen', 'unlock', 'night']) {
      expect(snippet.text.toLowerCase(), isNot(contains(word)));
    }
  });

  test('a shaky capacity reading is not passed on', () {
    final snippet = buildProfileSnippet(
      consented: true,
      profile: profile,
      capacity: _capacity(CapacityLevel.low, 0.3),
    );
    expect(snippet.text, isNot(contains('Right now')));
  });

  test('contains no digits, scores, or questionnaire answers', () {
    final snippet = buildProfileSnippet(
      consented: true,
      profile: const UserProfile(
        interactionPreferences: ['Gentle tone'],
        phq9Answers: {'q1': 3, 'q2': 3},
        gad7Answers: {'q1': 2},
        sleepStartMinutes: 23 * 60,
        sleepEndMinutes: 7 * 60,
        displayName: 'Rafsan',
      ),
      recentMoodScores: const [-1, -1, -1],
    );
    expect(RegExp(r'\d').hasMatch(snippet.text), isFalse);
    expect(snippet.text, isNot(contains('Rafsan')));
  });

  test('stays within its length cap by dropping whole lines', () {
    final snippet = buildProfileSnippet(
      consented: true,
      profile: const UserProfile(
        interactionPreferences: ['Gentle tone', 'Direct tone', 'Quiet prompts', 'More context'],
        constraints: ['Short moments', 'Low energy options', 'Quiet at home', 'Limited mobility'],
      ),
      recentMoodScores: const [-1, -1, -1],
      recentThemes: const ['work', 'relationships', 'sleep', 'health', 'home', 'money'],
      capacity: _capacity(CapacityLevel.low, 0.9),
    );
    expect(snippet.text.length, lessThanOrEqualTo(ProfileSnippet.maxCharacters));
    expect(snippet.text.endsWith('.'), isTrue);
  });

  test('a quiet, ordinary profile can be empty', () {
    expect(
      buildProfileSnippet(consented: true, profile: const UserProfile()).isEmpty,
      isTrue,
    );
  });
}
