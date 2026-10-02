import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/sleep_window.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/domain/footprint/usage_day_reducer.dart';

final _day = DateTime(2026, 10, 1);
final _end = DateTime(2026, 10, 2);

DateTime _t(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 10, 1, hour, minute, second);

UsageEvent _on(DateTime at) =>
    UsageEvent(time: at, type: UsageEventType.screenOn);
UsageEvent _off(DateTime at) =>
    UsageEvent(time: at, type: UsageEventType.screenOff);
UsageEvent _unlock(DateTime at) =>
    UsageEvent(time: at, type: UsageEventType.keyguardHidden);
UsageEvent _lock(DateTime at) =>
    UsageEvent(time: at, type: UsageEventType.keyguardShown);
UsageEvent _open(DateTime at, String pkg) =>
    UsageEvent(time: at, type: UsageEventType.appForeground, package: pkg);
UsageEvent _close(DateTime at, String pkg) =>
    UsageEvent(time: at, type: UsageEventType.appBackground, package: pkg);

String? _category(String package) => switch (package) {
  'chat.app' => 'messaging',
  'video.app' => 'video',
  'home.launcher' => null,
  _ => 'other',
};

void main() {
  group('screen use', () {
    test('one session gives its length, count, and times', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(9, 0)), _off(_t(9, 30))],
      )!;

      expect(row.screenOnMinutes, 30);
      expect(row.sessionCount, 1);
      expect(row.longestSessionMinutes, 30);
      expect(row.firstPickupMinute, 9 * 60);
      expect(row.lastUseMinute, 9 * 60 + 30);
      expect(row.sources, {'usage'});
      expect(row.dayKey, '2026-10-01');
    });

    test('several sessions add up and the longest is found', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _on(_t(8, 0)), _off(_t(8, 10)),
          _on(_t(12, 0)), _off(_t(12, 45)),
          _on(_t(20, 0)), _off(_t(20, 5)),
        ],
      )!;

      expect(row.screenOnMinutes, 60);
      expect(row.sessionCount, 3);
      expect(row.longestSessionMinutes, 45);
      expect(row.firstPickupMinute, 8 * 60);
      expect(row.lastUseMinute, 20 * 60 + 5);
    });

    test('events may arrive in any order', () {
      final ordered = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(9)), _off(_t(10)), _on(_t(14)), _off(_t(14, 20))],
      )!;
      final shuffled = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_off(_t(14, 20)), _on(_t(9)), _on(_t(14)), _off(_t(10))],
      )!;

      expect(shuffled.screenOnMinutes, ordered.screenOnMinutes);
      expect(shuffled.sessionCount, ordered.sessionCount);
    });

    test('a repeated screen-on does not start a second session', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(9)), _on(_t(9, 5)), _off(_t(9, 20))],
      )!;

      expect(row.sessionCount, 1);
      expect(row.screenOnMinutes, 20);
    });

    test('a stray screen-off with nothing on is ignored', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_off(_t(9)), _on(_t(10)), _off(_t(10, 10))],
      )!;

      expect(row.screenOnMinutes, 10);
      expect(row.sessionCount, 1);
    });

    test('a quiet day with data is a real row of zeros', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_off(_t(0, 5))],
      )!;

      expect(row.screenOnMinutes, 0);
      expect(row.sessionCount, 0);
      expect(row.firstPickupMinute, isNull);
      expect(row.lastUseMinute, isNull);
    });

    test('no data covering the day is not a row at all', () {
      expect(
        reduceUsageDay(day: _day, dataEnd: _day, events: [_on(_t(9))]),
        isNull,
      );
      expect(
        reduceUsageDay(
          day: _day,
          dataEnd: DateTime(2026, 9, 30, 12),
          events: const [],
        ),
        isNull,
      );
    });
  });

  group('across midnight', () {
    test('a session already running at midnight counts from midnight', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _on(DateTime(2026, 9, 30, 23, 30)),
          _off(_t(0, 20)),
        ],
      )!;

      expect(row.screenOnMinutes, 20);
      // Carried in from yesterday, so not a pickup of this day.
      expect(row.sessionCount, 0);
      expect(row.firstPickupMinute, isNull);
      expect(row.lastUseMinute, 20);
    });

    test('a session that runs past the end of the day is cut there', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(23, 40)), _off(DateTime(2026, 10, 2, 1, 0))],
      )!;

      expect(row.screenOnMinutes, 20);
      expect(row.sessionCount, 1);
      expect(row.lastUseMinute, 23 * 60 + 59);
    });

    test('the same events split cleanly between two days', () {
      final events = [
        _on(DateTime(2026, 10, 1, 23, 40)),
        _off(DateTime(2026, 10, 2, 0, 30)),
      ];

      final first = reduceUsageDay(day: _day, dataEnd: _end, events: events)!;
      final second = reduceUsageDay(
        day: DateTime(2026, 10, 2),
        dataEnd: DateTime(2026, 10, 3),
        events: events,
      )!;

      expect(first.screenOnMinutes, 20);
      expect(second.screenOnMinutes, 30);
      expect(first.screenOnMinutes! + second.screenOnMinutes!, 50);
    });
  });

  group('a day still in progress', () {
    test('only what has happened so far counts', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _t(10),
        events: [
          _on(_t(9)),
          _off(_t(9, 30)),
          _on(_t(11)),
          _off(_t(11, 30)),
        ],
      )!;

      expect(row.screenOnMinutes, 30);
      expect(row.sessionCount, 1);
    });

    test('a session still open runs to the end of the data', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _t(10),
        events: [_on(_t(9, 40))],
      )!;

      expect(row.screenOnMinutes, 20);
      expect(row.lastUseMinute, 10 * 60);
    });
  });

  group('hours of the day', () {
    test('a session is spread across the hours it touches', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(9, 40)), _off(_t(11, 10))],
      )!;

      final hours = row.hourlyActiveMinutes!;
      expect(hours, hasLength(24));
      expect(hours[9], 20);
      expect(hours[10], 60);
      expect(hours[11], 10);
      expect(hours.fold<int>(0, (a, b) => a + b), row.screenOnMinutes);
      expect(hours[8], 0);
    });
  });

  group('unlocks', () {
    test('counts unlocks within the day', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _on(_t(9)), _unlock(_t(9, 0, 2)), _off(_t(9, 10)), _lock(_t(9, 10, 1)),
          _on(_t(12)), _unlock(_t(12, 0, 3)), _off(_t(12, 5)),
          _unlock(DateTime(2026, 9, 30, 22)),
        ],
      )!;

      expect(row.unlockCount, 2);
    });

    test('screen use with no lock-screen events does not claim zero unlocks', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(9)), _off(_t(9, 10))],
      )!;

      expect(row.sessionCount, 1);
      expect(row.unlockCount, isNull);
    });

    test('lock events with no unlocks are a real zero', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_lock(_t(9))],
      )!;

      expect(row.unlockCount, 0);
    });
  });

  group('apps', () {
    final events = [
      _on(_t(9, 0)),
      _open(_t(9, 0), 'home.launcher'),
      _open(_t(9, 1), 'chat.app'),
      _open(_t(9, 11), 'video.app'),
      _close(_t(9, 41), 'video.app'),
      _open(_t(9, 41), 'chat.app'),
      _off(_t(9, 51)),
    ];

    test('without a resolver there are no category totals at all', () {
      final row = reduceUsageDay(day: _day, dataEnd: _end, events: events)!;

      expect(row.categoryMinutes, isNull);
      expect(row.topApps, isNull);
    });

    test('foreground time is split by category, and ignored apps are left out', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: events,
        categoryOf: _category,
      )!;

      expect(row.categoryMinutes, {'messaging': 20, 'video': 30});
      // The launcher's single minute counts as screen time but not in categories.
      expect(row.screenOnMinutes, 51);
    });

    test('app names appear only when asked for', () {
      final off = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: events,
        categoryOf: _category,
      )!;
      final on = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: events,
        categoryOf: _category,
        includeTopApps: true,
        labelOf: (package) => 'App $package',
      )!;

      expect(off.topApps, isNull);
      expect(on.topApps!.map((a) => a.name), [
        'App video.app',
        'App chat.app',
        'App home.launcher',
      ]);
      expect(on.topApps!.first.minutes, 30);
    });

    test('top apps are capped and zero-minute apps dropped', () {
      final many = <UsageEvent>[_on(_t(9))];
      for (var i = 0; i < 8; i++) {
        many.add(_open(_t(9, i * 5), 'app.$i'));
      }
      many.add(_off(_t(9, 40)));

      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: many,
        categoryOf: (_) => 'other',
        includeTopApps: true,
        topAppCount: 3,
      )!;

      expect(row.topApps, hasLength(3));
    });

    test('time in an app does not count while the screen is off', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _on(_t(9, 0)),
          _open(_t(9, 0), 'chat.app'),
          _off(_t(9, 10)),
          // The app is paused only a little after the screen goes off.
          _close(_t(9, 12), 'chat.app'),
        ],
        categoryOf: _category,
      )!;

      expect(row.categoryMinutes, {'messaging': 10});
    });

    test('an app resumed just before the screen turns on still counts', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _open(_t(9, 0), 'chat.app'),
          _on(_t(9, 0)),
          _off(_t(9, 10)),
        ],
        categoryOf: _category,
      )!;

      expect(row.categoryMinutes, {'messaging': 10});
    });

    test('a pause of a different app does not end the current one', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _on(_t(9, 0)),
          _open(_t(9, 0), 'chat.app'),
          _close(_t(9, 5), 'video.app'),
          _off(_t(9, 10)),
        ],
        categoryOf: _category,
      )!;

      expect(row.categoryMinutes, {'messaging': 10});
    });

    test('app switches per hour of screen time', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _on(_t(9, 0)),
          _open(_t(9, 0), 'a'),
          _open(_t(9, 10), 'b'),
          _open(_t(9, 20), 'a'),
          _open(_t(9, 30), 'b'),
          _off(_t(10, 0)),
        ],
      )!;

      // Three switches in one hour of screen time.
      expect(row.appSwitchRate, closeTo(3, 1e-9));
    });

    test('re-opening the same app is not a switch, and too little data gives none', () {
      final same = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [
          _on(_t(9, 0)),
          _open(_t(9, 0), 'a'),
          _open(_t(9, 10), 'a'),
          _off(_t(10, 0)),
        ],
      )!;
      final brief = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(9, 0)), _open(_t(9, 0), 'a'), _open(_t(9, 1), 'b'), _off(_t(9, 3))],
      )!;

      expect(same.appSwitchRate, 0);
      expect(brief.appSwitchRate, isNull);
    });
  });

  group('sleep hours', () {
    const window = SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60);

    test('counts screen use inside the stated window, both ends of the day', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        sleepWindow: window,
        events: [
          _on(_t(1, 0)), _off(_t(1, 30)),
          _on(_t(6, 50)), _off(_t(7, 10)),
          _on(_t(12)), _off(_t(12, 40)),
          _on(_t(22, 50)), _off(_t(23, 20)),
        ],
      )!;

      // 30 (01:00-01:30) + 10 (06:50-07:00) + 20 (23:00-23:20).
      expect(row.screenMinutesInSleepWindow, 60);
    });

    test('measures how far the last use ran past bedtime', () {
      final late = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        sleepWindow: window,
        events: [_on(_t(22)), _off(_t(23, 40))],
      )!;
      final early = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        sleepWindow: window,
        events: [_on(_t(21)), _off(_t(22, 30))],
      )!;

      expect(late.lastUseDelayVsStatedBedtimeMinutes, 40);
      expect(early.lastUseDelayVsStatedBedtimeMinutes, -30);
    });

    test('use that runs to midnight reads as the end of the day', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        sleepWindow: window,
        events: [_on(_t(23, 30)), _off(DateTime(2026, 10, 2, 1))],
      )!;

      expect(row.lastUseDelayVsStatedBedtimeMinutes, 24 * 60 - 1 - 23 * 60);
    });

    test('a last use many hours before bedtime says nothing about bedtime', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        sleepWindow: window,
        events: [_on(_t(1, 0)), _off(_t(1, 30))],
      )!;

      expect(row.lastUseDelayVsStatedBedtimeMinutes, isNull);
    });

    test('without sleep hours, neither is produced', () {
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        events: [_on(_t(23)), _off(_t(23, 30))],
      )!;

      expect(row.screenMinutesInSleepWindow, isNull);
      expect(row.lastUseDelayVsStatedBedtimeMinutes, isNull);
    });

    test('a same-day window does not produce a bedtime delay', () {
      const worker = SleepWindow(startMinutes: 9 * 60, endMinutes: 17 * 60);
      final row = reduceUsageDay(
        day: _day,
        dataEnd: _end,
        sleepWindow: worker,
        events: [_on(_t(10)), _off(_t(10, 30))],
      )!;

      expect(row.screenMinutesInSleepWindow, 30);
      expect(row.lastUseDelayVsStatedBedtimeMinutes, isNull);
    });
  });

  group('UsageEvent', () {
    test('round-trips through a map', () {
      final event = _open(_t(9), 'chat.app');

      final restored = UsageEvent.fromMap(event.toMap())!;

      expect(restored.time, event.time);
      expect(restored.type, UsageEventType.appForeground);
      expect(restored.package, 'chat.app');
    });

    test('an unreadable event is dropped', () {
      expect(UsageEvent.fromMap('junk'), isNull);
      expect(UsageEvent.fromMap({'time': 'x', 'type': 'screenOn'}), isNull);
      expect(UsageEvent.fromMap({'time': 1, 'type': 'teleport'}), isNull);
    });
  });
}
