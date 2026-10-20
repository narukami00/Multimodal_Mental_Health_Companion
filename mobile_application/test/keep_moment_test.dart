import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/domain/memory/moment_entry.dart';
import 'package:solace_mobile/features/chat/message_reading_popover.dart';
import 'package:solace_mobile/features/journal/session_detail_page.dart';
import 'package:solace_mobile/features/memory/keep_moment.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';

EmotionResult _reading({String pattern = 'AT', double negative = 0.1, Map<String, double>? face}) => EmotionResult(
      sessionId: 's',
      modality: EmotionModality.voice,
      timestamp: DateTime(2026, 10, 20),
      modelVersion: 'test',
      mood: 'calm or content',
      tier: 'clear',
      pattern: pattern,
      classes: const {'happy': 0.6, 'neutral': 0.3, 'sad': 0.1},
      valenceProbs: {'negative': negative, 'neutral': 0.2, 'positive': 0.7 - negative},
      faceClasses: face,
    );

void main() {
  late MomentsController moments;

  setUp(() async {
    moments = MomentsController(repository: InMemoryMomentRepository());
    await moments.load();
  });

  tearDown(() => KeepMoment.controller = null);

  group('keeping something from an entry', () {
    test('is kept at once, in their words, with what the model read beside it and labelled as the model\'s', () async {
      final kept = await moments.keepFromEntry(
        text: 'I walked by the river and it felt wonderful.',
        source: MomentSource.chat,
        sourceRef: 'chat:1',
        moodWord: 'Steady',
        reading: _reading(pattern: 'ATV', face: const {'happy': 0.5, 'neutral': 0.5}),
      );
      expect(kept.state, MomentState.confirmed);
      expect(kept.text, 'I walked by the river and it felt wonderful.');
      expect(kept.sourceRef, 'chat:1');
      expect(kept.moodWord, 'Steady');
      expect(kept.emotionClass, 'happy');
      expect(kept.signals, 'ATV');
      expect(kept.lookedClass, isNotNull);
      expect(kept.tone, MomentTone.warm);
      expect(moments.confirmed.single.id, kept.id);
    });

    test('a clearly heavy reading keeps it as a hard moment, which Insights never lists', () async {
      final kept = await moments.keepFromEntry(
        text: 'I got through the day.',
        source: MomentSource.journal,
        sourceRef: 's1',
        reading: _reading(negative: 0.7),
      );
      expect(kept.tone, MomentTone.heavy);
      expect(moments.forInsights, isEmpty);
      expect(moments.confirmed, hasLength(1));
    });

    test('works without any reading, and with a topic Sol would never offer on its own', () async {
      final kept = await moments.keepFromEntry(
        text: 'My sister and I finally spoke after the funeral and it helped.',
        source: MomentSource.chat,
        sourceRef: 'chat:2',
      );
      expect(kept.state, MomentState.confirmed);
      expect(kept.signals, isNull);
      expect(kept.emotionClass, isNull);
    });

    test('the same words from the same entry are kept once; different words are another moment', () async {
      final a = await moments.keepFromEntry(text: 'A good walk.', source: MomentSource.chat, sourceRef: 'chat:3');
      final again = await moments.keepFromEntry(text: 'a good walk', source: MomentSource.chat, sourceRef: 'chat:3');
      final other = await moments.keepFromEntry(text: 'The tea was lovely.', source: MomentSource.chat, sourceRef: 'chat:3');
      expect(again.id, a.id);
      expect(other.id, isNot(a.id));
      expect(moments.confirmed, hasLength(2));
      // and they go together when the entry is deleted
      await moments.deleteForSource('chat:3');
      expect(moments.confirmed, isEmpty);
    });

    test('a hidden moment with the same words is confirmed instead of duplicated', () async {
      final first = await moments.keepFromEntry(text: 'A good walk.', source: MomentSource.chat, sourceRef: 'chat:4');
      await moments.hide(first.id);
      final back = await moments.keepFromEntry(text: 'A good walk.', source: MomentSource.chat, sourceRef: 'chat:4');
      expect(back.id, first.id);
      expect(back.state, MomentState.confirmed);
      expect(moments.all, hasLength(1));
    });

    test('the new fields survive saving and loading, and older moments without them still load', () {
      final withSignals = MemoryMoment(
        id: 'a',
        text: 'x',
        createdAt: DateTime(2026, 1, 1),
        occurredOn: '2026-01-01',
        source: MomentSource.chat,
        signals: 'ATV',
        lookedClass: 'happy',
      );
      final back = MemoryMoment.fromMap(withSignals.toMap())!;
      expect(back.signals, 'ATV');
      expect(back.lookedClass, 'happy');

      final old = Map<String, Object?>.of(withSignals.toMap())
        ..remove('signals')
        ..remove('lookedClass');
      expect(MemoryMoment.fromMap(old)!.signals, isNull);
    });
  });

  group('what to offer for keeping', () {
    test('a short entry is offered whole', () {
      expect(suggestMomentText('  A good   walk today.  '), 'A good walk today.');
    });

    test('a long entry is offered as their own best sentence', () {
      const long = 'Work was a lot this week and I was behind on everything again and again. '
          'On Thursday I went for a walk by the river and it was lovely. '
          'Then I came home and sat with the laundry for an hour doing nothing useful at all, which is how it goes.';
      expect(suggestMomentText(long), 'On Thursday I went for a walk by the river and it was lovely.');
    });

    test('a long entry with no clear good sentence is offered as its start, cut at a word and short enough to keep', () {
      final long = List.filled(60, 'ordinary').join(' ');
      final offered = suggestMomentText(long);
      expect(offered.length, lessThanOrEqualTo(MemoryMoment.maxLength));
      expect(long.startsWith(offered), isTrue);
      expect(offered.endsWith(' '), isFalse);
    });
  });

  group('the buttons', () {
    Future<void> pumpPage(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
    }

    final session = SessionRecord(
      id: 'entry-1',
      createdAt: DateTime(2026, 10, 20, 9),
      mode: CaptureMode.text,
      text: 'Today I walked by the river with my sister and it felt so good.',
      mood: 'Steady',
    );

    testWidgets('a journal entry offers it, opens on their own words, and keeps what they choose', (tester) async {
      KeepMoment.controller = moments;
      await pumpPage(tester, SessionDetailPage(session: session));

      await tester.tap(find.byKey(const ValueKey('keep-moment')));
      await tester.pumpAndSettle();
      expect(find.text('Keep this as a moment'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const ValueKey('moment-field')));
      expect(field.controller!.text, session.text);

      await tester.enterText(find.byKey(const ValueKey('moment-field')), 'I walked by the river with my sister.');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('moment-keep')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      final kept = moments.confirmed.single;
      expect(kept.text, 'I walked by the river with my sister.');
      expect(kept.sourceRef, 'entry-1');
      expect(kept.editedByUser, isTrue);
      expect(kept.moodWord, 'Steady');
      expect(find.textContaining('Kept as a moment'), findsOneWidget);
    });

    testWidgets('a journal entry shows no button where moments are not available', (tester) async {
      await pumpPage(tester, SessionDetailPage(session: session));
      expect(find.byKey(const ValueKey('keep-moment')), findsNothing);
    });

    testWidgets('the press-and-hold card on a message offers it beside the breakdown, with that reading', (tester) async {
      EmotionResult? seen;
      final message = ChatMessageRecord(
        id: 'm1',
        isUser: true,
        text: 'I had a lovely walk with my sister today.',
        timestamp: DateTime(2026, 10, 20, 9),
        reading: _reading(pattern: 'ATV'),
      );
      await pumpPage(
        tester,
        Align(
          child: MessageReadingCard(message: message, read: null, onKeep: (r) => seen = r),
        ),
      );
      expect(find.byKey(const ValueKey('message-reading-word')), findsOneWidget); // the breakdown is still there
      await tester.tap(find.byKey(const ValueKey('message-keep-moment')));
      expect(seen?.pattern, 'ATV');
    });

    testWidgets('the card offers nothing to keep when no way to keep is given', (tester) async {
      final message = ChatMessageRecord(id: 'm2', isUser: true, text: 'hello there friend', timestamp: DateTime(2026, 10, 20), reading: _reading());
      await pumpPage(tester, Align(child: MessageReadingCard(message: message, read: null)));
      expect(find.byKey(const ValueKey('message-keep-moment')), findsNothing);
    });
  });
}
