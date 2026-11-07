import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/domain/insights/weekly_recap.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/forest/forest_garden.dart';
import 'package:solace_mobile/domain/goals/goals.dart';
import 'package:solace_mobile/features/forest/forest_controller.dart';
import 'package:solace_mobile/features/goals/goals_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

DailyFeatures _row(
  String day, {
  int? screen,
  int? pickups,
  int? longest,
  int? late,
  int? first,
  bool complete = true,
  bool usage = true,
}) => DailyFeatures(
  dayKey: day,
  sources: usage ? {'usage', if (complete) 'usageFinal'} : const {},
  screenOnMinutes: screen,
  unlockCount: pickups,
  longestSessionMinutes: longest,
  screenMinutesInSleepWindow: late,
  firstPickupMinute: first,
);

Goal _goal(GoalMeasure m, int target, {String created = '2026-11-01', bool weekdays = false}) =>
    Goal(id: 'g-${m.name}', measure: m, target: target, createdDay: created, weekdaysOnly: weekdays);

void main() {
  group('judging one goal on one day', () {
    final screen = _goal(GoalMeasure.screenTime, 180);

    test('at most: equal to the target is met, over it is not this time', () {
      expect(judgeGoal(screen, '2026-11-03', _row('2026-11-03', screen: 180)).outcome, GoalOutcome.met);
      expect(judgeGoal(screen, '2026-11-03', _row('2026-11-03', screen: 181)).outcome, GoalOutcome.notThisTime);
      expect(judgeGoal(screen, '2026-11-03', _row('2026-11-03', screen: 181)).value, 181);
    });

    test('first pickup is the other way round: later is better', () {
      final first = _goal(GoalMeasure.firstPickup, 480);
      expect(judgeGoal(first, '2026-11-03', _row('2026-11-03', first: 480)).outcome, GoalOutcome.met);
      expect(judgeGoal(first, '2026-11-03', _row('2026-11-03', first: 470)).outcome, GoalOutcome.notThisTime);
    });

    test('a day with no data, or a half-read day, is never counted either way', () {
      expect(judgeGoal(screen, '2026-11-03', null).outcome, GoalOutcome.noData);
      expect(judgeGoal(screen, '2026-11-03', _row('2026-11-03', screen: 500, usage: false)).outcome, GoalOutcome.noData);
      expect(judgeGoal(screen, '2026-11-03', _row('2026-11-03', screen: 500, complete: false)).outcome, GoalOutcome.noData);
      expect(judgeGoal(screen, '2026-11-03', _row('2026-11-03')).outcome, GoalOutcome.noData);
    });

    test('rest days, days before the goal, and weekends for a weekday goal are skipped', () {
      final row = _row('2026-11-03', screen: 500);
      expect(judgeGoal(screen, '2026-11-03', row, resting: true).outcome, GoalOutcome.skipped);
      expect(judgeGoal(screen, '2026-10-31', _row('2026-10-31', screen: 500)).outcome, GoalOutcome.skipped);
      final weekday = _goal(GoalMeasure.screenTime, 180, weekdays: true);
      expect(judgeGoal(weekday, '2026-11-07', _row('2026-11-07', screen: 500)).outcome, GoalOutcome.skipped, reason: 'a Saturday');
      expect(judgeGoal(weekday, '2026-11-06', _row('2026-11-06', screen: 500)).outcome, GoalOutcome.notThisTime, reason: 'a Friday');
    });
  });

  group('judging a run of days', () {
    test('any goal met makes the day count once, and nothing before the goal was set is judged', () {
      final goals = [_goal(GoalMeasure.screenTime, 120, created: '2026-11-02'), _goal(GoalMeasure.pickups, 40, created: '2026-11-02')];
      final days = judgeGoals(
        goals: goals,
        rowsByDay: {
          '2026-11-01': _row('2026-11-01', screen: 10, pickups: 1),
          '2026-11-02': _row('2026-11-02', screen: 90, pickups: 90),
          '2026-11-03': _row('2026-11-03', screen: 200, pickups: 90),
          '2026-11-04': _row('2026-11-04', screen: 90, pickups: 30),
        },
        restDays: const {},
        lastDay: '2026-11-04',
      );
      expect(days.map((d) => d.day), ['2026-11-02', '2026-11-03', '2026-11-04']);
      expect(days.map((d) => d.anyMet), [true, false, true]);
      expect(days[1].judged, isTrue);
    });

    test('no goals, nothing to judge', () {
      expect(judgeGoals(goals: const [], rowsByDay: const {}, restDays: const {}, lastDay: '2026-11-04'), isEmpty);
    });
  });

  group('suggested targets', () {
    test('a little below the person\'s own usual, rounded to the stepper', () {
      final rows = [for (var i = 1; i <= 7; i++) _row('2026-11-0$i', screen: 200)];
      expect(suggestedTarget(GoalMeasure.screenTime, rows), 180);
    });

    test('nothing until there are enough full days', () {
      final rows = [for (var i = 1; i <= 4; i++) _row('2026-11-0$i', screen: 200)];
      expect(suggestedTarget(GoalMeasure.screenTime, rows), isNull);
      final half = [for (var i = 1; i <= 7; i++) _row('2026-11-0$i', screen: 200, complete: false)];
      expect(suggestedTarget(GoalMeasure.screenTime, half), isNull);
    });

    test('first pickup suggests a little later than usual', () {
      final rows = [for (var i = 1; i <= 7; i++) _row('2026-11-0$i', first: 450)];
      expect(suggestedTarget(GoalMeasure.firstPickup, rows), 465);
    });
  });

  group('gentle adjustments', () {
    final goal = _goal(GoalMeasure.screenTime, 180);
    const miss = GoalOutcome.notThisTime;
    const hit = GoalOutcome.met;

    test('mostly missed offers an easier number; always met offers a firmer one; otherwise nothing', () {
      final ease = adjustmentFor(goal, [hit, miss, miss, miss, miss]);
      expect(ease!.kind, GoalAdjustmentKind.ease);
      expect(ease.newTarget, greaterThan(180));
      final tighten = adjustmentFor(goal, [hit, hit, hit, hit, hit]);
      expect(tighten!.kind, GoalAdjustmentKind.tighten);
      expect(tighten.newTarget, lessThan(180));
      expect(adjustmentFor(goal, [hit, miss, hit, miss, hit]), isNull);
    });

    test('needs enough judged days, and ignores days that were not judged', () {
      expect(adjustmentFor(goal, [miss, miss, miss, miss]), isNull);
      expect(adjustmentFor(goal, [miss, GoalOutcome.noData, miss, GoalOutcome.skipped, miss, miss, miss]), isNotNull);
    });

    test('first pickup eases by going earlier', () {
      final first = _goal(GoalMeasure.firstPickup, 480);
      expect(adjustmentFor(first, [miss, miss, miss, miss, miss])!.newTarget, 465);
    });
  });

  group('wording', () {
    test('values read plainly', () {
      expect(describeGoalValue(GoalMeasure.screenTime, 190), '3 h 10 min');
      expect(describeGoalValue(GoalMeasure.screenTime, 45), '45 min');
      expect(describeGoalValue(GoalMeasure.pickups, 1), '1 pickup');
      expect(describeGoalValue(GoalMeasure.firstPickup, 480), '8:00 am');
      expect(describeGoalValue(GoalMeasure.firstPickup, 12 * 60 + 5), '12:05 pm');
    });

    test('a goal survives being stored', () {
      final g = _goal(GoalMeasure.lateNight, 20, weekdays: true);
      final back = Goal.fromMap(g.toMap())!;
      expect((back.measure, back.target, back.weekdaysOnly, back.createdDay), (GoalMeasure.lateNight, 20, true, '2026-11-01'));
      expect(Goal.fromMap({'measure': 'nonsense'}), isNull);
    });
  });

  group('GoalsController', () {
    late SharedPreferences prefs;
    late List<DailyFeatures> rows;
    var now = DateTime(2026, 11, 5, 10);

    GoalsController make() => GoalsController(preferences: prefs, loadRows: () async => rows, clock: () => now);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 11, 5, 10);
      rows = [
        _row('2026-11-03', screen: 100, pickups: 30),
        _row('2026-11-04', screen: 300, pickups: 90),
      ];
    });

    test('goals are kept, judged only for finished days, and can be changed and removed', () async {
      final c = make();
      await c.load();
      expect(c.hasGoals, isFalse);

      now = DateTime(2026, 11, 3, 9);
      final goal = await c.add(GoalMeasure.screenTime, 150);
      now = DateTime(2026, 11, 5, 10);
      await c.refresh();
      expect(c.days.map((d) => d.day), ['2026-11-03', '2026-11-04']);
      expect(c.metDayKeys, ['2026-11-03']);
      expect(c.lastWeek, (judged: 2, met: 1));

      await c.update(goal.id, target: 400);
      expect(c.metDayKeys, ['2026-11-03', '2026-11-04']);

      final again = make();
      await again.load();
      expect(again.goals.single.target, 400);

      await again.remove(goal.id);
      expect(again.hasGoals, isFalse);
      expect(again.days, isEmpty);
    });

    test('a target is kept within what makes sense', () async {
      final c = make();
      await c.load();
      final g = await c.add(GoalMeasure.pickups, 1);
      expect(g.target, GoalMeasure.pickups.minTarget);
    });
  });

  group('weekly recaps', () {
    SessionRecord entry(DateTime at) => SessionRecord(id: '${at.microsecondsSinceEpoch}', createdAt: at, mode: CaptureMode.text, text: 'ok', emotionResults: const []);

    test('a week says how many days a goal was met, and stays as it was with no goals', () {
      final sessions = [entry(DateTime(2026, 11, 3, 9))];
      final now = DateTime(2026, 11, 12);
      final plain = weeklyRecaps(sessions, const [], now).single;
      expect(plain.lines.any((l) => l.contains('phone goal')), isFalse);

      final days = judgeGoals(
        goals: [_goal(GoalMeasure.screenTime, 150, created: '2026-11-02')],
        rowsByDay: {
          '2026-11-02': _row('2026-11-02', screen: 100),
          '2026-11-03': _row('2026-11-03', screen: 300),
          '2026-11-04': _row('2026-11-04', screen: 100),
        },
        restDays: const {},
        lastDay: '2026-11-04',
      );
      final withGoals = weeklyRecaps(sessions, const [], now, goalDays: days).single;
      expect(withGoals.goalDaysJudged, 3);
      expect(withGoals.goalDaysMet, 2);
      expect(withGoals.lines, contains('You met a phone goal on 2 of 3 days.'));
      expect(overallSummary([withGoals])!.join(' '), contains('You met a phone goal on 2 of 3 days.'));
    });

    test('a week with goals but none met is told kindly', () {
      final sessions = [entry(DateTime(2026, 11, 3, 9))];
      final days = judgeGoals(
        goals: [_goal(GoalMeasure.screenTime, 50, created: '2026-11-02')],
        rowsByDay: {'2026-11-03': _row('2026-11-03', screen: 300)},
        restDays: const {},
        lastDay: '2026-11-03',
      );
      final recap = weeklyRecaps(sessions, const [], DateTime(2026, 11, 12), goalDays: days).single;
      expect(recap.lines, contains('Your phone goals did not line up this week, and that is okay.'));
    });
  });

  group('the forest', () {
    test('a day with a met goal waters once, however many goals were met, and not twice on a second look', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 11, 8, 8);
      List<DailyFeatures> rows() => [
        _row('2026-11-05', screen: 100, pickups: 10),
        _row('2026-11-06', screen: 100, pickups: 10),
        _row('2026-11-07', screen: 100, pickups: 10),
      ];
      final setter = GoalsController(preferences: prefs, loadRows: () async => rows(), clock: () => DateTime(2026, 11, 5, 8));
      await setter.load();
      await setter.add(GoalMeasure.screenTime, 150);
      await setter.add(GoalMeasure.pickups, 20);

      final goals = GoalsController(preferences: prefs, loadRows: () async => rows(), clock: () => now);
      await goals.load();
      expect(goals.metDayKeys, ['2026-11-05', '2026-11-06', '2026-11-07']);

      final sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
      final forest = ForestController(store: InMemoryForestStore(), sessions: sessions, goals: goals, clock: () => now);
      await forest.load();

      final waters = forest.events.where((e) => e.kind == WaterKind.goal).toList();
      expect(waters, hasLength(3), reason: 'one per day, though two goals were met on each');
      expect(forest.waiting.where((e) => e.kind == WaterKind.goal), hasLength(1), reason: 'yesterday\'s pours when the forest opens');

      await goals.refresh();
      expect(forest.events.where((e) => e.kind == WaterKind.goal), hasLength(3));
    });
  });
}
