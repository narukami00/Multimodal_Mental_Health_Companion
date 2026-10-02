import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/domain/footprint/break_context.dart';
import 'package:solace_mobile/domain/footprint/pattern_features.dart';
import 'package:solace_mobile/domain/footprint/trend_break_detector.dart';
import 'package:solace_mobile/domain/recommendations/event_tagging.dart';

SessionRecord _session(DateTime at, String? text) => SessionRecord(
  id: at.microsecondsSinceEpoch.toString(),
  createdAt: at,
  mode: CaptureMode.text,
  text: text,
);

FeatureBreak _feature(
  PatternFeature feature, {
  required DateTime start,
  required DateTime latest,
}) => FeatureBreak(
  feature: feature,
  direction: BreakDirection.up,
  startDay: start,
  latestDay: latest,
  days: latest.difference(start).inDays + 1,
  meanZ: 3,
  kind: BreakKind.fast,
);

/// A shift from 28 to 30 October across screen and rhythm.
TrendBreak _shift({bool withMood = false}) => TrendBreak([
  _feature(
    PatternFeature.screenOnMinutes,
    start: DateTime(2026, 10, 28),
    latest: DateTime(2026, 10, 30),
  ),
  _feature(
    PatternFeature.sleepOnset,
    start: DateTime(2026, 10, 28),
    latest: DateTime(2026, 10, 30),
  ),
  if (withMood)
    _feature(
      PatternFeature.moodScore,
      start: DateTime(2026, 10, 29),
      latest: DateTime(2026, 10, 30),
    ),
]);

void main() {
  group('TrendBreak', () {
    test('spans its features and keeps a stable key', () {
      final shift = _shift();

      expect(shift.startDay, DateTime(2026, 10, 28));
      expect(shift.latestDay, DateTime(2026, 10, 30));
      expect(shift.families, {PatternFamily.screen, PatternFamily.rhythm});
      expect(shift.key, '2026-10-28:rhythm+screen');
    });

    test('the key does not depend on the order the features came in', () {
      final a = TrendBreak([
        _feature(PatternFeature.sleepOnset, start: DateTime(2026, 10, 28), latest: DateTime(2026, 10, 30)),
        _feature(PatternFeature.screenOnMinutes, start: DateTime(2026, 10, 28), latest: DateTime(2026, 10, 30)),
      ]);

      expect(a.key, _shift().key);
    });

    test('the key follows the start of the shift, not how long it has gone on', () {
      final longer = TrendBreak([
        _feature(PatternFeature.screenOnMinutes, start: DateTime(2026, 10, 28), latest: DateTime(2026, 11, 2)),
        _feature(PatternFeature.sleepOnset, start: DateTime(2026, 10, 28), latest: DateTime(2026, 11, 2)),
      ]);

      expect(longer.key, _shift().key);
    });
  });

  group('linkBreakContext', () {
    test('finds the themes they wrote about around the shift', () {
      final context = linkBreakContext(
        shift: _shift(),
        sessions: [
          _session(DateTime(2026, 10, 27, 20), 'A hard day at work again'),
          _session(DateTime(2026, 10, 29, 21), 'Work is a lot, and I am tired'),
          _session(DateTime(2026, 10, 30, 9), 'Slept badly'),
        ],
      );

      // Work twice; sleep (tired, slept) twice; work first on the tie by name?
      expect(context.nearbyThemes, containsAll(['work', 'sleep']));
      expect(context.hasNearbyContext, isTrue);
    });

    test('most-mentioned first, ties alphabetical', () {
      final context = linkBreakContext(
        shift: _shift(),
        sessions: [
          _session(DateTime(2026, 10, 28, 9), 'money worries'),
          _session(DateTime(2026, 10, 29, 9), 'a bill came, and work too'),
          _session(DateTime(2026, 10, 30, 9), 'more bills'),
        ],
      );

      expect(context.nearbyThemes.first, 'money');
      expect(context.nearbyThemes, contains('work'));
    });

    test('reaches a day before the shift began, and not two', () {
      final context = linkBreakContext(
        shift: _shift(),
        sessions: [
          _session(DateTime(2026, 10, 27, 9), 'family dinner'),
          _session(DateTime(2026, 10, 26, 9), 'work deadline'),
        ],
      );

      expect(context.nearbyThemes, ['relationships']);
    });

    test('ignores check-ins after the latest day of the shift', () {
      final context = linkBreakContext(
        shift: _shift(),
        sessions: [_session(DateTime(2026, 10, 31, 9), 'work work work')],
      );

      expect(context.nearbyThemes, isEmpty);
      expect(context.hasNearbyContext, isFalse);
    });

    test('check-ins with no text, or no known theme, add nothing', () {
      final context = linkBreakContext(
        shift: _shift(),
        sessions: [
          _session(DateTime(2026, 10, 29, 9), null),
          _session(DateTime(2026, 10, 29, 10), '   '),
          _session(DateTime(2026, 10, 29, 11), 'a strange and quiet feeling'),
        ],
      );

      expect(context.nearbyThemes, isEmpty);
    });

    test('knows whether their own mood moved with the phone', () {
      expect(
        linkBreakContext(shift: _shift(), sessions: const []).moodShifted,
        isFalse,
      );
      expect(
        linkBreakContext(shift: _shift(withMood: true), sessions: const [])
            .moodShifted,
        isTrue,
      );
    });
  });

  group('promptThemes', () {
    test('offers nearby themes first, then the rest, each once', () {
      final context = linkBreakContext(
        shift: _shift(),
        sessions: [_session(DateTime(2026, 10, 29, 9), 'so tired, and work')],
      );

      final themes = context.promptThemes;
      expect(themes.toSet(), EventTaggingService.knownThemes.toSet());
      expect(themes.length, EventTaggingService.knownThemes.length);
      expect(themes.take(2).toSet(), {'work', 'sleep'});
    });

    test('with nothing nearby, is just the known themes', () {
      final context = linkBreakContext(shift: _shift(), sessions: const []);

      expect(context.promptThemes, EventTaggingService.knownThemes);
    });
  });
}
