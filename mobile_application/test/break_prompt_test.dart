import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/research/ablations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/break_annotation.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_break_annotation_repository.dart';
import 'package:solace_mobile/data/repositories/shared_preferences_break_annotation_repository.dart';
import 'package:solace_mobile/domain/footprint/break_prompt_policy.dart';
import 'package:solace_mobile/domain/footprint/pattern_features.dart';
import 'package:solace_mobile/domain/footprint/trend_break_detector.dart';
import 'package:solace_mobile/features/footprint/break_prompt_controller.dart';

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// A steady person for [days] from 1 September, with a two-family shift on the
/// days [shiftFrom] to the end.
List<DailyFeatures> _rows({int days = 60, int? shiftFrom}) {
  final random = math.Random(5);
  double gauss() =>
      math.sqrt(-2 * math.log(1 - random.nextDouble())) *
      math.cos(2 * math.pi * random.nextDouble());
  return [
    for (var i = 0; i < days; i++)
      () {
        final day = DateTime(2026, 9, 1 + i);
        final shifted = shiftFrom != null && i >= shiftFrom;
        return DailyFeatures(
          dayKey: _key(day),
          sources: const {'usage', 'usageFinal'},
          screenOnMinutes: (200 + 18 * gauss() + (shifted ? 130 : 0)).round(),
          estimatedSleepStartMinute:
              ((23 * 60 + 30 + 18 * gauss() + (shifted ? 190 : 0)).round()) % 1440,
        );
      }(),
  ];
}

SessionRecord _session(DateTime at, String text) => SessionRecord(
  id: at.microsecondsSinceEpoch.toString(),
  createdAt: at,
  mode: CaptureMode.text,
  text: text,
);

// 31 October; the last three finished days (28 to 30) are the shift.
final _now = DateTime(2026, 10, 31, 9);
final _shiftFrom = 57;

TrendBreakReport _report({bool shifted = true}) => detectTrendBreaks(
  rows: _rows(shiftFrom: shifted ? _shiftFrom : null),
  asOf: _now,
);

void main() {
  test('the fixture produces a surfaced shift for the policy to judge', () {
    expect(_report().surfaced, isNotNull);
    expect(_report(shifted: false).surfaced, isNull);
  });

  group('currentBreakPrompt', () {
    BreakPrompt? ask({
      List<BreakAnnotation> annotations = const [],
      DateTime? now,
      bool muted = false,
      bool safety = false,
      bool shifted = true,
    }) => currentBreakPrompt(
      report: _report(shifted: shifted),
      sessions: [_session(DateTime(2026, 10, 29, 20), 'a hard week at work')],
      annotations: annotations,
      now: now ?? _now,
      muted: muted,
      safetyActive: safety,
    );

    BreakAnnotation shownAt(DateTime at, {String? key, BreakAnnotationStatus? status}) =>
        BreakAnnotation(
          breakKey: key ?? _report().surfaced!.key,
          status: status ?? BreakAnnotationStatus.shown,
          shownAt: at,
        );

    test('asks about a surfaced shift, for the first time', () {
      final prompt = ask()!;

      expect(prompt.isNew, isTrue);
      expect(prompt.context.nearbyThemes, ['work']);
    });

    test('asks nothing when nothing shifted', () {
      expect(ask(shifted: false), isNull);
    });

    test('never when the person has turned these questions off', () {
      expect(ask(muted: true), isNull);
    });

    test('never while safety support is active', () {
      expect(ask(safety: true), isNull);
    });

    test('keeps showing a question that has not been answered, but not as new', () {
      final prompt = ask(
        annotations: [shownAt(_now.subtract(const Duration(hours: 5)))],
      )!;

      expect(prompt.isNew, isFalse);
    });

    test('lets an ignored question expire after a day, and never asks again', () {
      expect(
        ask(annotations: [shownAt(_now.subtract(const Duration(hours: 25)))]),
        isNull,
      );
    });

    test('an answered shift is never asked about again', () {
      expect(
        ask(
          annotations: [
            shownAt(
              _now.subtract(const Duration(hours: 2)),
              status: BreakAnnotationStatus.answered,
            ),
          ],
        ),
        isNull,
      );
    });

    test('a declined shift is never asked about again', () {
      expect(
        ask(
          annotations: [
            shownAt(
              _now.subtract(const Duration(hours: 2)),
              status: BreakAnnotationStatus.dismissed,
            ),
          ],
        ),
        isNull,
      );
    });

    test('a new question waits out the cap after the last one', () {
      final other = shownAt(
        _now.subtract(const Duration(days: 3)),
        key: '2026-10-01:screen+rhythm',
        status: BreakAnnotationStatus.answered,
      );

      expect(ask(annotations: [other]), isNull);
    });

    test('and is allowed once a week has passed', () {
      final other = shownAt(
        _now.subtract(const Duration(days: 8)),
        key: '2026-10-01:screen+rhythm',
        status: BreakAnnotationStatus.answered,
      );

      expect(ask(annotations: [other])?.isNew, isTrue);
    });
  });

  group('recentChosenThemes', () {
    BreakAnnotation answered(String? theme, DateTime at, {String key = 'k'}) =>
        BreakAnnotation(
          breakKey: key,
          status: BreakAnnotationStatus.answered,
          shownAt: at,
          decidedAt: at,
          theme: theme,
        );

    test('are the themes chosen in the last few days, sorted and once each', () {
      final themes = recentChosenThemes([
        answered('work', _now.subtract(const Duration(days: 1)), key: 'a'),
        answered('work', _now.subtract(const Duration(days: 2)), key: 'b'),
        answered('home', _now.subtract(const Duration(hours: 5)), key: 'c'),
      ], _now);

      expect(themes, ['home', 'work']);
    });

    test('forget themes after three days', () {
      expect(
        recentChosenThemes([
          answered('work', _now.subtract(const Duration(days: 4))),
        ], _now),
        isEmpty,
      );
    });

    test('"nothing in particular" and declined answers add no theme', () {
      expect(
        recentChosenThemes([
          answered(null, _now.subtract(const Duration(hours: 1)), key: 'a'),
          BreakAnnotation(
            breakKey: 'b',
            status: BreakAnnotationStatus.dismissed,
            shownAt: _now,
            decidedAt: _now,
          ),
          BreakAnnotation(
            breakKey: 'c',
            status: BreakAnnotationStatus.shown,
            shownAt: _now,
          ),
        ], _now),
        isEmpty,
      );
    });
  });

  group('BreakAnnotation', () {
    test('round-trips', () {
      final annotation = BreakAnnotation(
        breakKey: 'k',
        status: BreakAnnotationStatus.shown,
        shownAt: _now,
      ).answered(theme: 'sleep', at: _now.add(const Duration(minutes: 3)));

      final restored = BreakAnnotation.fromMap(annotation.toMap())!;

      expect(restored.status, BreakAnnotationStatus.answered);
      expect(restored.theme, 'sleep');
      expect(restored.decidedAt, _now.add(const Duration(minutes: 3)));
    });

    test('an unreadable status reads as declined, never as a question to repeat', () {
      final restored = BreakAnnotation.fromMap({
        'breakKey': 'k',
        'status': 'teleported',
        'shownAt': _now.toIso8601String(),
      })!;

      expect(restored.status, BreakAnnotationStatus.dismissed);
    });

    test('unusable records are dropped', () {
      expect(BreakAnnotation.fromMap('junk'), isNull);
      expect(BreakAnnotation.fromMap({'breakKey': '', 'shownAt': 'x'}), isNull);
    });
  });

  group('BreakPromptController', () {
    late InMemoryBreakAnnotationRepository repository;
    var muted = false;
    var safety = false;
    var shifted = true;
    var now = _now;

    BreakPromptController build() => BreakPromptController(
      repository: repository,
      rows: () async => _rows(shiftFrom: shifted ? _shiftFrom : null),
      sessions: () => [_session(DateTime(2026, 10, 29, 20), 'work and sleep')],
      muted: () => muted,
      safetyActive: () => safety,
      clock: () => now,
    );

    setUp(() {
      repository = InMemoryBreakAnnotationRepository();
      muted = false;
      safety = false;
      shifted = true;
      now = _now;
    });

    test('with phone signals ablated, nothing is asked and nothing is recorded', () async {
      Ablations.current = const Ablations(phoneSignals: false);
      addTearDown(Ablations.reset);

      final controller = build();
      await controller.refresh();

      expect(controller.current, isNull);
      expect(await repository.loadAll(), isEmpty);
    });

    test('shows a question for a shift and records it as shown once', () async {
      final controller = build();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.refresh();
      await controller.refresh();

      expect(controller.current, isNotNull);
      expect(notifications, 1);
      final saved = await repository.loadAll();
      expect(saved, hasLength(1));
      expect(saved.single.status, BreakAnnotationStatus.shown);
    });

    test('shows nothing when nothing shifted', () async {
      shifted = false;
      final controller = build();

      await controller.refresh();

      expect(controller.current, isNull);
      expect(await repository.loadAll(), isEmpty);
    });

    test('answering with a theme records it and clears the question', () async {
      final controller = build();
      await controller.refresh();

      await controller.answer('work');

      expect(controller.current, isNull);
      final saved = (await repository.loadAll()).single;
      expect(saved.status, BreakAnnotationStatus.answered);
      expect(saved.theme, 'work');
      expect(controller.activeThemes(), ['work']);
    });

    test('"nothing in particular" is an answer with no theme', () async {
      final controller = build();
      await controller.refresh();

      await controller.answer(null);

      final saved = (await repository.loadAll()).single;
      expect(saved.status, BreakAnnotationStatus.answered);
      expect(saved.theme, isNull);
      expect(controller.activeThemes(), isEmpty);
    });

    test('declining records it and the same shift is not asked again', () async {
      final controller = build();
      await controller.refresh();

      await controller.dismiss();
      await controller.refresh();

      expect(controller.current, isNull);
      expect(
        (await repository.loadAll()).single.status,
        BreakAnnotationStatus.dismissed,
      );
    });

    test('turning questions off hides a question already showing', () async {
      final controller = build();
      await controller.refresh();
      expect(controller.current, isNotNull);

      muted = true;
      await controller.refresh();

      expect(controller.current, isNull);
    });

    test('safety support hides it too', () async {
      safety = true;
      final controller = build();

      await controller.refresh();

      expect(controller.current, isNull);
      expect(await repository.loadAll(), isEmpty);
    });

    test('a question left unanswered goes away after a day', () async {
      final controller = build();
      await controller.refresh();

      now = _now.add(const Duration(hours: 25));
      await controller.refresh();

      expect(controller.current, isNull);
    });

    test('deleting everything forgets answers and the current question', () async {
      final controller = build();
      await controller.refresh();
      await controller.answer('home');

      await controller.deleteAll();

      expect(await repository.loadAll(), isEmpty);
      expect(controller.activeThemes(), isEmpty);
    });

    test('a failure while reading never reaches the person', () async {
      final failing = BreakPromptController(
        repository: repository,
        rows: () async => throw StateError('boom'),
        sessions: () => const [],
        muted: () => false,
        safetyActive: () => false,
        clock: () => _now,
      );

      await failing.refresh();

      expect(failing.current, isNull);
    });

    test('answering with nothing showing does nothing', () async {
      final controller = build();

      await controller.answer('work');

      expect(await repository.loadAll(), isEmpty);
    });
  });

  group('SharedPreferencesBreakAnnotationRepository', () {
    test('round-trips and replaces by shift', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesBreakAnnotationRepository(
        await SharedPreferences.getInstance(),
      );
      final shown = BreakAnnotation(
        breakKey: 'k',
        status: BreakAnnotationStatus.shown,
        shownAt: _now,
      );
      await repository.save(shown);
      await repository.save(shown.answered(theme: 'money', at: _now));

      final all = await repository.loadAll();
      expect(all, hasLength(1));
      expect(all.single.theme, 'money');

      await repository.deleteAll();
      expect(await repository.loadAll(), isEmpty);
    });

    test('unreadable stored data is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'footprint.breakAnnotations': '{not json',
      });
      final repository = SharedPreferencesBreakAnnotationRepository(
        await SharedPreferences.getInstance(),
      );

      expect(await repository.loadAll(), isEmpty);
    });
  });

  test('a shift names the families, which the prompt wording will use', () {
    final shift = _report().surfaced!;

    expect(shift.families, containsAll([PatternFamily.screen, PatternFamily.rhythm]));
  });
}
