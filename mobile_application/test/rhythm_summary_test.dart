import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/day_key.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/rhythm/rhythm_summary.dart';

final _now = DateTime(2026, 9, 26, 10, 0);

SessionRecord _session(DateTime at, {String id = 's'}) {
  return SessionRecord(
    id: '${id}_${at.microsecondsSinceEpoch}',
    createdAt: at,
    mode: CaptureMode.text,
    mood: 'Steady',
  );
}

SuggestionRecord _suggestion(
  DateTime at, {
  SuggestionStatus status = SuggestionStatus.completed,
  String id = 'r',
}) {
  return SuggestionRecord(
    id: '${id}_${at.microsecondsSinceEpoch}',
    activityId: 'walk',
    shownAt: at,
    contextTags: const [],
    status: status,
  );
}

RhythmSummary _summarise({
  List<SessionRecord> sessions = const [],
  Set<String> restDays = const {},
  List<SuggestionRecord> suggestions = const [],
}) {
  return summariseRhythm(
    sessions: sessions,
    restDays: restDays,
    suggestions: suggestions,
    now: _now,
  );
}

void main() {
  group('RhythmSummary window', () {
    test('always exposes 28 days, oldest first, ending today', () {
      final summary = _summarise();

      expect(summary.days.length, 28);
      expect(summary.days.first.date, DateTime(2026, 8, 30));
      expect(summary.days.last.date, DateTime(2026, 9, 26));
      expect(summary.days.last.isToday, isTrue);
      expect(summary.days.where((day) => day.isToday).length, 1);
    });

    test('is empty with no history at all', () {
      final summary = _summarise();

      expect(summary.isEmpty, isTrue);
      expect(summary.checkInCount, 0);
      expect(summary.restCount, 0);
      expect(summary.usual, isNull);
    });

    test('ignores sessions older than the window', () {
      final summary = _summarise(
        sessions: [
          _session(DateTime(2026, 5, 1)),
          _session(DateTime(2026, 9, 24)),
        ],
      );

      expect(summary.checkInCount, 1);
    });
  });

  group('Attendance', () {
    test('a check-in marks the day', () {
      final summary = _summarise(sessions: [_session(_now)]);

      final today = summary.days.last;
      expect(today.hasCheckIn, isTrue);
      expect(today.isRestDay, isFalse);
      expect(today.attended, isTrue);
    });

    test('a declared rest day marks the day', () {
      final summary = _summarise(restDays: {dayKey(_now)});

      final today = summary.days.last;
      expect(today.hasCheckIn, isFalse);
      expect(today.isRestDay, isTrue);
      expect(today.attended, isTrue);
      expect(summary.restCount, 1);
    });

    test('rest and check-in on the same day are counted separately', () {
      final summary = _summarise(
        sessions: [_session(_now)],
        restDays: {dayKey(_now)},
      );

      expect(summary.checkInCount, 1);
      expect(summary.restCount, 1);
      expect(summary.days.last.attended, isTrue);
    });

    test('an answered suggestion counts, but one merely shown does not', () {
      final answered = _summarise(
        suggestions: [_suggestion(_now)],
      );
      expect(answered.days.last.hasSuggestionOutcome, isTrue);
      expect(answered.days.last.attended, isTrue);

      final abandoned = _summarise(
        suggestions: [_suggestion(_now, status: SuggestionStatus.shown)],
      );
      expect(abandoned.days.last.hasSuggestionOutcome, isFalse);
      expect(abandoned.days.last.attended, isFalse);
    });
  });

  group('Usual', () {
    test('stays hidden until enough weeks have data', () {
      // Two active weeks is below the three-week minimum.
      final summary = _summarise(
        sessions: [
          _session(_now),
          _session(_now.subtract(const Duration(days: 8))),
        ],
      );

      expect(summary.usual, isNull);
    });

    test('appears once three weeks carry data, as the median', () {
      final summary = _summarise(
        sessions: [
          // Current week: 2 days.
          _session(_now),
          _session(_now.subtract(const Duration(days: 1))),
          // Last week: 4 days.
          for (var offset = 7; offset < 11; offset++)
            _session(_now.subtract(Duration(days: offset))),
          // Two weeks ago: 3 days.
          for (var offset = 14; offset < 17; offset++)
            _session(_now.subtract(Duration(days: offset))),
        ],
      );

      expect(summary.usual, isNotNull);
      expect(summary.usual!.daysPerWeek, 3);
      expect(summary.usual!.sampleWeeks, 3);
    });

    test('never counts more than the week length', () {
      final summary = _summarise(
        sessions: [
          for (var offset = 0; offset < 28; offset++)
            _session(_now.subtract(Duration(days: offset))),
        ],
      );

      expect(summary.usual!.daysPerWeek, 7);
    });
  });

  group('Gaps stay neutral', () {
    test('days inside a gap carry no mark at all', () {
      final summary = _summarise(
        sessions: [
          _session(_now),
          // A three week gap, then one check-in.
          _session(_now.subtract(const Duration(days: 21))),
        ],
      );

      // Every day strictly between the two check-ins, excluding today.
      final gapDays = summary.days.where(
        (day) => !day.isToday && day.date.isAfter(DateTime(2026, 9, 5)),
      );

      expect(gapDays, isNotEmpty);
      for (final day in gapDays) {
        expect(day.hasCheckIn, isFalse);
        expect(day.isRestDay, isFalse);
        expect(day.hasSuggestionOutcome, isFalse);
        expect(day.attended, isFalse);
      }
    });

    test('a week without activity never lowers the reported usual', () {
      final withGap = _summarise(
        sessions: [
          for (var offset = 0; offset < 3; offset++)
            _session(_now.subtract(Duration(days: offset))),
          for (var offset = 7; offset < 10; offset++)
            _session(_now.subtract(Duration(days: offset))),
          for (var offset = 14; offset < 17; offset++)
            _session(_now.subtract(Duration(days: offset))),
        ],
      );

      expect(withGap.usual!.daysPerWeek, 3);
      expect(withGap.usual!.sampleWeeks, 3);
    });
  });
}
