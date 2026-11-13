import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/chat/chat_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  late SafetyController safety;
  late ChatController chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    safety = SafetyController(
      screener: const KeywordSafetyScreener(),
      repository: InMemorySafetyEventRepository(),
    );
    chat = ChatController(preferences: await SharedPreferences.getInstance());
    await chat.load();

    await chat.addMessage(
      ChatMessageRecord(
        id: 'u1',
        text: 'Breathing exercises helped calm my chest',
        isUser: true,
        timestamp: DateTime(2026, 11, 10, 9),
      ),
    );
    await chat.addMessage(
      ChatMessageRecord(
        id: 'a1',
        text: 'Glad that helped you settle.',
        isUser: false,
        timestamp: DateTime(2026, 11, 10, 9, 1),
      ),
    );

    chat.startNewConversation();
    await chat.addMessage(
      ChatMessageRecord(
        id: 'u2',
        text: 'Went for a morning walk in the park',
        isUser: true,
        timestamp: DateTime(2026, 11, 11, 8),
      ),
    );
  });

  Future<void> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          safetyController: safety,
          chatController: chat,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
      'header stays minimal and right side panel hosts search, threads, breakdown, and server',
      (tester) async {
    await pumpChat(tester);

    expect(find.byKey(const ValueKey('chat-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-side-panel-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-side-panel')), findsNothing);
    expect(find.byKey(const ValueKey('chat-breakdown')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-side-panel-btn')));
    for (var i = 0; i < 8; i++) { await tester.pump(const Duration(milliseconds: 60)); }

    expect(find.byKey(const ValueKey('chat-side-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('side-panel-new-chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-breakdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-server-settings')), findsOneWidget);

    final firstThreadId = chat.conversations.last.id;
    final secondThreadId = chat.conversations.first.id;
    expect(find.byKey(ValueKey('history-thread-$firstThreadId')), findsOneWidget);
    expect(find.byKey(ValueKey('history-thread-$secondThreadId')), findsOneWidget);

    // Search keeps full drawer height even with 1 matching thread.
    await tester.enterText(
      find.byKey(const ValueKey('history-search-field')),
      'Breathing',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(ValueKey('history-thread-$firstThreadId')), findsOneWidget);
    expect(find.byKey(ValueKey('history-thread-$secondThreadId')), findsNothing);

    final panelHeight =
        tester.getSize(find.byKey(const ValueKey('chat-side-panel'))).height;
    final scaffoldHeight = tester.getSize(find.byType(Scaffold)).height;
    expect(panelHeight, equals(scaffoldHeight));

    // Selecting the matching thread switches to it and closes the panel.
    await tester.tap(find.byKey(ValueKey('history-thread-$firstThreadId')));
    for (var i = 0; i < 8; i++) { await tester.pump(const Duration(milliseconds: 60)); }

    expect(chat.activeConversation?.id, equals(firstThreadId));
    expect(find.byKey(const ValueKey('chat-side-panel')), findsNothing);
    expect(
      find.text('Breathing exercises helped calm my chest'),
      findsOneWidget,
    );
  });

  testWidgets('side panel starts a new conversation cleanly', (tester) async {
    await pumpChat(tester);
    final previousId = chat.activeConversation?.id;

    await tester.tap(find.byKey(const ValueKey('chat-side-panel-btn')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.byKey(const ValueKey('side-panel-new-chat')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(chat.activeConversation?.id, isNot(equals(previousId)));
    expect(chat.activeConversation?.hasUserMessage, isFalse);
    expect(find.byKey(const ValueKey('chat-side-panel')), findsNothing);
    expect(find.text('What’s on your mind?'), findsOneWidget);
  });
}
