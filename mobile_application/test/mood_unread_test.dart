import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/constants/moods.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/domain/insights/mood_insights.dart';

SessionRecord _unread(DateTime at, {CaptureMode mode = CaptureMode.voice}) =>
    SessionRecord(id: '${at.microsecondsSinceEpoch}', createdAt: at, mode: mode, text: 'waiting', emotionResults: const []);

SessionRecord _readUnsure(DateTime at) => SessionRecord(
  id: '${at.microsecondsSinceEpoch}_u',
  createdAt: at,
  mode: CaptureMode.voice,
  text: 'already read',
  emotionResults: [
    EmotionResult(
      sessionId: 's',
      modality: EmotionModality.voice,
      timestamp: at,
      modelVersion: 'test',
      mood: null,
      classes: const {'neutral': 1.0},
    ),
  ],
);

SessionRecord _read(DateTime at) => SessionRecord(
  id: '${at.microsecondsSinceEpoch}',
  createdAt: at,
  mode: CaptureMode.text,
  text: 'ok',
  mood: 'Steady',
  emotionResults: const [],
);

void main() {
  final now = DateTime(2026, 11, 20, 12);

  test('an entry with no mood word yet marks its day as written, not empty', () {
    final strip = moodStrip([_unread(DateTime(2026, 11, 19, 21))], now, days: 3);
    final yesterday = strip[1];
    expect(yesterday.entries, isEmpty);
    expect(yesterday.unread, hasLength(1));
    expect(yesterday.mood, isNull, reason: 'no colour is invented for it');
    expect(strip[0].unread, isEmpty);
  });

  test('a day with a read entry and an unread one keeps both', () {
    final strip = moodStrip([_read(DateTime(2026, 11, 19, 9)), _unread(DateTime(2026, 11, 19, 22))], now, days: 2);
    expect(strip[0].entries, hasLength(1));
    expect(strip[0].unread, hasLength(1));
    expect(strip[0].mood, 'Steady');
  });

  test('a read entry whose model reading was unsure is not marked unread', () {
    final strip = moodStrip([_readUnsure(DateTime(2026, 11, 19, 15))], now, days: 2);
    expect(strip[0].unread, isEmpty);
    expect(strip[0].unsure, hasLength(1));
    expect(Moods.fromReadingMood('even'), 'Quiet');
    expect(Moods.display('Quiet'), 'Even');
  });
}
