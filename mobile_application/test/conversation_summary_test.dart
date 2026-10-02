import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/domain/chat/conversation_summary.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';

ChatMessageRecord _m(int i, {bool user = true, String? text, bool voice = false, String? spoken}) =>
    ChatMessageRecord(
      id: 'm$i',
      isUser: user,
      text: text ?? 'message $i',
      timestamp: DateTime(2026, 10, 20, 12, i),
      isVoice: voice,
      transcription: spoken,
    );

ChatConversationRecord _conversation(
  int count, {
  String? summary,
  String? through,
}) => ChatConversationRecord(
  id: 'c1',
  title: 'Talk',
  createdAt: DateTime(2026, 10, 20),
  updatedAt: DateTime(2026, 10, 20),
  messages: [for (var i = 0; i < count; i++) _m(i, user: i.isEven)],
  summary: summary,
  summarizedThroughId: through,
);

void main() {
  group('when a summary is due', () {
    test('not while the conversation is short', () {
      expect(planSummary(_conversation(12)), isNull);
    });

    test('once more than twelve have piled up, all but the newest eight', () {
      final plan = planSummary(_conversation(14))!;

      expect(plan.toSummarize.length, 6);
      expect(plan.toSummarize.first.id, 'm0');
      expect(plan.throughId, 'm5');
    });

    test('counts only what came after the last summary', () {
      // Summary covers up to m5; messages m6..m18 are new (13 of them).
      final conversation = _conversation(19, summary: 'Earlier.', through: 'm5');
      final plan = planSummary(conversation)!;

      expect(plan.toSummarize.first.id, 'm6');
      expect(plan.throughId, 'm10');

      expect(planSummary(_conversation(18, summary: 'Earlier.', through: 'm5')), isNull);
    });

    test('an unknown through-id means nothing is covered yet', () {
      final plan = planSummary(_conversation(14, summary: 'x', through: 'gone'))!;
      expect(plan.toSummarize.first.id, 'm0');
    });

    test('empty messages do not count', () {
      final conversation = ChatConversationRecord(
        id: 'c',
        title: 't',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        messages: [for (var i = 0; i < 20; i++) _m(i, text: i.isEven ? '' : 'hi $i')],
      );
      expect(unsummarized(conversation).length, 10);
      expect(planSummary(conversation), isNull);
    });
  });

  group('what the server is sent', () {
    test('turns carry a role and what was said, voice by its transcription', () {
      final turns = turnsOf([
        _m(0, text: 'hello'),
        _m(1, user: false, text: 'hi there'),
        _m(2, voice: true, text: '', spoken: 'spoken words'),
        _m(3, text: '  '),
      ]);
      expect(turns, [
        {'role': 'user', 'content': 'hello'},
        {'role': 'assistant', 'content': 'hi there'},
        {'role': 'user', 'content': 'spoken words'},
      ]);
    });

    test('a resumed conversation brings its summary and the last ten turns', () {
      final block = resumeBlock(_conversation(25, summary: 'The user felt tired.'))!;

      expect(block['summary'], 'The user felt tired.');
      final recent = block['recent']! as List;
      expect(recent.length, 10);
      expect((recent.last as Map)['content'], 'message 24');
    });

    test('a greeting nobody answered is not resumed', () {
      final onlyGreeting = ChatConversationRecord(
        id: 'c',
        title: 't',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        messages: [_m(0, user: false, text: 'Hello. Take your time here.')],
      );
      expect(resumeBlock(onlyGreeting), isNull);
      expect(resumeBlock(null), isNull);
    });

    test('the configure message carries it only when there is one', () {
      final without = CompanionWebSocketService.buildSessionConfigurePayload(
        sessionId: 's',
        mode: 'chat_voice_playback',
      );
      expect(without.containsKey('resume'), isFalse);

      final withResume = CompanionWebSocketService.buildSessionConfigurePayload(
        sessionId: 's',
        mode: 'chat_voice_playback',
        resume: {'summary': 'x'},
      );
      expect(withResume['resume'], {'summary': 'x'});
    });
  });

  group('storing it', () {
    late ChatController chat;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      chat = ChatController(preferences: await SharedPreferences.getInstance());
      await chat.load();
      for (var i = 0; i < 6; i++) {
        await chat.addMessage(_m(i, user: i.isEven));
      }
    });

    test('a summary is kept with the message it covers up to', () async {
      final id = chat.activeConversation!.id;
      await chat.setSummary(id, 'The user felt tired.', 'm3');

      final c = chat.activeConversation!;
      expect(c.summary, 'The user felt tired.');
      expect(c.summarizedThroughId, 'm3');
    });

    test('survives a restart', () async {
      final id = chat.activeConversation!.id;
      await chat.setSummary(id, 'The user felt tired.', 'm3');

      final reopened = ChatController(preferences: await SharedPreferences.getInstance());
      await reopened.load();
      expect(reopened.conversations.firstWhere((c) => c.id == id).summary, 'The user felt tired.');
    });

    test('a late, older answer never rolls a newer summary back', () async {
      final id = chat.activeConversation!.id;
      await chat.setSummary(id, 'Newer.', 'm4');
      await chat.setSummary(id, 'Older.', 'm2');

      expect(chat.activeConversation!.summary, 'Newer.');
    });

    test('ignores an unknown conversation, an unknown message, and empty text', () async {
      final id = chat.activeConversation!.id;
      await chat.setSummary('nope', 'x', 'm3');
      await chat.setSummary(id, 'x', 'unknown');
      await chat.setSummary(id, '   ', 'm3');

      expect(chat.activeConversation!.hasSummary, isFalse);
    });

    test('forgetting it leaves the messages', () async {
      final id = chat.activeConversation!.id;
      await chat.setSummary(id, 'The user felt tired.', 'm3');
      final before = chat.activeConversation!.messages.length;

      await chat.clearSummary(id);

      expect(chat.activeConversation!.hasSummary, isFalse);
      expect(chat.activeConversation!.summarizedThroughId, isNull);
      expect(chat.activeConversation!.messages.length, before);
    });

    test('deleting the conversation deletes its summary with it', () async {
      final id = chat.activeConversation!.id;
      await chat.setSummary(id, 'The user felt tired.', 'm3');
      await chat.deleteConversation(id);

      expect(chat.conversations.where((c) => c.id == id), isEmpty);
    });
  });
}
