import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/rhythm/reminder_wording.dart';

void main() {
  String at(int hour, DateTime day, {String? name}) =>
      ReminderWording.body(minutesPastMidnight: hour * 60, day: day, name: name);

  test('the line fits the time of day', () {
    final day = DateTime(2026, 3, 3);
    expect(at(8, day), isNot(equals(at(20, day))));
    expect(at(8, day), at(8, day)); // and is steady for the same day
  });

  test('it changes from day to day instead of repeating', () {
    final lines = {for (var d = 0; d < 4; d++) at(20, DateTime(2026, 3, 1 + d))};
    expect(lines.length, 4);
  });

  test('a name is used on some days, not all, and only the first name', () {
    final withName = [for (var d = 0; d < 6; d++) at(20, DateTime(2026, 3, 1 + d), name: '  Sam Rivera ')];
    expect(withName.where((l) => l.startsWith('Sam, ')), isNotEmpty);
    expect(withName.where((l) => !l.startsWith('Sam')), isNotEmpty);
    expect(withName.any((l) => l.contains('Rivera')), isFalse);
  });

  test('a blank name is the same as none', () {
    for (var d = 0; d < 6; d++) {
      final day = DateTime(2026, 3, 1 + d);
      expect(at(9, day, name: '   '), at(9, day));
    }
  });

  test('every line at every hour stays gentle: short, no urgency, nothing counted', () {
    final banned = RegExp(r'streak|missed|miss you|days|haven.t|don.t forget|last time|urgent|now!', caseSensitive: false);
    for (var hour = 0; hour < 24; hour++) {
      for (var d = 0; d < 12; d++) {
        final line = at(hour, DateTime(2026, 3, 1 + d), name: 'Sam');
        expect(line.length, lessThan(80), reason: line);
        expect(banned.hasMatch(line), isFalse, reason: line);
      }
    }
  });
}
