import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/sleep_window.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/domain/capacity/capacity_estimator.dart';

/// Usual sleep 23:00 to 07:00.
const _usual = SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60);

DateTime _at(int hour, [int minute = 0]) =>
    DateTime(2026, 10, 1, hour, minute);

Capacity _hoursOnly(DateTime now) =>
    estimateCapacity(now: now, sleepWindow: _usual);

void main() {
  group('with usual sleep hours, from where now sits in the day', () {
    final cases = <String, (DateTime, CapacityLevel, CapacityReason?)>{
      'asleep hours': (_at(3), CapacityLevel.low, CapacityReason.inSleepWindow),
      'just after bedtime': (
        _at(23, 30),
        CapacityLevel.low,
        CapacityReason.inSleepWindow,
      ),
      'half an hour after waking': (
        _at(7, 30),
        CapacityLevel.medium,
        CapacityReason.justWoke,
      ),
      'an hour after waking': (_at(8), CapacityLevel.medium, null),
      'two hours after waking': (
        _at(9),
        CapacityLevel.high,
        CapacityReason.daytime,
      ),
      'mid-afternoon': (_at(15), CapacityLevel.high, CapacityReason.daytime),
      'four hours before bed': (
        _at(19),
        CapacityLevel.high,
        CapacityReason.daytime,
      ),
      'three and a half hours before bed': (_at(19, 30), CapacityLevel.medium, null),
      'winding down': (
        _at(21, 45),
        CapacityLevel.medium,
        CapacityReason.windingDown,
      ),
    };

    cases.forEach((name, expected) {
      test(name, () {
        final result = _hoursOnly(expected.$1);
        expect(result.level, expected.$2);
        if (expected.$3 != null) {
          expect(result.reasons, contains(expected.$3));
        } else {
          expect(result.reasons, isEmpty);
        }
      });
    });

    test('a same-day sleep window works too', () {
      // A night worker sleeping 09:00 to 17:00.
      const worker = SleepWindow(startMinutes: 9 * 60, endMinutes: 17 * 60);

      expect(
        estimateCapacity(now: _at(12), sleepWindow: worker).level,
        CapacityLevel.low,
      );
      expect(
        estimateCapacity(now: _at(22), sleepWindow: worker).reasons,
        contains(CapacityReason.daytime),
      );
    });

    test('an empty window is treated as no sleep hours', () {
      const empty = SleepWindow(startMinutes: 480, endMinutes: 480);

      final result = estimateCapacity(now: _at(3), sleepWindow: empty);

      expect(result.reasons, contains(CapacityReason.lateNight));
    });
  });

  group('without sleep hours, the clock is only a weak stand-in', () {
    test('small hours read low', () {
      final result = estimateCapacity(now: _at(3));
      expect(result.level, CapacityLevel.low);
      expect(result.reasons, [CapacityReason.lateNight]);
    });

    test('the working day is neutral rather than assumed energetic', () {
      final result = estimateCapacity(now: _at(14));
      expect(result.level, CapacityLevel.medium);
      expect(result.reasons, isEmpty);
    });

    test('the edges of the day lean gentle', () {
      expect(estimateCapacity(now: _at(6)).level, CapacityLevel.medium);
      expect(
        estimateCapacity(now: _at(6)).reasons,
        [CapacityReason.earlyMorning],
      );
      expect(estimateCapacity(now: _at(21, 30)).level, CapacityLevel.medium);
      expect(estimateCapacity(now: _at(22, 30)).level, CapacityLevel.low);
    });

    test('is far less sure of itself', () {
      expect(estimateCapacity(now: _at(14)).confidence, closeTo(0.2, 1e-9));
      expect(_hoursOnly(_at(14)).confidence, closeTo(0.4, 1e-9));
    });
  });

  group('mood', () {
    test('a wobbly mood outweighs a good time of day', () {
      final result = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        latestMood: 'Wobbly',
      );

      expect(result.level, CapacityLevel.low);
      expect(result.reasons, containsAll([
        CapacityReason.daytime,
        CapacityReason.lowMood,
      ]));
    });

    test('tender alone only softens a good day', () {
      final result = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        latestMood: 'Tender',
      );

      expect(result.level, CapacityLevel.medium);
    });

    test('tender near bedtime is low', () {
      final result = estimateCapacity(
        now: _at(21, 45),
        sleepWindow: _usual,
        latestMood: 'Tender',
      );

      expect(result.level, CapacityLevel.low);
    });

    test('a bright mood lifts, but cannot outrun just having woken', () {
      expect(
        estimateCapacity(
          now: _at(15),
          sleepWindow: _usual,
          latestMood: 'Bright',
        ).score,
        2,
      );
      expect(
        estimateCapacity(
          now: _at(7, 30),
          sleepWindow: _usual,
          latestMood: 'Bright',
        ).level,
        CapacityLevel.medium,
      );
    });

    test('steady and quiet change nothing', () {
      final base = _hoursOnly(_at(15));
      for (final mood in ['Steady', 'Quiet']) {
        final result = estimateCapacity(
          now: _at(15),
          sleepWindow: _usual,
          latestMood: mood,
        );
        expect(result.score, base.score);
      }
    });

    test('an unrecognised mood word is ignored and adds no confidence', () {
      final base = _hoursOnly(_at(15));
      final result = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        latestMood: 'elated',
      );

      expect(result.score, base.score);
      expect(result.confidence, base.confidence);
    });
  });

  group('sensed sleep', () {
    test('a short night counts against a good day', () {
      final result = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        sleptMinutes: 5 * 60,
      );

      // Three hours short of eight, against a +1 daytime.
      expect(result.reasons, contains(CapacityReason.shortSleep));
      expect(result.level, CapacityLevel.medium);
    });

    test('a short night plus a tender mood is low', () {
      final result = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        sleptMinutes: 5 * 60,
        latestMood: 'Tender',
      );

      expect(result.level, CapacityLevel.low);
    });

    test('a usual night, or a slightly short one, is not held against anyone', () {
      for (final slept in [8 * 60, 7 * 60 + 30, 9 * 60]) {
        final result = estimateCapacity(
          now: _at(15),
          sleepWindow: _usual,
          sleptMinutes: slept,
        );
        expect(result.reasons, isNot(contains(CapacityReason.shortSleep)));
      }
    });

    test('sensed sleep without stated hours has nothing to compare to', () {
      final result = estimateCapacity(now: _at(15), sleptMinutes: 120);

      expect(result.reasons, isNot(contains(CapacityReason.shortSleep)));
    });
  });

  group('trend and recent too-hard', () {
    test('a falling run of days counts once there are three', () {
      final falling = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        recentMoodScores: const [0.25, 0.0, -0.5],
      );
      final tooShort = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        recentMoodScores: const [0.25, -0.5],
      );

      expect(falling.reasons, contains(CapacityReason.decliningMood));
      expect(tooShort.reasons, isNot(contains(CapacityReason.decliningMood)));
    });

    test('a rising run is not rewarded', () {
      final rising = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        recentMoodScores: const [-0.5, 0.0, 0.5],
      );

      expect(rising.score, _hoursOnly(_at(15)).score);
    });

    test('a recent too-hard keeps things gentler', () {
      final result = estimateCapacity(
        now: _at(15),
        sleepWindow: _usual,
        tooHardRecently: true,
      );

      expect(result.reasons, contains(CapacityReason.recentTooHard));
      expect(result.level, CapacityLevel.medium);
    });
  });

  test('confidence grows with what is known and stays within 0 to 1', () {
    final everything = estimateCapacity(
      now: _at(15),
      sleepWindow: _usual,
      sleptMinutes: 8 * 60,
      latestMood: 'Steady',
      recentMoodScores: const [0.0, 0.0, 0.0],
    );

    expect(everything.confidence, closeTo(1.0, 1e-9));
    expect(everything.confidence, greaterThan(_hoursOnly(_at(15)).confidence));
  });

  group('resolveSleepWindow', () {
    const usual = SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60);
    const weekend = SleepWindow(startMinutes: 60, endMinutes: 9 * 60);
    const profile = UserProfile(
      sleepStartMinutes: 23 * 60,
      sleepEndMinutes: 7 * 60,
      weekendSleepDiffers: true,
      weekendSleepStartMinutes: 60,
      weekendSleepEndMinutes: 9 * 60,
    );

    test('the fixtures fall on the days the cases assume', () {
      expect(DateTime(2026, 10, 1).weekday, DateTime.thursday);
    });

    test('a night leading into a day off uses the weekend hours', () {
      // Thursday evening: tomorrow is Friday.
      expect(
        resolveSleepWindow(profile: profile, now: DateTime(2026, 10, 1, 20)),
        weekend,
      );
      // Friday evening: tomorrow is Saturday.
      expect(
        resolveSleepWindow(profile: profile, now: DateTime(2026, 10, 2, 20)),
        weekend,
      );
      // Saturday evening: tomorrow is Sunday, a working day here.
      expect(
        resolveSleepWindow(profile: profile, now: DateTime(2026, 10, 3, 20)),
        usual,
      );
    });

    test('before midday the night in question began yesterday evening', () {
      // Friday morning follows Thursday night, which led into Friday.
      expect(
        resolveSleepWindow(profile: profile, now: DateTime(2026, 10, 2, 8)),
        weekend,
      );
      // Sunday morning follows Saturday night, which led into Sunday.
      expect(
        resolveSleepWindow(profile: profile, now: DateTime(2026, 10, 4, 8)),
        usual,
      );
    });

    test('weekend days are a parameter, not a fixed rule', () {
      expect(
        resolveSleepWindow(
          profile: profile,
          now: DateTime(2026, 10, 3, 20),
          weekendDays: const {DateTime.sunday},
        ),
        weekend,
      );
    });

    test('the usual hours apply everywhere when weekends do not differ', () {
      const same = UserProfile(
        sleepStartMinutes: 23 * 60,
        sleepEndMinutes: 7 * 60,
      );

      expect(
        resolveSleepWindow(profile: same, now: DateTime(2026, 10, 2, 20)),
        usual,
      );
    });

    test('no sleep hours means no window', () {
      expect(
        resolveSleepWindow(
          profile: const UserProfile(),
          now: DateTime(2026, 10, 2, 20),
        ),
        isNull,
      );
    });
  });
}
