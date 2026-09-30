import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/features/suggestions/suggestion_context.dart';

final _now = DateTime(2026, 9, 22, 10);

SessionRecord _session({
  required DateTime at,
  String? mood,
  String? text,
}) {
  return SessionRecord(
    id: 's${at.microsecondsSinceEpoch}',
    createdAt: at,
    mode: CaptureMode.text,
    mood: mood,
    text: text,
  );
}

void main() {
  group('buildRecommendationContext', () {
    test('reads state and tags from the most recent check-in', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [
          // Newest first, as the controller returns them.
          _session(
            at: _now,
            mood: 'Steady',
            text: 'Work felt long, and I could not sleep.',
          ),
          _session(
            at: _now.subtract(const Duration(days: 2)),
            mood: 'Wobbly',
            text: 'money worries',
          ),
        ],
        now: _now,
      );

      expect(context.currentState, 'Steady');
      expect(context.eventTags, containsAll(['work', 'sleep']));
      // The older check-in must not leak in.
      expect(context.eventTags, isNot(contains('money')));
    });

    test('documented limitation: inflections do not match', () {
      // The tagger matches whole words, so "slept" misses the "sleep" alias.
      // Recorded here rather than fixed, because tag normalisation is its own
      // piece of work the spec already flags.
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [_session(at: _now, mood: 'Steady', text: 'I slept badly.')],
        now: _now,
      );

      expect(context.eventTags, isEmpty);
    });

    test('is empty rather than invented when there is no history', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: const [],
        now: _now,
      );

      expect(context.currentState, isNull);
      expect(context.eventTags, isEmpty);
    });

    test('a mood-only check-in contributes state but no tags', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [_session(at: _now, mood: 'Quiet')],
        now: _now,
      );

      expect(context.currentState, 'Quiet');
      expect(context.eventTags, isEmpty);
    });

    test('unrecognised words produce no tags rather than guesses', () {
      final context = buildRecommendationContext(
        profile: const UserProfile(),
        sessions: [
          _session(at: _now, mood: 'Steady', text: 'Just a quiet afternoon.'),
        ],
        now: _now,
      );

      expect(context.eventTags, isEmpty);
    });
  });

  group('profileAgeInDays', () {
    test('counts from the first run', () {
      final profile = UserProfile(firstRunAt: DateTime(2026, 9, 1));

      expect(profileAgeInDays(profile, now: _now), 21);
    });

    test('is null when the first run was never recorded', () {
      expect(profileAgeInDays(const UserProfile(), now: _now), isNull);
    });
  });

  group('prefersGentleStart', () {
    test('is false before the baseline is answered', () {
      expect(prefersGentleStart(const UserProfile()), isFalse);
    });

    test('is false when the baseline is low', () {
      final profile = UserProfile(
        gad7Answers: {for (var i = 1; i <= 7; i++) 'gad7_$i': 0},
        phq9Answers: {for (var i = 1; i <= 9; i++) 'phq9_$i': 1},
      );

      expect(prefersGentleStart(profile), isFalse);
    });

    test('is true when anxiety scores are elevated', () {
      final profile = UserProfile(
        // 1,2,3,0,1,2,3 = 12, above the moderate threshold.
        gad7Answers: {for (var i = 1; i <= 7; i++) 'gad7_$i': i % 4},
      );

      expect(prefersGentleStart(profile), isTrue);
    });

    test('is true when low-mood scores are elevated', () {
      final profile = UserProfile(
        phq9Answers: {for (var i = 1; i <= 9; i++) 'phq9_$i': 2},
      );

      expect(prefersGentleStart(profile), isTrue);
    });

    test('a partially answered instrument cannot raise the flag', () {
      final profile = UserProfile(
        // Incomplete, so scoreFor returns null rather than a partial total.
        gad7Answers: const {'gad7_1': 3, 'gad7_2': 3},
      );

      expect(prefersGentleStart(profile), isFalse);
    });
  });
}
