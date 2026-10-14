import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/domain/insights/what_helped.dart';
import 'package:solace_mobile/features/app_shell/today_footer.dart';

HelpedKind _kind(ActivityType type, int tries, int lighter) =>
    HelpedKind(type: type, tries: tries, lighter: lighter, same: tries - lighter, heavier: 0);

MemoryMoment _moment(String text) => MemoryMoment(
  id: 'm',
  text: text,
  createdAt: DateTime(2026, 10, 12),
  occurredOn: '2026-10-12',
  source: MomentSource.chat,
  state: MomentState.confirmed,
);

Future<void> _pump(WidgetTester tester, TodayFooter footer, {double scale = 1}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(18), child: footer))),
    ),
  );
  await tester.pump();
}

void main() {
  final now = DateTime(2026, 10, 14, 19, 30);

  test('every kind has its own natural headline, none built from the raw activity name', () {
    final seen = <String>{};
    for (final type in ActivityType.values) {
      final line = TodayFooter.headlineFor(type);
      expect(line, endsWith('tends to lift you'));
      expect(seen.add(line), isTrue);
    }
  });

  test('the detail reports what they said, never a cause', () {
    expect(TodayFooter.detailFor(_kind(ActivityType.nature, 4, 3)), 'You felt lighter after it 3 of 4 times.');
    expect(TodayFooter.detailFor(_kind(ActivityType.nature, 3, 3)), 'You felt lighter after it, all 3 times.');
  });

  test('every hour has a caption', () {
    for (var h = 0; h < 24; h++) {
      expect(TodayFooter.periodFor(h).$2, isNotEmpty);
    }
  });

  testWidgets('shows what lifted them when there is something', (tester) async {
    await _pump(tester, TodayFooter(helped: [_kind(ActivityType.nature, 4, 3)], keptMoments: [_moment('A good walk.')], now: now));
    expect(find.byKey(const ValueKey('today-lifted')), findsOneWidget);
    expect(find.text('Time outside tends to lift you'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-moment')), findsNothing);
  });

  testWidgets('falls back to a kept moment, then to a breathing minute', (tester) async {
    await _pump(tester, TodayFooter(helped: const [], keptMoments: [_moment('Working is a great idea.')], now: now));
    expect(find.byKey(const ValueKey('today-moment')), findsOneWidget);
    expect(find.textContaining('Working is a great idea.'), findsOneWidget);

    await _pump(tester, TodayFooter(helped: const [], keptMoments: const [], now: now));
    expect(find.byKey(const ValueKey('today-breathe')), findsOneWidget);
  });

  testWidgets('lays out at large text', (tester) async {
    await _pump(tester, TodayFooter(helped: [_kind(ActivityType.productivity, 6, 5)], keptMoments: const [], now: now), scale: 2.0);
    expect(tester.takeException(), isNull);
    await _pump(tester, TodayFooter(helped: const [], keptMoments: const [], now: now), scale: 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sky is a backdrop with no card, and paints at every hour', (tester) async {
    for (final hour in [2.0, 6.5, 11.0, 15.5, 18.5, 22.0]) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Stack(children: [Positioned(left: 0, right: 0, bottom: 0, child: SkyBackdrop(hour: hour))]))),
      );
      expect(find.byKey(const ValueKey('today-sky')), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
