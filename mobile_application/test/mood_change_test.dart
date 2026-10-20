import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/recommendations/mood_change.dart';

SessionRecord _session(DateTime at, {String? mood, String? text}) =>
    SessionRecord(
      id: at.microsecondsSinceEpoch.toString(),
      createdAt: at,
      mode: CaptureMode.text,
      mood: mood,
      text: text,
    );

void main() {
  final shown = DateTime(2026, 10, 1, 15);

  group('moodBeforeFor', () {
    test('uses the latest recent check-in with a mood word', () {
      final before = moodBeforeFor(
        shownAt: shown,
        sessions: [
          _session(DateTime(2026, 10, 1, 9), mood: 'Bright'),
          _session(DateTime(2026, 10, 1, 13), mood: 'Wobbly'),
        ],
      );

      expect(before, 'Wobbly');
    });

    test('ignores a check-in older than the window', () {
      expect(
        moodBeforeFor(
          shownAt: shown,
          sessions: [_session(DateTime(2026, 9, 30, 20), mood: 'Bright')],
        ),
        isNull,
      );
    });

    test('ignores a check-in made after the idea was offered', () {
      expect(
        moodBeforeFor(
          shownAt: shown,
          sessions: [_session(DateTime(2026, 10, 1, 16), mood: 'Bright')],
        ),
        isNull,
      );
    });

    test('a check-in without a recognised mood does not stand in for one', () {
      expect(
        moodBeforeFor(
          shownAt: shown,
          sessions: [
            _session(DateTime(2026, 10, 1, 14), text: 'long day'),
            _session(DateTime(2026, 10, 1, 14, 30), mood: 'elated'),
          ],
        ),
        isNull,
      );
    });

    test('a check-in the model read, with no word picked, still gives the before', () {
      final read = SessionRecord(
        id: 'r',
        createdAt: DateTime(2026, 10, 1, 14),
        mode: CaptureMode.text,
        text: 'a quiet afternoon',
        emotionResults: [
          EmotionResult(
            sessionId: 'r',
            modality: EmotionModality.text,
            timestamp: DateTime(2026, 10, 1, 14),
            modelVersion: 'test',
            mood: 'upbeat',
            tier: 'clear',
            pattern: 'T',
            classes: const {'happy': 1.0},
          ),
        ],
      );

      expect(moodBeforeFor(shownAt: shown, sessions: [read]), 'Bright');
    });

    test('no check-ins is no answer', () {
      expect(moodBeforeFor(shownAt: shown, sessions: const []), isNull);
    });
  });

  group('moodChange', () {
    test('is positive for an improvement and negative for a decline', () {
      expect(moodChange('Wobbly', 'Bright')!, greaterThan(0));
      expect(moodChange('Bright', 'Wobbly')!, lessThan(0));
      expect(moodChange('Steady', 'steady'), 0);
    });

    test('needs both ends, and both recognised', () {
      expect(moodChange(null, 'Bright'), isNull);
      expect(moodChange('Bright', null), isNull);
      expect(moodChange('elated', 'Bright'), isNull);
    });
  });

  group('SuggestionRecord mood fields', () {
    test('round-trip and survive copyWith', () {
      final record = SuggestionRecord(
        id: '1',
        activityId: 'a',
        shownAt: shown,
        contextTags: const [],
        moodBefore: 'Wobbly',
      ).copyWith(moodAfter: 'Steady', done: true);

      final restored = SuggestionRecord.fromMap(record.toMap());

      expect(restored.moodBefore, 'Wobbly');
      expect(restored.moodAfter, 'Steady');
      expect(restored.done, isTrue);
    });

    test('records written before these existed read as not asked', () {
      final legacy = SuggestionRecord.fromMap({
        'id': '1',
        'activityId': 'a',
        'shownAt': '2026-09-01T10:00:00.000',
        'contextTags': <String>[],
      });

      expect(legacy.moodBefore, isNull);
      expect(legacy.moodAfter, isNull);
    });
  });
}
