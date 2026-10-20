import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/call/mood_note.dart';

void main() {
  test('a clear estimate says sound, a hint says might', () {
    expect(moodNoteFor('low or tired', 'clear'), 'You sound a bit low or tired.');
    expect(moodNoteFor('low or tired', 'hint'), 'You might be feeling a bit low or tired.');
    expect(moodNoteFor('upbeat', 'clear'), 'You sound upbeat.');
    expect(moodNoteFor('tense or upset', 'hint'), 'You might be feeling a bit tense or upset.');
  });

  test('unsure, unknown or missing means nothing is shown', () {
    expect(moodNoteFor(null, null), isNull);
    expect(moodNoteFor('low or tired', null), isNull);
    expect(moodNoteFor('something new', 'clear'), isNull);
    expect(moodNoteFor('upbeat', 'whatever'), isNull);
  });

  test('never names a diagnosis or a raw number', () {
    for (final mood in ['low or tired', 'tense or upset', 'upbeat', 'calm or content']) {
      for (final tier in ['clear', 'hint']) {
        final note = moodNoteFor(mood, tier)!;
        expect(RegExp(r'\d').hasMatch(note), isFalse);
        expect(note.toLowerCase(), isNot(contains('depress')));
      }
    }
  });
}
