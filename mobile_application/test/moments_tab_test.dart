import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/features/insights/moments_tab.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';

void main() {
  late MomentsController moments;

  setUp(() async {
    moments = MomentsController(repository: InMemoryMomentRepository());
    await moments.load();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MomentsInsightsTab(moments: moments, onManage: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says what will fill it, and shows nothing invented', (tester) async {
    await pump(tester);

    expect(find.text('Good moments will gather here'), findsOneWidget);
    expect(find.byKey(const ValueKey('moments-list')), findsNothing);
  });

  testWidgets('shows only warm, kept moments, in their own words', (tester) async {
    await tester.runAsync(() async {
      await moments.addManual('A good walk by the river.');
      await moments.addManual('Hard talk with my manager.', tone: MomentTone.heavy);
      final hidden = (await moments.addManual('Set aside one.'))!;
      await moments.hide(hidden.id);
    });
    await pump(tester);

    expect(find.text('A good walk by the river.'), findsOneWidget);
    expect(find.text('Hard talk with my manager.'), findsNothing);
    expect(find.text('Set aside one.'), findsNothing);
  });

  testWidgets('a moment still waiting for a yes is not shown', (tester) async {
    await tester.runAsync(
      () => moments.addManual('Kept.'),
    );
    expect(moments.pending, isEmpty);
    await pump(tester);
    expect(find.text('Kept.'), findsOneWidget);
  });
}
