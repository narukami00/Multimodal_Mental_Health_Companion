import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/domain/goals/goals.dart';
import 'package:solace_mobile/features/goals/goals_card.dart';
import 'package:solace_mobile/features/goals/goals_controller.dart';

DailyFeatures _row(String day, {int screen = 100, int pickups = 20}) =>
    DailyFeatures(dayKey: day, sources: {'usage', 'usageFinal'}, screenOnMinutes: screen, unlockCount: pickups);

void main() {
  late SharedPreferences prefs;
  late GoalsController goals;
  late List<DailyFeatures> rows;
  var now = DateTime(2026, 11, 20, 9);

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GoalsCard(goals: goals)))),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 20, 9);
    rows = [for (var d = 8; d <= 19; d++) _row('2026-11-${d.toString().padLeft(2, '0')}', screen: 200, pickups: 50)];
    goals = GoalsController(preferences: prefs, loadRows: () async => rows, clock: () => now);
    await goals.load();
  });

  testWidgets('with no goals it invites one, and says nothing is taken away', (tester) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('goal-first')), findsOneWidget);
    expect(find.textContaining('Missing one takes nothing away'), findsOneWidget);
  });

  testWidgets('setting a goal starts from a little below the person\'s own usual', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('goal-first')));
    await tester.pumpAndSettle();

    // 12 full days at 200 min: the suggestion is 180 min = 3 h.
    expect(find.byKey(const ValueKey('goal-value')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('goal-value'))).data, '3 h');

    await tester.tap(find.byKey(const ValueKey('goal-less')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('goal-value'))).data, '2 h 50 min');
    await tester.tap(find.byKey(const ValueKey('goal-use-suggestion')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('goal-value'))).data, '3 h');

    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();
    expect(goals.goals.single.measure, GoalMeasure.screenTime);
    expect(goals.goals.single.target, 180);
    expect(find.textContaining('Screen time: at most 3 h'), findsOneWidget);
  });

  testWidgets('shows how the week went, and yesterday kindly', (tester) async {
    now = DateTime(2026, 11, 12, 9);
    await goals.add(GoalMeasure.screenTime, 150);
    now = DateTime(2026, 11, 20, 9);
    rows = [
      for (var d = 12; d <= 19; d++) _row('2026-11-$d', screen: d.isEven ? 100 : 300),
    ];
    await goals.refresh();
    await mount(tester);

    expect(find.byKey(const ValueKey('goals-summary')), findsOneWidget);
    expect(find.textContaining('You met a goal on 3 of the last 7 days.'), findsOneWidget);
    expect(find.textContaining('Yesterday: 5 h. Not this time.'), findsOneWidget);
    expect(find.textContaining('fail'), findsNothing);
  });

  testWidgets('a goal that keeps being missed is offered an easier number, and taking it changes the goal', (tester) async {
    now = DateTime(2026, 11, 10, 9);
    final goal = await goals.add(GoalMeasure.screenTime, 100);
    now = DateTime(2026, 11, 20, 9);
    await goals.refresh();
    await mount(tester);

    expect(find.textContaining('This one has been hard lately'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('goal-offer-${goal.id}')));
    await tester.pumpAndSettle();
    expect(goals.goals.single.target, inInclusiveRange(110, 120), reason: 'about 15% easier, rounded to the stepper');
  });

  testWidgets('a goal can be changed and removed', (tester) async {
    now = DateTime(2026, 11, 10, 9);
    final goal = await goals.add(GoalMeasure.pickups, 60);
    now = DateTime(2026, 11, 20, 9);
    await goals.refresh();
    await mount(tester);

    await tester.tap(find.byKey(ValueKey('goal-${goal.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-weekdays')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();
    expect(goals.goals.single.weekdaysOnly, isTrue);

    await tester.tap(find.byKey(ValueKey('goal-${goal.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-remove')));
    await tester.pumpAndSettle();
    expect(goals.hasGoals, isFalse);
    expect(find.byKey(const ValueKey('goal-first')), findsOneWidget);
  });

  testWidgets('once every measure has a goal there is nothing more to add', (tester) async {
    for (final m in GoalMeasure.values) {
      await goals.add(m, m.defaultTarget);
    }
    await mount(tester);
    expect(find.byKey(const ValueKey('goal-add')), findsNothing);
  });
}
