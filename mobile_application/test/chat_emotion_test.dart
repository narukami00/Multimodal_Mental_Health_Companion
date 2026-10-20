import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/chat_conversation_record.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/domain/chat/conversation_breakdown.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/chat/chat_message_reader.dart';
import 'package:solace_mobile/features/chat/chat_page.dart';
import 'package:solace_mobile/features/chat/conversation_breakdown_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/journal_analysis_client.dart';

EmotionResult reading({
  String? mood = 'low or tired',
  String tier = 'clear',
  double neg = 0.7,
  double pos = 0.1,
  double low = 0.6,
  double high = 0.1,
  String pattern = 'T',
  bool inContext = false,
  Map<String, double>? face,
}) =>
    EmotionResult(
      faceClasses: face,
      sessionId: 's',
      modality: EmotionModality.text,
      timestamp: DateTime(2026, 1, 1),
      modelVersion: 'test',
      origin: EmotionOrigin.chat,
      mood: mood,
      tier: tier,
      pattern: pattern,
      valenceProbs: {'negative': neg, 'neutral': 1 - neg - pos, 'positive': pos},
      arousalProbs: {'low': low, 'mid': 1 - low - high, 'high': high},
      classes: const {'sad': 0.5, 'neutral': 0.5},
      inContext: inContext,
    );

ChatMessageRecord userMsg(String id, String text, {EmotionResult? r, DateTime? at}) => ChatMessageRecord(
      id: id,
      isUser: true,
      text: text,
      timestamp: at ?? DateTime.now(),
      reading: r,
    );

ChatMessageRecord solMsg(String id, String text) =>
    ChatMessageRecord(id: id, isUser: false, text: text, timestamp: DateTime.now());

ChatConversationRecord conversation(List<ChatMessageRecord> messages, {String? summary}) => ChatConversationRecord(
      id: 'c1',
      title: 'A long week',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: messages,
      summary: summary,
    );

Future<ChatController> controllerWith(List<ChatMessageRecord> messages, {String? summary}) async {
  SharedPreferences.setMockInitialValues({
    'solace_chat_conversations_v2': jsonEncode([conversation(messages, summary: summary).toMap()]),
    'solace_active_chat_id_v2': 'c1',
  });
  final c = ChatController();
  await c.load();
  return c;
}

void main() {
  group('the face on its own', () {
    test('is read from the server update, kept when saved, and absent when there was no camera', () {
      final withFace = JournalAnalysis(transcript: '', emotion: {
        'pattern': 'ATV',
        'estimate': {
          'l7': {'happy': 0.5, 'neutral': 0.5},
          'lv': {'negative': 0.1, 'neutral': 0.4, 'positive': 0.5},
        },
        'face': {
          'l7': {'sad': 0.7, 'neutral': 0.3},
        },
      }).toResults(sessionId: 't').single;
      expect(withFace.faceClasses, {'sad': 0.7, 'neutral': 0.3});
      expect(withFace.classes!['happy'], 0.5); // the blended reading is untouched
      expect(EmotionResult.fromMap(withFace.toMap()).faceClasses, {'sad': 0.7, 'neutral': 0.3});

      final without = JournalAnalysis(transcript: '', emotion: {
        'pattern': 'AT',
        'estimate': {
          'l7': {'happy': 1.0},
        },
      }).toResults(sessionId: 't').single;
      expect(without.faceClasses, isNull);
      expect(without.toMap().containsKey('faceClasses'), isFalse);
    });
  });

  group('a message and its reading', () {
    test('survive saving and loading, and older messages without one still load', () {
      final m = userMsg('a', 'Too tired to talk', r: reading(inContext: true));
      final back = ChatMessageRecord.fromJson(m.toJson());
      expect(back.reading?.mood, 'low or tired');
      expect(back.reading?.inContext, isTrue);
      expect(back.reading?.valenceProbs?['negative'], 0.7);

      final old = ChatMessageRecord.fromMap({'id': 'x', 'isUser': true, 'text': 'hi', 'timestamp': '2026-01-01T00:00:00'});
      expect(old.reading, isNull);
    });

    test('a voice message counts its transcription as what was said', () {
      final v = ChatMessageRecord(
          id: 'v', isUser: true, text: 'Audio reflection', timestamp: DateTime.now(), isVoice: true, transcription: ' I am fine ');
      expect(v.spokenText, 'I am fine');
    });
  });

  group('the controller', () {
    test('keeps a reading through a later update of the same message', () async {
      final c = await controllerWith([solMsg('g', 'Hello'), userMsg('u1', 'hello there')]);
      await c.setReading('u1', reading());
      await c.updateMessage('u1', userMsg('u1', 'hello there')); // e.g. an audio path arrives; carries no reading
      final stored = c.conversationById('c1')!.messages.last;
      expect(stored.reading?.mood, 'low or tired');
    });

    test('a live reading goes to the newest message of the person without one', () async {
      final c = await controllerWith(
          [userMsg('u1', 'first', r: reading(mood: 'upbeat')), solMsg('s1', 'ok'), userMsg('u2', 'second')]);
      expect(await c.attachToLatestUserMessage(reading()), isTrue);
      expect(c.conversationById('c1')!.messages.last.reading?.mood, 'low or tired');
      // nothing left without a reading: a stray one is dropped
      expect(await c.attachToLatestUserMessage(reading(mood: 'upbeat')), isFalse);
    });

    test('a reading that arrives before the message is saved waits and is given to it', () async {
      final c = await controllerWith([solMsg('g', 'Hello')]);
      expect(await c.attachToLatestUserMessage(reading(mood: 'tense or upset', pattern: 'ATV')), isFalse);
      await c.addMessage(userMsg('call1', 'spoken in a call'));
      final stored = c.activeConversation!.messages.last;
      expect(stored.reading?.pattern, 'ATV');
      expect(stored.reading?.mood, 'tense or upset');
    });

    test('a stale reading is not attached to an old message', () async {
      final old = DateTime.now().subtract(const Duration(minutes: 30));
      final c = await controllerWith([userMsg('u1', 'long ago', at: old)]);
      expect(await c.attachToLatestUserMessage(reading()), isFalse);
    });

    test('reads earlier messages one by one and stops when the server goes away', () async {
      final c = await controllerWith([userMsg('u1', 'one'), solMsg('s', 'x'), userMsg('u2', 'two'), userMsg('u3', 'three')]);
      var calls = 0;
      c.messageReader = (m, before) async => ++calls == 3 ? null : reading();
      expect(c.unreadMessages('c1'), hasLength(3));
      final done = await c.readUnreadMessages('c1');
      expect(done, 2);
      expect(c.unreadMessages('c1').map((m) => m.id), ['u3']);
    });

    test('without a reader nothing is read', () async {
      final c = await controllerWith([userMsg('u1', 'one')]);
      expect(c.canReadMessages, isFalse);
      expect(await c.readMessage('c1', 'u1'), isNull);
    });
  });

  group('the message reader', () {
    JournalAnalysisClient client(List<Map<String, dynamic>> sent, {bool reachable = true}) => JournalAnalysisClient(
          baseUri: () async => reachable ? Uri.parse('http://x:8000') : null,
          transport: ({required method, required uri, required headers, required body, required timeout}) async {
            sent.add({'path': uri.path, 'body': body.length < 4000 ? utf8.decode(body) : ''});
            return (
              status: 200,
              body: jsonEncode({
                'transcript': 't',
                'safety': null,
                'emotion': {
                  'pattern': 'T',
                  'mood': 'low or tired',
                  'tier': 'hint',
                  'estimate': {
                    'l7': {'sad': 0.6, 'neutral': 0.4},
                    'lv': {'negative': 0.6, 'neutral': 0.3, 'positive': 0.1},
                    'la': {'low': 0.5, 'mid': 0.4, 'high': 0.1},
                  },
                },
              }),
            );
          },
        );

    test('reads a short message together with the person\'s last messages', () async {
      final sent = <Map<String, dynamic>>[];
      final now = DateTime.now();
      final before = [
        userMsg('a', 'I have not slept properly all week', at: now.subtract(const Duration(minutes: 3))),
        solMsg('s', 'That sounds draining.'),
        userMsg('b', 'work keeps piling up', at: now.subtract(const Duration(minutes: 2))),
      ];
      final reader = ChatMessageReader(client: client(sent), consentGranted: () => true);
      final r = await reader(userMsg('c', 'yeah I guess', at: now), before);
      final text = jsonDecode(sent.single['body'] as String)['text'] as String;
      expect(text, 'I have not slept properly all week work keeps piling up yeah I guess'); // Sol's line is not part of it
      expect(r?.inContext, isTrue);
      expect(r?.origin, EmotionOrigin.chat);
    });

    test('reads a longer message as it stands', () async {
      final sent = <Map<String, dynamic>>[];
      final reader = ChatMessageReader(client: client(sent), consentGranted: () => true);
      final r = await reader(
          userMsg('c', 'I really do not know how to carry on like this'), [userMsg('a', 'earlier words')]);
      expect(jsonDecode(sent.single['body'] as String)['text'], 'I really do not know how to carry on like this');
      expect(r?.inContext, isFalse);
    });

    test('does nothing without the person\'s OK, and never invents a reading when the server is away', () async {
      final sent = <Map<String, dynamic>>[];
      expect(
          await ChatMessageReader(client: client(sent), consentGranted: () => false)(userMsg('c', 'hello there friend'), []),
          isNull);
      expect(sent, isEmpty);
      expect(
          await ChatMessageReader(client: client(sent, reachable: false), consentGranted: () => true)(
              userMsg('c', 'hello there friend'), []),
          isNull);
    });

    test('a voice message with a recording is read from the recording', () async {
      final sent = <Map<String, dynamic>>[];
      final reader = ChatMessageReader(
        client: client(sent),
        consentGranted: () => true,
        readFile: (path) async => Uint8List(32000),
      );
      final voice = ChatMessageRecord(
          id: 'v',
          isUser: true,
          text: 'Audio reflection',
          timestamp: DateTime.now(),
          isVoice: true,
          transcription: 'I am ok',
          localAudioPath: '/x.wav');
      await reader(voice, []);
      expect(sent.single['path'], '/v1/journal/audio');
    });
  });

  group('the breakdown', () {
    test('counts moods, finds the biggest shifts and says nothing it cannot back up', () {
      final conv = conversation([
        solMsg('g', 'Hello'),
        userMsg('1', 'Today was fine, work went well', r: reading(mood: 'upbeat', neg: 0.05, pos: 0.8, low: 0.1, high: 0.3)),
        userMsg('2', 'Then my manager called me in', r: reading(mood: 'tense or upset', neg: 0.8, pos: 0.05, low: 0.2, high: 0.5)),
        solMsg('s', 'That sounds stressful'),
        userMsg('3', 'I could not sleep after that either', r: reading(neg: 0.75)),
        userMsg('4', 'Sleep is the main thing I keep losing', r: reading(neg: 0.7)),
        userMsg('5', 'not yet read'),
      ]);
      final b = ConversationBreakdown.from(conv);
      expect(b.userMessages, 5);
      expect(b.unreadMessages, 1);
      expect(b.points, hasLength(4));
      expect(b.moodCounts['Upbeat'], 1);
      expect(b.moodCounts['Tense'], 1);
      expect(b.moodCounts['Low'], 2);
      expect(b.dominantWord, 'Low');
      expect(b.shifts.first.lighter, isFalse);
      expect(b.shifts.first.to.message.id, '2');
      expect(b.keywords, contains('sleep'));
      expect(b.notes.join(' '), contains('heavier'));
    });

    test('with fewer than three readings it only says so', () {
      final b = ConversationBreakdown.from(conversation([userMsg('1', 'hi there', r: reading())]));
      expect(b.notes, ['Too few messages have been read to see a pattern yet.']);
      expect(b.shifts, isEmpty);
    });

    test('an unsure reading counts as Even, and the placeholder voice text is ignored', () {
      final b = ConversationBreakdown.from(conversation([
        userMsg('1', 'hmm', r: reading(mood: null, neg: 0.3, pos: 0.3)),
        ChatMessageRecord(id: 'v', isUser: true, text: 'Audio reflection', timestamp: DateTime.now(), isVoice: true),
      ]));
      expect(b.userMessages, 1);
      expect(b.dominantWord, 'Even');
    });
  });

  group('on the chat page', () {
    SafetyController safety() =>
        SafetyController(screener: const KeywordSafetyScreener(), repository: InMemorySafetyEventRepository());

    Future<void> pump(WidgetTester tester, ChatController c) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(home: ChatPage(safetyController: safety(), chatController: c, autoConnect: false)));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('holding one of my messages shows how it read; Sol\'s messages show nothing', (tester) async {
      final c = await controllerWith([
        solMsg('g', 'Hello, what is on your mind?'),
        userMsg('u1', 'I am so tired of everything', r: reading(inContext: true)),
      ]);
      await pump(tester, c);

      await tester.longPress(find.text('Hello, what is on your mind?'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('message-reading')), findsNothing);

      await tester.longPress(find.text('I am so tired of everything'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('message-reading')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-reading-word')), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.textContaining('earlier messages in mind'), findsOneWidget);
      expect(find.textContaining('Heavy 70%'), findsOneWidget);
      // named feelings from words alone: tucked away, but one tap shows them with a warning
      expect(find.text('Sad'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('feelings-toggle')));
      await tester.pump();
      expect(find.textContaining('huge grain of salt'), findsOneWidget);
      expect(find.text('Sad'), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.byKey(const ValueKey('message-reading')), findsNothing);
    });

    testWidgets('a message with no reading is read on the spot, or says why it cannot be', (tester) async {
      final c = await controllerWith([userMsg('u1', 'long ago I said this')]);
      await pump(tester, c);
      await tester.longPress(find.text('long ago I said this'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('message-reading-none')), findsOneWidget); // no reader wired: says why, shows nothing made up
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();

      c.messageReader = (m, before) async => reading(mood: 'calm or content', neg: 0.1, pos: 0.6);
      await tester.longPress(find.text('long ago I said this'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Calm'), findsOneWidget);
      expect(c.conversationById('c1')!.messages.last.reading?.mood, 'calm or content'); // kept for next time
    });

    testWidgets('the header icon opens the whole-conversation breakdown with a way to Support', (tester) async {
      final c = await controllerWith([
        userMsg('1', 'Work was fine and I felt good', r: reading(mood: 'upbeat', neg: 0.05, pos: 0.8)),
        userMsg('2', 'My manager shouted at me about the sleep issue', r: reading(mood: 'tense or upset', neg: 0.8, pos: 0.05)),
        userMsg('3', 'Sleep has been the worst part of it', r: reading(neg: 0.75)),
      ], summary: 'They talked about work stress and poor sleep.');
      await pump(tester, c);
      await tester.tap(find.byKey(const ValueKey('chat-breakdown')));
      await tester.pumpAndSettle();

      expect(find.byType(ConversationBreakdownPage), findsOneWidget);
      expect(find.byKey(const ValueKey('breakdown-dominant')), findsOneWidget);
      expect(find.byKey(const ValueKey('breakdown-chart')), findsOneWidget);
      expect(find.text('They talked about work stress and poor sleep.'), findsOneWidget);
      expect(find.byKey(const ValueKey('breakdown-support')), findsOneWidget);

      // tapping the chart selects an earlier message
      final chart = tester.getTopLeft(find.byKey(const ValueKey('breakdown-chart')));
      await tester.tapAt(chart + const Offset(20, 60));
      await tester.pump();
      expect(find.textContaining('Work was fine'), findsWidgets);

      // further down: the moments that moved, and what was kept
      await tester.scrollUntilVisible(find.byKey(const ValueKey('breakdown-kept-empty')), 300,
          scrollable: find.byType(Scrollable).last);
      expect(find.byKey(const ValueKey('breakdown-kept-empty')), findsOneWidget);
    });

    testWidgets('how you looked is not offered when the camera was never on', (tester) async {
      final without = await controllerWith([userMsg('1', 'No camera in this one', r: reading())]);
      await pump(tester, without);
      await tester.tap(find.byKey(const ValueKey('chat-breakdown')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('breakdown-looks')), findsNothing);
    });

    testWidgets('how you looked is tucked away until you ask, and hedged', (tester) async {
      final c = await controllerWith([
        userMsg('1', 'Work was fine and I felt good', r: reading(pattern: 'ATV', face: const {'happy': 0.6, 'neutral': 0.3, 'sad': 0.1})),
        userMsg('2', 'My manager shouted at me', r: reading(pattern: 'ATV', face: const {'sad': 0.55, 'neutral': 0.35, 'angry': 0.1})),
        userMsg('3', 'Typed with no camera', r: reading()),
      ]);
      await pump(tester, c);
      await tester.tap(find.byKey(const ValueKey('chat-breakdown')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('breakdown-looks')), 300, scrollable: find.byType(Scrollable).last);

      expect(find.byKey(const ValueKey('looks-withheld')), findsOneWidget);
      expect(find.textContaining('roughly'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('looks-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('looks-warning')), findsOneWidget);
      expect(find.textContaining('roughly happy (60%)'), findsOneWidget);
      expect(find.textContaining('roughly sad (55%)'), findsOneWidget);
      expect(find.byKey(const ValueKey('looks-3')), findsNothing); // a message with no camera is not listed
    });

    testWidgets('a conversation with unread messages offers to read them', (tester) async {
      final c = await controllerWith([userMsg('1', 'an older message of mine here')]);
      c.messageReader = (m, before) async => reading();
      await pump(tester, c);
      await tester.tap(find.byKey(const ValueKey('chat-breakdown')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('breakdown-unread')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('breakdown-read')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('breakdown-unread')), findsNothing);
      expect(find.byKey(const ValueKey('breakdown-dominant')), findsOneWidget);
    });
  });
}
