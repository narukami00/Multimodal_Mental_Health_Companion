import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/domain/memory/moment_extractor.dart';
import 'package:solace_mobile/features/memory/moment_proposal_card.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';

const _warm = 'I had coffee with a friend and it was really nice.';

void main() {
  late MomentsController controller;
  var suppressed = false;
  var stopped = false;

  setUp(() async {
    suppressed = false;
    stopped = false;
    controller = MomentsController(repository: InMemoryMomentRepository());
    await controller.load();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MomentProposalCard(
              controller: controller,
              suppressed: () => suppressed,
              onStopAsking: () => stopped = true,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> propose(WidgetTester tester) async {
    await tester.runAsync(
      () => controller.consider(
        MomentCandidate(
          text: _warm,
          source: MomentSource.journal,
          createdAt: DateTime(2026, 10, 20),
          sourceRef: 'r1',
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows nothing when nothing is waiting', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('moment-proposal')), findsNothing);
  });

  testWidgets('asks with their exact words, and keeps nothing yet', (tester) async {
    await pump(tester);
    await propose(tester);

    expect(find.text('Want me to remember this?'), findsOneWidget);
    expect(find.text('“$_warm”'), findsOneWidget);
    expect(controller.confirmed, isEmpty);
  });

  testWidgets('yes keeps it and the card goes away', (tester) async {
    await pump(tester);
    await propose(tester);

    await tester.tap(find.byKey(const ValueKey('moment-yes')));
    await tester.pump();

    expect(controller.confirmed.single.text, _warm);
    expect(find.byKey(const ValueKey('moment-proposal')), findsNothing);
  });

  testWidgets('not this deletes it', (tester) async {
    await pump(tester);
    await propose(tester);

    await tester.tap(find.byKey(const ValueKey('moment-no')));
    await tester.pump();

    expect(controller.all, isEmpty);
    expect(find.byKey(const ValueKey('moment-proposal')), findsNothing);
  });

  testWidgets('they can change the words before keeping it', (tester) async {
    await pump(tester);
    await propose(tester);

    await tester.tap(find.byKey(const ValueKey('moment-edit')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('moment-edit-field')),
      'Coffee with Sam was lovely.',
    );
    await tester.tap(find.byKey(const ValueKey('moment-yes')));
    await tester.pump();

    expect(controller.confirmed.single.text, 'Coffee with Sam was lovely.');
    expect(controller.confirmed.single.editedByUser, isTrue);
  });

  testWidgets('is not shown while suppressed, but the moment still waits', (tester) async {
    suppressed = true;
    await pump(tester);
    await propose(tester);

    expect(find.byKey(const ValueKey('moment-proposal')), findsNothing);
    expect(controller.pending, hasLength(1));
  });

  testWidgets('can be turned off from the card itself', (tester) async {
    await pump(tester);
    await propose(tester);

    await tester.tap(find.byKey(const ValueKey('moment-stop')));
    expect(stopped, isTrue);
  });
}
