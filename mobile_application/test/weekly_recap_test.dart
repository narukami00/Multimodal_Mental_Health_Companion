import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/insights/weekly_recap.dart';

void main() {
  // Monday 2 March 2026. "now" is Wednesday 18 March, so the weeks of 2, 9 and 16 March: 2 and 9 are finished.
  final now = DateTime(2026, 3, 18, 10);

  SessionRecord entry(DateTime at, {String mood = 'Steady', CaptureMode mode = CaptureMode.text}) =>
      SessionRecord(id: '${at.microsecondsSinceEpoch}$mood', createdAt: at, mode: mode, mood: mood);

  SuggestionRecord task(DateTime at) => SuggestionRecord(
    id: 't${at.microsecondsSinceEpoch}',
    activityId: 'walk',
    shownAt: at,
    contextTags: const [],
    done: true,
    completedAt: at,
  );

  test('weeks start on Monday', () {
    expect(mondayOf(DateTime(2026, 3, 2)), DateTime(2026, 3, 2));
    expect(mondayOf(DateTime(2026, 3, 8, 23)), DateTime(2026, 3, 2));
    expect(mondayOf(DateTime(2026, 3, 9)), DateTime(2026, 3, 9));
  });

  test('only finished weeks with something in them appear, newest first', () {
    final recaps = weeklyRecaps(
      [
        entry(DateTime(2026, 3, 3, 9)),
        entry(DateTime(2026, 3, 11, 9)),
        entry(DateTime(2026, 3, 17, 9)), // this week: not finished
      ],
      const [],
      now,
    );
    expect(recaps.map((r) => r.weekStart), [DateTime(2026, 3, 9), DateTime(2026, 3, 2)]);
  });

  test('a week with nothing in it is left out, never shown as empty', () {
    final recaps = weeklyRecaps([entry(DateTime(2026, 3, 3)), entry(DateTime(2026, 3, 24))], const [], DateTime(2026, 4, 1));
    expect(recaps, hasLength(2));
    expect(recaps.any((r) => r.weekStart == DateTime(2026, 3, 9)), isFalse);
  });

  test('counts days, entries, voice or video, tasks, and the mood that came up most', () {
    final recap = weeklyRecaps(
      [
        entry(DateTime(2026, 3, 2, 8), mood: 'Bright'),
        entry(DateTime(2026, 3, 2, 20), mood: 'Steady', mode: CaptureMode.voice),
        entry(DateTime(2026, 3, 4, 9), mood: 'Steady'),
        entry(DateTime(2026, 3, 8, 9), mood: 'Tender', mode: CaptureMode.video),
      ],
      [task(DateTime(2026, 3, 3, 12)), task(DateTime(2026, 3, 5, 12)), task(DateTime(2026, 3, 12))],
      now,
    ).last;
    expect(recap.activeDays, 3);
    expect(recap.entries, 4);
    expect(recap.voiceOrVideo, 2);
    expect(recap.tasksDone, 2); // the one on the 12th belongs to the next week
    expect(recap.topMood, 'Steady');
    expect(recap.dayHasEntry, [true, false, true, false, false, false, true]);
    expect(recap.dayMoods[0], anyOf('Bright', 'Steady'));
  });

  test('the sentences describe, and a quiet week is kind about it', () {
    final busy = weeklyRecaps(
      [for (var d = 2; d < 6; d++) entry(DateTime(2026, 3, d, 9))],
      [task(DateTime(2026, 3, 3, 12))],
      now,
    ).single;
    expect(busy.lines.first, 'You checked in on 4 of 7 days.');
    expect(busy.lines, contains('Calm came up most.'));
    expect(busy.lines, contains('You tried 1 small thing.'));

    final quiet = weeklyRecaps([entry(DateTime(2026, 3, 4, 9))], const [], now).single;
    expect(quiet.lines.first, 'You checked in on 1 day.');
    expect(quiet.lines.last, contains('A quieter week, and that is fine'));
  });

  test('no sentence compares, counts what was missed, or judges', () {
    final banned = RegExp(r'missed|only|less than|more than last|worse|better|streak|behind|failed|should', caseSensitive: false);
    final recaps = weeklyRecaps(
      [
        entry(DateTime(2026, 3, 3)),
        entry(DateTime(2026, 3, 4), mood: 'Wobbly'),
        entry(DateTime(2026, 3, 10), mood: 'Tender', mode: CaptureMode.voice),
        entry(DateTime(2026, 3, 11), mood: 'Tender'),
        entry(DateTime(2026, 3, 12), mood: 'Tender'),
      ],
      [task(DateTime(2026, 3, 3))],
      now,
    );
    for (final line in [...recaps.expand((r) => r.lines), ...overallSummary(recaps)!]) {
      expect(banned.hasMatch(line), isFalse, reason: line);
    }
  });

  group('the overall summary', () {
    test('is null until there is a finished week', () {
      expect(overallSummary(const []), isNull);
    });

    test('says plainly what the weeks add up to', () {
      final recaps = weeklyRecaps(
        [
          entry(DateTime(2026, 3, 2), mood: 'Bright'),
          entry(DateTime(2026, 3, 9), mood: 'Bright'),
          entry(DateTime(2026, 3, 16), mood: 'Steady'),
          entry(DateTime(2026, 3, 23), mood: 'Bright'),
        ],
        [task(DateTime(2026, 3, 3)), task(DateTime(2026, 3, 10))],
        DateTime(2026, 4, 1),
      );
      final text = overallSummary(recaps)!;
      expect(text.first, 'Over 4 weeks, you showed up on 4 days.');
      expect(text, contains('Upbeat was the word that came up most.'));
      expect(text, contains('You tried 2 small things along the way.'));
      expect(text, contains('Mondays are when you most often check in.'));
    });

    test('does not invent a favourite day from too little', () {
      final recaps = weeklyRecaps([entry(DateTime(2026, 3, 2)), entry(DateTime(2026, 3, 9))], const [], now);
      expect(overallSummary(recaps)!.any((l) => l.contains('most often check in')), isFalse);
    });
  });
}
