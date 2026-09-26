import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  var testCounter = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    testCounter++;
  });

  ChatController makeController([String? keySuffix]) {
    final s = keySuffix ?? '$testCounter';
    return ChatController(
      preferences: prefs,
      storageKey: 'test_chat_conv_$s',
      activeIdKey: 'test_chat_active_$s',
    );
  }

  group('ChatController Lifecycle & Persistence', () {
    test('load seeds first clean conversation if storage is empty without counting in history', () async {
      final controller = makeController();
      expect(controller.isLoaded, isFalse);
      expect(controller.conversations, isEmpty);
      expect(controller.hasHistory, isFalse);

      await controller.load();

      expect(controller.isLoaded, isTrue);
      // History is empty until the user actually sends a message
      expect(controller.conversations, isEmpty);
      expect(controller.hasHistory, isFalse);

      final active = controller.activeConversation;
      expect(active, isNotNull);
      expect(active!.title, 'Holding space today');
      expect(active.messages.length, 1);
      expect(active.messages.first.isUser, isFalse);
      expect(active.messages.first.text, contains("you don't have to carry it"));
    });

    test('conversations only count in history when user has messaged', () async {
      final controller = makeController();
      await controller.load();

      expect(controller.conversations, isEmpty);
      expect(controller.hasHistory, isFalse);

      // User sends a message -> becomes a real conversation
      await controller.addMessage(ChatMessageRecord(
        id: 'msg_1',
        isUser: true,
        text: 'Hello Sol, checking in',
        timestamp: DateTime.now(),
      ));

      expect(controller.conversations.length, 1);
      expect(controller.hasHistory, isTrue);

      // Starting a new conversation before messaging in it does not increase history count
      final newConv = controller.startNewConversation();
      expect(controller.activeConversation?.id, newConv.id);
      expect(controller.conversations.length, 1);

      // Pruning empty conversations discards the untouched draft
      controller.pruneEmptyConversations();
      expect(controller.conversations.length, 1);
    });

    test('addMessage appends text message and updates conversation title', () async {
      final controller = makeController();
      await controller.load();

      final userMsg = ChatMessageRecord(
        id: 'msg_1',
        isUser: true,
        text: 'Feeling overwhelmed by work today',
        timestamp: DateTime.now(),
      );

      await controller.addMessage(userMsg);

      final active = controller.activeConversation!;
      expect(active.messages.length, 2);
      expect(active.messages.last.text, 'Feeling overwhelmed by work today');
      expect(active.title, 'Feeling overwhelmed by work today');
    });

    test('addMessage with voice reflection preserves waveform and duration', () async {
      final controller = makeController();
      await controller.load();

      final voiceMsg = ChatMessageRecord(
        id: 'voice_1',
        isUser: true,
        text: 'Audio reflection',
        timestamp: DateTime.now(),
        isVoice: true,
        voiceDuration: '0:18',
        localAudioPath: '/tmp/test.wav',
        waveform: const [0.2, 0.5, 0.8, 0.3],
        turnId: 'turn_abc',
      );

      await controller.addMessage(voiceMsg);

      final active = controller.activeConversation!;
      expect(active.messages.length, 2);
      expect(active.hasVoice, isTrue);
      expect(active.messages.last.isVoice, isTrue);
      expect(active.messages.last.voiceDuration, '0:18');
      expect(active.messages.last.localAudioPath, '/tmp/test.wav');
      expect(active.messages.last.waveform, const [0.2, 0.5, 0.8, 0.3]);
    });

    test('updateMessage updates transcription and derives intelligent title', () async {
      final controller = makeController();
      await controller.load();

      final voiceMsg = ChatMessageRecord(
        id: 'voice_1',
        isUser: true,
        text: 'Audio reflection',
        timestamp: DateTime.now(),
        isVoice: true,
        voiceDuration: '0:12',
      );

      await controller.addMessage(voiceMsg);

      final updatedVoiceMsg = voiceMsg.copyWith(
        transcription: 'I went for a long quiet walk to calm down',
      );

      await controller.updateMessage('voice_1', updatedVoiceMsg);

      final active = controller.activeConversation!;
      expect(active.messages.last.transcription,
          'I went for a long quiet walk to calm down');
      expect(active.title, contains('I went for a long'));
    });

    test('switchConversation and deleteConversation manage thread collection', () async {
      final controller = makeController();
      await controller.load();

      await controller.addMessage(ChatMessageRecord(
        id: 'msg_c1',
        isUser: true,
        text: 'Thread 1 conversation',
        timestamp: DateTime.now(),
      ));
      final conv1 = controller.activeConversation!;

      final conv2 = controller.startNewConversation();
      await controller.addMessage(ChatMessageRecord(
        id: 'msg_c2',
        isUser: true,
        text: 'Thread 2 conversation',
        timestamp: DateTime.now(),
      ));

      expect(controller.conversations.length, 2);
      expect(controller.activeConversation?.id, conv2.id);

      controller.switchConversation(conv1.id);
      expect(controller.activeConversation?.id, conv1.id);

      await controller.deleteConversation(conv2.id);
      expect(controller.conversations.length, 1);
      expect(controller.activeConversation?.id, conv1.id);
    });

    test('persists and reloads from SharedPreferences cleanly', () async {
      final key = 'persist_test';
      final controller1 = makeController(key);
      await controller1.load();

      final userMsg = ChatMessageRecord(
        id: 'msg_p1',
        isUser: true,
        text: 'Saving persistent reflection test',
        timestamp: DateTime.now(),
      );
      await controller1.addMessage(userMsg);

      // Create a fresh controller with same storage key
      final controller2 = makeController(key);
      await controller2.load();

      expect(controller2.conversations.length, 1);
      final reloaded = controller2.activeConversation!;
      expect(reloaded.messages.length, 2);
      expect(reloaded.messages.last.text, 'Saving persistent reflection test');
    });
  });
}
