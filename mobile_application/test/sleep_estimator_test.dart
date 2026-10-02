import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/sleep_window.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/domain/footprint/sleep_estimator.dart';

/// The night of 1 to 2 October; the morning is the 2nd.
final _morning = DateTime(2026, 10, 2);
final _end = DateTime(2026, 10, 2, 18);

DateTime _evening(int hour, [int minute = 0]) =>
    DateTime(2026, 10, 1, hour, minute);
DateTime _next(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 10, 2, hour, minute, second);

List<UsageEvent> _use(DateTime from, DateTime to) => [
  UsageEvent(time: from, type: UsageEventType.screenOn),
  UsageEvent(time: to, type: UsageEventType.screenOff),
];

const _window = SleepWindow(startMinutes: 23 * 60, endMinutes: 7 * 60);

/// A usual night: phone down at 23:30, picked up at 07:00.
List<UsageEvent> _usualNight() => [
  ..._use(_evening(22), _evening(23, 30)),
  ..._use(_next(7), _next(7, 20)),
];

void main() {
  group('a usual night', () {
    test('runs from phone down to first pickup', () {
      final estimate = estimateSleep(
        morning: _morning,
        events: _usualNight(),
        dataEnd: _end,
        sleepWindow: _window,
      )!;

      expect(estimate.start, _evening(23, 30));
      expect(estimate.end, _next(7));
      expect(estimate.minutes, 450);
    });

    test('is trusted when it fits their own stated hours', () {
      final estimate = estimateSleep(
        morning: _morning,
        events: _usualNight(),
        dataEnd: _end,
        sleepWindow: _window,
      )!;

      // 0.4 + 0.2 (a plausible length) + 0.3 * (450 / 480 of the window).
      expect(estimate.confidence, closeTo(0.4 + 0.2 + 0.3 * 450 / 480, 1e-9));
    });

    test('is a little less sure without stated hours', () {
      final estimate = estimateSleep(
        morning: _morning,
        events: _usualNight(),
        dataEnd: _end,
      )!;

      expect(estimate.minutes, 450);
      expect(estimate.confidence, closeTo(0.7, 1e-9));
    });

    test('becomes the sleep fields of a daily row', () {
      final features = estimateSleep(
        morning: _morning,
        events: _usualNight(),
        dataEnd: _end,
        sleepWindow: _window,
      )!.toFeatures('2026-10-02');

      expect(features.dayKey, '2026-10-02');
      expect(features.estimatedSleepStartMinute, 23 * 60 + 30);
      expect(features.estimatedSleepEndMinute, 7 * 60);
      expect(features.estimatedSleepMinutes, 450);
      expect(features.screenOnMinutes, isNull);
    });
  });

  group('interruptions', () {
    test('a glance at a notification does not cut the night', () {
      final estimate = estimateSleep(
        morning: _morning,
        events: [
          ..._usualNight(),
          ..._use(_next(3), _next(3, 0, 30)),
        ],
        dataEnd: _end,
        sleepWindow: _window,
      )!;

      expect(estimate.minutes, 450);
    });

    test('a real wake splits the night and the longer piece is taken', () {
      final estimate = estimateSleep(
        morning: _morning,
        events: [
          ..._usualNight(),
          ..._use(_next(3), _next(3, 10)),
        ],
        dataEnd: _end,
        sleepWindow: _window,
      )!;

      // 23:30 to 03:00 is 210 minutes; 03:10 to 07:00 is 230.
      expect(estimate.start, _next(3, 10));
      expect(estimate.minutes, 230);
    });
  });

  group('different kinds of night', () {
    test('a late night and a late morning', () {
      final estimate = estimateSleep(
        morning: _morning,
        events: [
          ..._use(_evening(22), _next(3, 30)),
          ..._use(_next(11, 30), _next(12)),
        ],
        dataEnd: _end,
        sleepWindow: _window,
      )!;

      expect(estimate.start, _next(3, 30));
      expect(estimate.end, _next(11, 30));
      expect(estimate.minutes, 480);
      // Only part of it falls in the stated hours, so it is trusted less.
      expect(estimate.confidence, lessThan(0.88));
    });

    test('a stated window that starts after midnight is still a night', () {
      const lateWindow = SleepWindow(startMinutes: 30, endMinutes: 8 * 60 + 30);

      final estimate = estimateSleep(
        morning: _morning,
        events: [
          ..._use(_evening(22), _next(0, 30)),
          ..._use(_next(8, 30), _next(9)),
        ],
        dataEnd: _end,
        sleepWindow: lateWindow,
      )!;

      expect(estimate.minutes, 480);
      expect(estimate.confidence, closeTo(0.4 + 0.2 + 0.3, 1e-9));
    });

    test('an evening gap away from the night is not a night', () {
      final estimate = estimateSleep(
        morning: _morning,
        events: [
          ..._use(_evening(18), _evening(18, 10)),
          // Four hours with the phone down, early in the evening.
          ..._use(_evening(22, 10), _evening(23, 50)),
          ..._use(_next(7), _next(7, 20)),
        ],
        dataEnd: _end,
        sleepWindow: _window,
      )!;

      expect(estimate.start, _evening(23, 50));
      expect(estimate.minutes, 430);
    });
  });

  group('when there is no night to find', () {
    test('a phone left alone all day is not sleep', () {
      expect(
        estimateSleep(
          morning: _morning,
          events: _use(_next(13), _next(13, 20)),
          dataEnd: _end,
        ),
        isNull,
      );
    });

    test('a gap shorter than a night is not one', () {
      expect(
        estimateSleep(
          morning: _morning,
          events: [
            ..._use(_evening(22), _next(2)),
            ..._use(_next(4, 30), _next(5)),
          ],
          dataEnd: _end,
        ),
        isNull,
      );
    });

    test('a night with no pickup yet in the data has not ended', () {
      expect(
        estimateSleep(
          morning: _morning,
          events: _use(_evening(22), _evening(23, 30)),
          dataEnd: _next(11),
        ),
        isNull,
      );
    });

    test('before the morning has had time to show a pickup there is no answer', () {
      expect(
        estimateSleep(
          morning: _morning,
          events: _usualNight(),
          dataEnd: _next(8),
        ),
        isNull,
      );
    });

    test('use through the whole night leaves no gap', () {
      expect(
        estimateSleep(
          morning: _morning,
          events: _use(_evening(20), _next(6)),
          dataEnd: _end,
        ),
        isNull,
      );
    });

    test('no events at all is no estimate', () {
      expect(
        estimateSleep(morning: _morning, events: const [], dataEnd: _end),
        isNull,
      );
    });

    test('sleeping by day is outside what this can read', () {
      const dayWindow = SleepWindow(startMinutes: 9 * 60, endMinutes: 17 * 60);

      expect(
        estimateSleep(
          morning: _morning,
          events: [
            ..._use(_evening(20), _next(8, 30)),
            ..._use(_next(17), _next(17, 30)),
          ],
          dataEnd: DateTime(2026, 10, 3),
          sleepWindow: dayWindow,
        ),
        isNull,
      );
    });
  });

  group('how much data backed it', () {
    test('a night that began before the data did is cut and trusted less', () {
      final full = estimateSleep(
        morning: _morning,
        events: _usualNight(),
        dataEnd: _end,
        sleepWindow: _window,
      )!;
      final cut = estimateSleep(
        morning: _morning,
        events: [..._use(_next(7), _next(7, 20))],
        dataEnd: _end,
        dataStart: _next(1),
        sleepWindow: _window,
      )!;

      expect(cut.start, _next(1));
      expect(cut.minutes, 360);
      expect(cut.confidence, lessThan(full.confidence));
    });

    test('data that starts after the pickup leaves nothing to read', () {
      expect(
        estimateSleep(
          morning: _morning,
          events: _usualNight(),
          dataEnd: _end,
          dataStart: _next(9),
        ),
        isNull,
      );
    });

    test('an implausibly short or long night is trusted less than a normal one', () {
      final normal = estimateSleep(
        morning: _morning,
        events: _usualNight(),
        dataEnd: _end,
      )!;
      final short = estimateSleep(
        morning: _morning,
        events: [
          ..._use(_evening(22), _next(1, 30)),
          ..._use(_next(4, 40), _next(5)),
        ],
        dataEnd: _end,
      )!;

      expect(short.minutes, 190);
      expect(short.confidence, lessThan(normal.confidence));
    });
  });

  group('sleepRegularityMinutes', () {
    DailyFeatures night(int day, int startMinute, int minutes) => DailyFeatures(
      dayKey: '2026-10-${day.toString().padLeft(2, '0')}',
      estimatedSleepStartMinute: startMinute,
      estimatedSleepMinutes: minutes,
    );

    test('identical nights are perfectly regular', () {
      final rows = [for (var d = 1; d <= 7; d++) night(d, 23 * 60, 480)];

      expect(sleepRegularityMinutes(rows), closeTo(0, 1e-6));
    });

    test('a half-hour wobble either side reads as about half an hour', () {
      final rows = [
        for (var d = 1; d <= 8; d++)
          night(d, d.isEven ? 22 * 60 + 30 : 23 * 60 + 30, 480),
      ];

      expect(sleepRegularityMinutes(rows), closeTo(30, 2));
    });

    test('midnight is not a cliff', () {
      // Midpoints of 23:50 and 00:10 are twenty minutes apart.
      final rows = [
        for (var d = 1; d <= 8; d++)
          d.isEven ? night(d, 23 * 60 + 40, 20) : night(d, 0 * 60, 20),
      ];

      expect(sleepRegularityMinutes(rows)!, lessThan(15));
    });

    test('fewer than five nights says nothing', () {
      final rows = [for (var d = 1; d <= 4; d++) night(d, 23 * 60, 480)];

      expect(sleepRegularityMinutes(rows), isNull);
    });

    test('rows without a sleep estimate are not counted', () {
      final rows = [
        for (var d = 1; d <= 4; d++) night(d, 23 * 60, 480),
        const DailyFeatures(dayKey: '2026-10-05'),
      ];

      expect(sleepRegularityMinutes(rows), isNull);
    });

    test('only the most recent nights count', () {
      final rows = [
        // Very irregular long ago.
        night(1, 20 * 60, 480),
        night(2, 2 * 60, 480),
        night(3, 20 * 60, 480),
        night(4, 2 * 60, 480),
        for (var d = 5; d <= 9; d++) night(d, 23 * 60, 480),
      ];

      expect(sleepRegularityMinutes(rows, nights: 5), closeTo(0, 1e-6));
    });
  });
}
