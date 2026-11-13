import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/domain/chat/conversation_search.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/chat/conversation_history.dart';

void main() {
  group('conversation_search', () {
    test('splitHighlightSegments splits case-insensitive overlapping terms', () {
      final segments = splitHighlightSegments(
        'Deadline stress made me lose sleep before the exam.',
        'sleep exam',
      );
      final highlighted = segments
          .where((s) => s.highlighted)
          .map((s) => s.text)
          .toList();
      expect(highlighted, ['sleep', 'exam']);
      expect(segments.map((s) => s.text).join(), contains('Deadline stress'));
    });

    test('matchConversationRecord searches title, summary, text, and transcripts', () {
      final record = ChatConversationRecord(
        id: 'conv_1',
        title: 'Late evening check-in',
        createdAt: DateTime(2026, 10, 1, 21),
        updatedAt: DateTime(2026, 10, 1, 21, 15),
        summary: 'Talked through upcoming midterm anxiety.',
        messages: [
          ChatMessageRecord(
            id: 'm1',
            isUser: true,
            text: '',
            isVoice: true,
            transcription: 'I keep worrying about the algorithms presentation.',
            timestamp: DateTime(2026, 10, 1, 21, 5),
          ),
          ChatMessageRecord(
            id: 'm2',
            isUser: false,
            text: 'Preparing one slide at a time might ease that presentation tension.',
            timestamp: DateTime(2026, 10, 1, 21, 10),
          ),
        ],
      );

      final hit = matchConversationRecord(record, 'presentation');
      expect(hit, isNotNull);
      expect(hit!.matchCount, 2);
      expect(hit.matchedMessageId, 'm2');
      expect(hit.matchedExcerpt, contains('presentation'));

      final multiTermHit = matchConversationRecord(record, 'midterm presentation');
      expect(multiTermHit, isNotNull);
      expect(multiTermHit!.summaryMatched, isTrue);

      expect(matchConversationRecord(record, 'vacation'), isNull);
    });
  });

  group('ConversationHistorySheet search UI', () {
    testWidgets('search icon filters threads, highlights keywords, and stores query on select', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ChatController();
      await controller.load();

      await controller.addMessage(
        ChatMessageRecord(
          id: 'u1',
          isUser: true,
          text: 'Feeling overwhelmed by my thesis deadline tonight.',
          timestamp: DateTime(2026, 10, 2, 22),
        ),
      );
      controller.startNewConversation();
      await controller.addMessage(
        ChatMessageRecord(
          id: 'u2',
          isUser: true,
          text: 'Had a calm walk in the morning sun.',
          timestamp: DateTime(2026, 10, 3, 9),
        ),
      );

      ConversationThread? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ConversationHistorySheet.show(
                  context,
                  chatController: controller,
                  onSelectThread: (t) => selected = t,
                  onNewConversation: () {},
                ),
                child: const Text('History'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('history-search-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-search-field')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('history-search-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('history-search-field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('history-search-field')),
        'thesis',
      );
      await tester.pumpAndSettle();

      expect(find.text('1 conversation matches "thesis"'), findsOneWidget);
      expect(find.textContaining('2 hits'), findsOneWidget);
      expect(find.text('Had a calm walk in the morning sun.'), findsNothing);

      final thesisConvId = controller.conversations
          .firstWhere((c) => c.messages.any((m) => m.text.contains('thesis')))
          .id;
      await tester.tap(find.byKey(ValueKey('history-thread-$thesisConvId')));
      await tester.pumpAndSettle();

      expect(selected?.id, thesisConvId);
      expect(controller.highlightQuery, 'thesis');
    });
  });
}
