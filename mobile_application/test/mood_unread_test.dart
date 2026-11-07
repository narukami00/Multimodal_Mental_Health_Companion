import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/domain/insights/mood_insights.dart';

SessionRecord _unread(DateTime at, {CaptureMode mode = CaptureMode.voice}) =>
    SessionRecord(id: '${at.microsecondsSinceEpoch}', createdAt: at, mode: mode, text: 'waiting', emotionResults: const []);

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
}
