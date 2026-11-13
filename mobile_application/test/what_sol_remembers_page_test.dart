import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/memory/companion_memory_context.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';
import 'package:solace_mobile/core/widgets/visual_kit.dart';
import 'package:solace_mobile/features/chat/highlighted_text.dart';
import 'package:solace_mobile/features/memory/what_sol_remembers_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';

void main() {
  late ConsentController consent;
  late ProfileController profile;
  late MomentsController moments;
  late CompanionMemoryContext memory;

  setUp(() async {
    consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    final repository = InMemoryProfileRepository();
    await repository.save(const UserProfile(interactionPreferences: ['Gentle tone']));
    profile = ProfileController(repository: repository);
    await profile.load();
    moments = MomentsController(repository: InMemoryMomentRepository());
    await moments.load();
    memory = CompanionMemoryContext(
      consent: consent,
      profile: profile,
      moments: moments,
      sessions: () => const [],
      themes: () => const [],
      clock: () => DateTime(2026, 10, 20, 15),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: WhatSolRemembersPage(
          moments: moments,
          memory: memory,
          consent: consent,
          profileController: profile,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with nothing agreed, shows what would be said and sends nothing', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('If you turn this on, Sol would be told:'), findsNWidgets(2));
    expect(find.textContaining('a gentle tone'), findsOneWidget);
    expect(memory.payload(), isNull);
  });

  testWidgets('the switches are the consent', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('snippet-switch')));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.profileSnippet), isTrue);
    expect(find.text('Sol is told:'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('snippet-switch')));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.profileSnippet), isFalse);
  });

  testWidgets('noticing how I sound is off until the person turns it on', (
    tester,
  ) async {
    await pump(tester);
    expect(consent.isGranted(ConsentKey.emotionEstimate), isFalse);

    await tester.ensureVisible(find.byKey(const ValueKey('emotion-switch')));
    await tester.tap(find.byKey(const ValueKey('emotion-switch')));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.emotionEstimate), isTrue);

    await tester.tap(find.byKey(const ValueKey('emotion-switch')));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.emotionEstimate), isFalse);
  });

  testWidgets('reading my face is its own switch, and turning it on also turns on noticing how I sound', (
    tester,
  ) async {
    await pump(tester);
    expect(consent.isGranted(ConsentKey.faceFeatures), isFalse);

    await tester.ensureVisible(find.byKey(const ValueKey('face-switch')));
    await tester.tap(find.byKey(const ValueKey('face-switch')));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.faceFeatures), isTrue);
    expect(consent.isGranted(ConsentKey.emotionEstimate), isTrue);

    await tester.tap(find.byKey(const ValueKey('face-switch')));
    await tester.pumpAndSettle();
    expect(consent.isGranted(ConsentKey.faceFeatures), isFalse);
    expect(consent.isGranted(ConsentKey.emotionEstimate), isTrue); // the voice and text consent is untouched

    // Withdrawing the parent also ends the camera consent: a sub-grant needs its parent.
    await tester.tap(find.byKey(const ValueKey('face-switch')));
    await tester.pumpAndSettle();
    await consent.revoke(ConsentKey.emotionEstimate);
    expect(consent.isGranted(ConsentKey.faceFeatures), isFalse);
  });

  testWidgets('lists every moment, and its menu keeps, sets aside, and deletes', (
    tester,
  ) async {
    final moment = (await tester.runAsync(
      () => moments.addManual('A good walk by the river.'),
    ))!;
    await pump(tester);

    expect(find.text('A good walk by the river.'), findsOneWidget);
    expect(find.textContaining('Kept'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('moment-menu-${moment.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set aside'));
    await tester.pumpAndSettle();
    expect(moments.hidden, hasLength(1));
    expect(find.textContaining('Set aside'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('moment-menu-${moment.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(moments.all, isEmpty);
    expect(find.byKey(const ValueKey('moments-empty')), findsOneWidget);
  });

  testWidgets('they can add a moment themselves', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('add-moment')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('moment-dialog-field')), 'Tea with my sister.');
    await tester.tap(find.byKey(const ValueKey('moment-dialog-save')));
    await tester.pumpAndSettle();

    expect(moments.confirmed.single.text, 'Tea with my sister.');
  });

  testWidgets('asking can be turned off', (tester) async {
    await pump(tester);
    expect(profile.profile.momentPromptsMuted, isFalse);

    await tester.tap(find.byKey(const ValueKey('asking-switch')));
    await tester.pumpAndSettle();

    expect(profile.profile.momentPromptsMuted, isTrue);
  });

  testWidgets('forgetting all asks first, then clears everything', (tester) async {
    await tester.runAsync(() => moments.addManual('A good walk by the river.'));
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('forget-all-moments')));
    await tester.pumpAndSettle();
    expect(moments.all, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('forget-all-confirm')));
    await tester.pumpAndSettle();
    expect(moments.all, isEmpty);
  });

  testWidgets('lists the notes kept on long conversations, and each can be forgotten', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final chat = ChatController(preferences: await SharedPreferences.getInstance());
    await tester.runAsync(() async {
      await chat.load();
      await chat.addMessage(
        ChatMessageRecord(
          id: 'm1',
          isUser: true,
          text: 'A long day.',
          timestamp: DateTime(2026, 10, 20),
        ),
      );
      await chat.setSummary(chat.activeConversation!.id, 'The user had a long day at work.', 'm1');
    });
    final id = chat.activeConversation!.id;

    tester.view.physicalSize = const Size(1080, 4400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: WhatSolRemembersPage(
          moments: moments,
          memory: memory,
          consent: consent,
          profileController: profile,
          chat: chat,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The user had a long day at work.'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('forget-note-$id')));
    await tester.pumpAndSettle();

    expect(find.text('The user had a long day at work.'), findsNothing);
    expect(chat.activeConversation!.messages, isNotEmpty);
  });

  testWidgets('all four glance stat tiles have identical height', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final chat = ChatController(preferences: await SharedPreferences.getInstance());
    await tester.runAsync(() async {
      await chat.load();
      await chat.addMessage(
        ChatMessageRecord(
          id: 'm1',
          isUser: true,
          text: 'A long day.',
          timestamp: DateTime(2026, 10, 20),
        ),
      );
      await chat.setSummary(
        chat.activeConversation!.id,
        'The user had a long day at work.',
        'm1',
      );
    });

    tester.view.physicalSize = const Size(1080, 4400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: WhatSolRemembersPage(
          moments: moments,
          memory: memory,
          consent: consent,
          profileController: profile,
          chat: chat,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tiles = find.byType(StatTile);
    expect(tiles, findsNWidgets(4));
    expect(find.text('waiting'), findsOneWidget);
    expect(find.text('waiting for you'), findsNothing);

    final heights = List.generate(4, (i) => tester.getSize(tiles.at(i)).height);
    for (final h in heights) {
      expect(h, equals(heights.first));
    }
  });

  testWidgets('pinning an older moment keeps it in Sols top 5 and shows pin badge', (tester) async {
    late String oldestId;
    await tester.runAsync(() async {
      final oldest = await moments.addManual('Core anchor: morning walk helps me reset.');
      oldestId = oldest!.id;
      for (var i = 0; i < 5; i++) {
        await moments.addManual('Newer reflection number $i');
      }
    });
    expect(moments.forSol.any((m) => m.id == oldestId), isFalse);

    await pump(tester);
    await tester.ensureVisible(find.byKey(ValueKey('moment-menu-$oldestId')));
    await tester.tap(find.byKey(ValueKey('moment-menu-$oldestId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin for Sol'));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('moment-pin-badge-$oldestId')), findsOneWidget);
    expect(moments.forSol.first.id, equals(oldestId));
    expect(moments.forSol.length, equals(5));
  });

  testWidgets('search bar filters moments and highlights matched keywords', (tester) async {
    await tester.runAsync(() async {
      await moments.addManual('Evening tea with my sister');
      await moments.addManual('Calm stretch after work');
    });
    await pump(tester);

    expect(find.byKey(const ValueKey('memory-search-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('memory-search-field')),
      'sister',
    );
    await tester.pump();

    expect(find.text('Calm stretch after work'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is HighlightedText &&
            w.query == 'sister' &&
            w.text.contains('Evening tea with my sister'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('memory-search-clear')));
    await tester.pump();
    expect(find.text('Calm stretch after work'), findsOneWidget);
  });
}
