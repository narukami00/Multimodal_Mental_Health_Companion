import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/domain/memory/moment_extractor.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';

ChatMessageRecord _message(String id, String text) => ChatMessageRecord(
  id: id,
  isUser: true,
  text: text,
  timestamp: DateTime(2026, 10, 20, 12),
);

void main() {
  test('deleting a conversation reports the messages it held, once it is gone', () async {
    SharedPreferences.setMockInitialValues({});
    final chat = ChatController(preferences: await SharedPreferences.getInstance());
    await chat.load();

    List<String>? reported;
    chat.onConversationDeleted = (ids) => reported = ids;

    await chat.addMessage(_message('m1', 'I had coffee with a friend and it was nice.'));
    await chat.addMessage(_message('m2', 'Then we walked by the river.'));
    final id = chat.activeConversation!.id;

    await chat.deleteConversation(id);

    expect(reported, containsAll(['m1', 'm2']));
    expect(chat.conversations.any((c) => c.id == id), isFalse);
  });

  test('an empty conversation reports nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final chat = ChatController(preferences: await SharedPreferences.getInstance());
    await chat.load();

    var called = false;
    chat.onConversationDeleted = (_) => called = true;
    await chat.deleteConversation(chat.activeConversation!.id);

    expect(called, isFalse);
  });

  test('deleting by source removes those moments and only those', () async {
    final moments = MomentsController(repository: InMemoryMomentRepository());
    await moments.load();

    Future<MemoryMoment> add(String text, String ref) async {
      final moment = (await moments.consider(
        MomentCandidate(
          text: text,
          source: MomentSource.chat,
          createdAt: DateTime(2026, 10, 20),
          sourceRef: ref,
        ),
      ))!;
      await moments.confirm(moment.id);
      return moment;
    }

    await add('I had coffee with a friend and it was really nice.', 'chat:m1');
    await add('We went for a walk by the river and I felt calmer.', 'chat:m2');
    await add('I cooked dinner for my family and it was so good.', 'chat:m9');

    await moments.deleteForSources(['chat:m1', 'chat:m2', 'chat:unknown']);

    expect(moments.all.map((m) => m.sourceRef), ['chat:m9']);
  });
}
