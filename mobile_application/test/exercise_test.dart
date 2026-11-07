import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/domain/exercises/exercise_plan.dart';
import 'package:solace_mobile/features/exercises/exercise_page.dart';

Widget _host(Widget page, void Function(bool?) onResult) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => onResult(await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('breathing timing', () {
    const pattern = BreathPattern(inSeconds: 4, outSeconds: 4, cycles: 2);

    test('fills on the way in, empties on the way out', () {
      expect(breathAt(pattern, Duration.zero).size, 0);
      expect(breathAt(pattern, const Duration(seconds: 2)).size, closeTo(0.5, 0.001));
      final top = breathAt(pattern, const Duration(milliseconds: 3999));
      expect(top.phase, BreathPhase.inhale);
      expect(top.size, greaterThan(0.99));
      expect(breathAt(pattern, const Duration(seconds: 4)).phase, BreathPhase.exhale);
      expect(breathAt(pattern, const Duration(seconds: 6)).size, closeTo(0.5, 0.001));
    });

    test('counts breaths and ends at the end', () {
      expect(breathAt(pattern, const Duration(seconds: 9)).cycle, 1);
      expect(breathAt(pattern, const Duration(seconds: 15)).done, isFalse);
      expect(breathAt(pattern, const Duration(seconds: 16)).done, isTrue);
      expect(breathAt(pattern, const Duration(minutes: 5)).done, isTrue);
    });

    test('box breathing holds full and empty', () {
      final box = breathPatternFor(ExerciseGuide.boxBreathing)!;
      expect(box.cycleSeconds, 16);
      final held = breathAt(box, const Duration(seconds: 5));
      expect(held.phase, BreathPhase.holdIn);
      expect(held.size, 1);
      final rest = breathAt(box, const Duration(seconds: 13));
      expect(rest.phase, BreathPhase.holdOut);
      expect(rest.size, 0);
    });

    test('a longer breath out than in', () {
      final p = breathPatternFor(ExerciseGuide.longExhale)!;
      expect(p.outSeconds, greaterThan(p.inSeconds));
      expect(breathPatternFor(ExerciseGuide.grounding), isNull);
    });
  });

  group('the library', () {
    test('guided ideas are tagged, and the new ones are in the lifestyle tier', () {
      final raw = jsonDecode(File('assets/activity_library.json').readAsStringSync()) as Map<String, dynamic>;
      final all = [for (final a in raw['activities'] as List<dynamic>) Activity.fromMap(a as Map<String, dynamic>)];
      final guided = {for (final a in all) if (a.guide != null) a.id: a.guide};
      expect(guided, {
        'mindfulness-003': ExerciseGuide.breathing,
        'mindfulness-008': ExerciseGuide.grounding,
        'mindfulness-010': ExerciseGuide.longExhale,
        'mindfulness-016': ExerciseGuide.gratitude,
        'mindfulness-023': ExerciseGuide.boxBreathing,
        'mindfulness-024': ExerciseGuide.reframe,
      });
      for (final a in all.where((a) => a.guide != null)) {
        expect(a.review.isApprovedForPrototype, isTrue, reason: a.id);
      }
      expect(all.map((a) => a.id).toSet().length, all.length);
    });

    test('an unknown guide is ignored rather than breaking the idea', () {
      final a = Activity.fromMap({'id': 'x', 'title': 't', 'guide': 'telepathy'});
      expect(a.guide, isNull);
    });

    test('every writing guide has prompts and every guide has an intro', () {
      for (final g in ExerciseGuide.values) {
        expect(exerciseIntro(g), isNotEmpty);
        expect(exerciseTakesWords(g), g == ExerciseGuide.gratitude || g == ExerciseGuide.reframe);
      }
    });
  });

  group('ExercisePage', () {
    testWidgets('breathing: intro, runs through every breath, then finishes with true', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(const ExercisePage(guide: ExerciseGuide.breathing, title: 'Five breaths'), (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Five breaths'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('exercise-begin')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Breathe in'), findsOneWidget);
      expect(find.text('Breath 1 of 5'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Breathe out'), findsOneWidget);

      await tester.pump(const Duration(seconds: 36));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Nicely done.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exercise-finish')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('stopping early returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(const ExercisePage(guide: ExerciseGuide.longExhale, title: 'Longer out'), (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exercise-begin')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('exercise-stop')));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('grounding: tap what you find, move from five down to one', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(const ExercisePage(guide: ExerciseGuide.grounding, title: 'Five senses'), (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exercise-begin')));
      await tester.pumpAndSettle();

      expect(find.text('things you can see'), findsOneWidget);
      expect(find.text('Skip to next'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(ValueKey('dot-$i')));
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Next'), findsOneWidget);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('grounding-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('thing you can taste'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('grounding-next')));
      await tester.pumpAndSettle();
      expect(find.text('Nicely done.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exercise-finish')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('writing: the words go to the safety check, not to storage', (tester) async {
      String? checked;
      await tester.pumpWidget(
        _host(
          ExercisePage(guide: ExerciseGuide.gratitude, title: 'Three good things', onWords: (w) async => checked = w),
          (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exercise-begin')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('answer-0')), 'A warm cup of tea');
      await tester.tap(find.byKey(const ValueKey('writing-next')));
      await tester.pumpAndSettle();
      // Skipping an empty one is fine.
      await tester.tap(find.byKey(const ValueKey('writing-next')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('answer-2')), 'My sister called');
      await tester.tap(find.byKey(const ValueKey('writing-next')));
      await tester.pumpAndSettle();

      expect(checked, 'A warm cup of tea\nMy sister called');
      expect(find.text('Nicely done.'), findsOneWidget);
    });

    testWidgets('writing nothing at all sends nothing to check', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _host(ExercisePage(guide: ExerciseGuide.reframe, title: 'Another view', onWords: (_) async => calls++), (_) {}),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exercise-begin')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('writing-next')));
        await tester.pumpAndSettle();
      }
      expect(calls, 0);
      expect(find.text('Nicely done.'), findsOneWidget);
    });
  });
}
