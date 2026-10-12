import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/features/app_shell/app_shell.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  testWidgets('the shell shows the chat history of the controller it is handed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final at = DateTime.now().subtract(const Duration(minutes: 30));
    final conversation = ChatConversationRecord(
      id: 'c1',
      title: 'Earlier',
      createdAt: at,
      updatedAt: at,
      messages: [
        ChatMessageRecord(
          id: 'm1',
          isUser: true,
          text: 'A distinctive line from the shared history',
          timestamp: at,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'solace_chat_conversations_v2': jsonEncode([conversation.toMap()]),
    });
    final preferences = await SharedPreferences.getInstance();
    final chat = ChatController(preferences: preferences);
    await chat.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          sessionController: SessionController(
            repository: InMemorySessionRepository(),
            emotionAnalyzer: const MockEmotionAnalyzer(),
          ),
          safetyController: SafetyController(
            screener: const KeywordSafetyScreener(),
            repository: InMemorySafetyEventRepository(),
          ),
          profileController: ProfileController(
            repository: InMemoryProfileRepository(),
          ),
          suggestionController: SuggestionController(
            libraryRepository: AssetActivityLibraryRepository(),
            suggestionRepository: InMemorySuggestionRepository(),
          ),
          chatController: chat,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The rail no longer prints whole messages: the last-chat tile shows the
    // thread's date and carries the line itself as its label for readers.
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        RegExp('A distinctive line from the shared history'),
      ),
      findsOneWidget,
    );
    handle.dispose();

    expect(find.text('LAST CHAT'), findsOneWidget);
    expect(find.text(conversation.dateStr), findsOneWidget);
    // The shell was handed this controller, so it must not have disposed or
    // replaced it: it still holds the conversation it loaded.
    expect(chat.conversations, hasLength(1));
  });
}
