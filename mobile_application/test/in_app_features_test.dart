import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/constants/moods.dart';
import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/domain/footprint/in_app_features.dart';

SessionRecord _session(DateTime at, {String? text, String? mood}) =>
    SessionRecord(
      id: at.microsecondsSinceEpoch.toString(),
      createdAt: at,
      mode: CaptureMode.text,
      text: text,
      mood: mood,
    );

ChatMessageRecord _message(DateTime at, {bool user = true}) =>
    ChatMessageRecord(
      id: '${at.microsecondsSinceEpoch}$user',
      isUser: user,
      text: 'hi',
      timestamp: at,
    );

ChatConversationRecord _conversation(List<ChatMessageRecord> messages) =>
    ChatConversationRecord(
      id: 'c${messages.first.timestamp.microsecondsSinceEpoch}',
      title: 'Chat',
      createdAt: messages.first.timestamp,
      updatedAt: messages.last.timestamp,
      messages: messages,
    );

final _day = DateTime(2026, 10, 1);

void main() {
  group('Moods.score', () {
    test('orders the five words and ignores case and padding', () {
      expect(Moods.score('Bright')!, greaterThan(Moods.score('Steady')!));
      expect(Moods.score('Steady')!, greaterThan(Moods.score('Quiet')!));
      expect(Moods.score('Quiet')!, greaterThan(Moods.score('Tender')!));
      expect(Moods.score('Tender')!, greaterThan(Moods.score('Wobbly')!));
      expect(Moods.score('  wobbly '), Moods.score('Wobbly'));
    });

    test('an unknown or missing word has no score', () {
      expect(Moods.score('elated'), isNull);
      expect(Moods.score(null), isNull);
    });
  });

  group('deriveInAppFeatures', () {
    test('an active day with nothing recorded is zero, not missing', () {
      final row = deriveInAppFeatures(
        day: _day,
        sessions: const [],
        conversations: const [],
        firstRunAt: DateTime(2026, 9, 1),
      )!;

      expect(row.checkInCount, 0);
      expect(row.journalWordCount, 0);
      expect(row.chatMinutes, 0);
      // Nothing to measure, so these stay "not collected".
      expect(row.firstCheckInMinute, isNull);
      expect(row.checkInLatencyMinutes, isNull);
      expect(row.selfMoodMedian, isNull);
      expect(row.sources, {'inApp'});
    });

    test('a day before the app was first opened is not observed', () {
      expect(
        deriveInAppFeatures(
          day: DateTime(2026, 8, 31),
          sessions: const [],
          conversations: const [],
          firstRunAt: DateTime(2026, 9, 1, 14),
        ),
        isNull,
      );
      // The first day itself counts, even if opened late in it.
      expect(
        deriveInAppFeatures(
          day: DateTime(2026, 9, 1),
          sessions: const [],
          conversations: const [],
          firstRunAt: DateTime(2026, 9, 1, 14),
        ),
        isNotNull,
      );
    });

    test('counts check-ins, times the first, and measures against the reminder', () {
      final row = deriveInAppFeatures(
        day: _day,
        sessions: [
          _session(DateTime(2026, 10, 1, 21, 15)),
          _session(DateTime(2026, 10, 1, 9, 5)),
        ],
        conversations: const [],
        reminderMinutes: 20 * 60 + 30,
      )!;

      expect(row.checkInCount, 2);
      expect(row.firstCheckInMinute, 9 * 60 + 5);
      // Checked in 11h25m before the 8:30 PM reminder.
      expect(row.checkInLatencyMinutes, (9 * 60 + 5) - (20 * 60 + 30));
    });

    test('no reminder means no latency, even with a check-in', () {
      final row = deriveInAppFeatures(
        day: _day,
        sessions: [_session(DateTime(2026, 10, 1, 9))],
        conversations: const [],
      )!;

      expect(row.firstCheckInMinute, 9 * 60);
      expect(row.checkInLatencyMinutes, isNull);
    });

    test('check-ins either side of midnight land on their own local days', () {
      final sessions = [
        _session(DateTime(2026, 10, 1, 23, 59)),
        _session(DateTime(2026, 10, 2, 0, 1)),
      ];

      final before = deriveInAppFeatures(
        day: DateTime(2026, 10, 1),
        sessions: sessions,
        conversations: const [],
      )!;
      final after = deriveInAppFeatures(
        day: DateTime(2026, 10, 2),
        sessions: sessions,
        conversations: const [],
      )!;

      expect(before.checkInCount, 1);
      expect(before.firstCheckInMinute, 23 * 60 + 59);
      expect(after.checkInCount, 1);
      expect(after.firstCheckInMinute, 1);
    });

    test('mood median uses only known mood words and handles an even count', () {
      final odd = deriveInAppFeatures(
        day: _day,
        sessions: [
          _session(DateTime(2026, 10, 1, 8), mood: 'Bright'),
          _session(DateTime(2026, 10, 1, 12), mood: 'Wobbly'),
          _session(DateTime(2026, 10, 1, 18), mood: 'Steady'),
          _session(DateTime(2026, 10, 1, 19), mood: 'unrecognised'),
          _session(DateTime(2026, 10, 1, 20)),
        ],
        conversations: const [],
      )!;
      final even = deriveInAppFeatures(
        day: _day,
        sessions: [
          _session(DateTime(2026, 10, 1, 8), mood: 'Bright'),
          _session(DateTime(2026, 10, 1, 12), mood: 'Wobbly'),
        ],
        conversations: const [],
      )!;

      expect(odd.selfMoodMedian, Moods.score('Steady'));
      expect(even.selfMoodMedian, closeTo(0, 1e-9));
    });

    test('words written are counted across the day, ignoring blank text', () {
      final row = deriveInAppFeatures(
        day: _day,
        sessions: [
          _session(DateTime(2026, 10, 1, 8), text: 'Slept badly\nbut okay.'),
          _session(DateTime(2026, 10, 1, 20), text: '   '),
          _session(DateTime(2026, 10, 1, 21)),
          _session(
            DateTime(2026, 10, 2, 8),
            text: 'This belongs to the next day',
          ),
        ],
        conversations: const [],
      )!;

      expect(row.journalWordCount, 4);
    });

    group('chat minutes', () {
      test('a continuous sitting counts its length', () {
        final row = deriveInAppFeatures(
          day: _day,
          sessions: const [],
          conversations: [
            _conversation([
              _message(DateTime(2026, 10, 1, 20, 0), user: false),
              _message(DateTime(2026, 10, 1, 20, 1)),
              _message(DateTime(2026, 10, 1, 20, 3), user: false),
              _message(DateTime(2026, 10, 1, 20, 6)),
            ]),
          ],
        )!;

        // Gaps of 1, 2 and 3 minutes.
        expect(row.chatMinutes, 6);
      });

      test('a long silence is capped, not counted as time spent', () {
        final row = deriveInAppFeatures(
          day: _day,
          sessions: const [],
          conversations: [
            _conversation([
              _message(DateTime(2026, 10, 1, 9, 0)),
              _message(DateTime(2026, 10, 1, 17, 0)),
            ]),
          ],
        )!;

        expect(row.chatMinutes, chatSittingGap.inMinutes);
      });

      test('a single message still counts as a minute', () {
        final row = deriveInAppFeatures(
          day: _day,
          sessions: const [],
          conversations: [
            _conversation([_message(DateTime(2026, 10, 1, 9, 0))]),
          ],
        )!;

        expect(row.chatMinutes, 1);
      });

      test('Sol opening a chat the user never spoke in is not time spent', () {
        final row = deriveInAppFeatures(
          day: _day,
          sessions: const [],
          conversations: [
            _conversation([
              _message(DateTime(2026, 10, 1, 9, 0), user: false),
              _message(DateTime(2026, 10, 1, 9, 2), user: false),
            ]),
          ],
        )!;

        expect(row.chatMinutes, 0);
      });

      test('a chat across midnight splits by local day', () {
        final chat = _conversation([
          _message(DateTime(2026, 10, 1, 23, 58)),
          _message(DateTime(2026, 10, 1, 23, 59)),
          _message(DateTime(2026, 10, 2, 0, 1)),
          _message(DateTime(2026, 10, 2, 0, 3)),
        ]);

        final first = deriveInAppFeatures(
          day: DateTime(2026, 10, 1),
          sessions: const [],
          conversations: [chat],
        )!;
        final second = deriveInAppFeatures(
          day: DateTime(2026, 10, 2),
          sessions: const [],
          conversations: [chat],
        )!;

        expect(first.chatMinutes, 1);
        expect(second.chatMinutes, 2);
      });

      test('separate conversations add up', () {
        final row = deriveInAppFeatures(
          day: _day,
          sessions: const [],
          conversations: [
            _conversation([
              _message(DateTime(2026, 10, 1, 8, 0)),
              _message(DateTime(2026, 10, 1, 8, 2)),
            ]),
            _conversation([
              _message(DateTime(2026, 10, 1, 21, 0)),
              _message(DateTime(2026, 10, 1, 21, 3)),
            ]),
          ],
        )!;

        expect(row.chatMinutes, 5);
      });
    });
  });
}
