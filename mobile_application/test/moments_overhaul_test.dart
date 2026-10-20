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

  Future<void> pump(WidgetTester tester, {VoidCallback? onTalk}) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MomentsInsightsTab(moments: moments, onManage: () {}, onTalk: onTalk),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with none yet: an inviting sky, ways to begin, and an honest account of what Sol does', (tester) async {
    await pump(tester, onTalk: () {});

    expect(find.text('Your first star is waiting'), findsOneWidget);
    expect(find.byKey(const ValueKey('moment-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('moment-talk')), findsOneWidget);
    expect(find.text('Good moments will gather here'), findsOneWidget);
    for (final starter in momentStarters) {
      expect(find.byKey(ValueKey('moment-starter-$starter')), findsOneWidget);
    }
    expect(find.textContaining('Only if you allow it'), findsOneWidget);
  });

  testWidgets('every kept moment is a star in the sky, and the count says so', (tester) async {
    await tester.runAsync(() async {
      await moments.addManual('A good walk by the river.');
      await moments.addManual('Mum called and we laughed.');
      await moments.addManual('The first warm day.');
    });
    await pump(tester);

    expect(find.text('3 moments kept'), findsOneWidget);
    expect(find.text('Your first star is waiting'), findsNothing);
  });

  testWidgets('one moment is kept in the singular', (tester) async {
    await tester.runAsync(() => moments.addManual('A good walk by the river.'));
    await pump(tester);

    expect(find.text('One moment kept'), findsOneWidget);
  });

  testWidgets('talking about one is offered only when there is a chat to open, and opens it', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('moment-talk')), findsNothing);

    var opened = 0;
    await pump(tester, onTalk: () => opened++);
    await tester.tap(find.byKey(const ValueKey('moment-talk')));
    expect(opened, 1);
  });

  testWidgets('adding one yourself: write it, keep it, and it is kept at once', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('moment-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('moment-sheet')), findsOneWidget);

    // Nothing to keep until something is written.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('moment-keep'))).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('moment-field')), 'My sister sent me a photo of the baby.');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('moment-keep')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final kept = moments.confirmed.single;
    expect(kept.text, 'My sister sent me a photo of the baby.');
    expect(kept.source, MomentSource.manual);
    expect(kept.state, MomentState.confirmed);
    expect(find.text('My sister sent me a photo of the baby.'), findsOneWidget);
    expect(find.text('One moment kept'), findsOneWidget);
  });

  testWidgets('a starter begins the sentence for you', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(ValueKey('moment-starter-${momentStarters.first}')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const ValueKey('moment-field')));
    expect(field.controller!.text, '${momentStarters.first} ');
  });

  testWidgets('the whole tab fits when the text is enlarged', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => moments.addManual('A good walk by the river.'));
    await pump(tester, onTalk: () {});

    expect(tester.takeException(), isNull);
  });
}
