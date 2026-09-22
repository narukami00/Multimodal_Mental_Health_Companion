import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/chat/chat_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/safety/support_resources_page.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  SafetyController safety() => SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );

  Future<void> pumpChat(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ChatPage(safetyController: safety())),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Breathing orb animates forever — pumpAndSettle would hang.
  Future<void> pumpSettle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('greets and replies to a clear message', (tester) async {
    await pumpChat(tester);

    expect(find.text('Sol'), findsOneWidget);
    expect(find.textContaining("you don't have to carry it"), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Feeling a bit anxious');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await pumpSettle(tester);

    expect(find.text('Feeling a bit anxious'), findsOneWidget);
    expect(find.textContaining('I hear you'), findsOneWidget);
    expect(find.byType(SupportResourcesPage), findsNothing);
  });

  testWidgets('chips send their suggestion', (tester) async {
    await pumpChat(tester);

    final chip = find.widgetWithText(ActionChip, "I'm feeling a bit restless");
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await pumpSettle(tester);

    expect(find.text("I'm feeling a bit restless"), findsWidgets);
    expect(find.textContaining('I hear you'), findsOneWidget);
  });

  testWidgets('urgent text opens support resources', (tester) async {
    await pumpChat(tester);

    await tester.enterText(
      find.byType(TextField),
      'I want to die and need help.',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await pumpSettle(tester);

    expect(find.byType(SupportResourcesPage), findsOneWidget);
  });
}
