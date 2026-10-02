import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/chat_message_record.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/memory/companion_memory_context.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';
import 'package:solace_mobile/features/memory/what_sol_remembers_page.dart';
import 'package:solace_mobile/features/profile/everything_kept_page.dart';
import 'package:solace_mobile/features/profile/phone_patterns_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

class _Collector implements UsageCollectorService {
  @override
  Future<bool> hasAccess() async => true;
  @override
  Future<bool> openAccessSettings() async => true;
  @override
  Future<List<UsageEvent>> events({required DateTime from, required DateTime to}) async =>
      const [];
  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async => const {};
}

void main() {
  late SessionController sessions;
  late ProfileController profile;
  late MomentsController moments;
  late ChatController chat;
  late PhonePatternsController phone;
  late InMemoryDailyFeaturesRepository phoneRepository;
  late CompanionMemoryContext memory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessions.load();
    profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
    moments = MomentsController(repository: InMemoryMomentRepository());
    await moments.load();
    chat = ChatController(preferences: await SharedPreferences.getInstance());
    await chat.load();
    final consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();
    phoneRepository = InMemoryDailyFeaturesRepository();
    phone = PhonePatternsController(
      consent: consent,
      collector: _Collector(),
      repository: phoneRepository,
    );
    memory = CompanionMemoryContext(
      consent: consent,
      profile: profile,
      moments: moments,
      sessions: () => sessions.sessions,
      themes: () => const [],
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EverythingKeptPage(
          sessionController: sessions,
          profileController: profile,
          chatController: chat,
          moments: moments,
          memory: memory,
          phonePatterns: phone,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String v) => find.byKey(ValueKey(v));

  testWidgets('with nothing kept, says so for each kind', (tester) async {
    await pump(tester);

    expect(find.textContaining('Nothing yet.'), findsNWidgets(2));
    expect(find.text('Nothing kept.'), findsOneWidget);
    expect(find.text('Nothing stored.'), findsOneWidget);
  });

  testWidgets('counts come straight from the stores', (tester) async {
    await tester.runAsync(() async {
      await sessions.saveSession(mode: CaptureMode.text, text: 'one');
      await sessions.saveSession(mode: CaptureMode.text, text: 'two');
      await chat.addMessage(
        ChatMessageRecord(
          id: 'm1',
          isUser: true,
          text: 'hello',
          timestamp: DateTime(2026, 10, 20),
        ),
      );
      await chat.setSummary(chat.activeConversation!.id, 'The user said hello.', 'm1');
      await moments.addManual('A good walk by the river.');
      await moments.addManual('Tea with my sister.');
      await phoneRepository.upsert(
        const DailyFeatures(dayKey: '2026-10-01', sources: {'usage', 'usageFinal'}, screenOnMinutes: 100),
      );
    });
    await pump(tester);

    expect(find.textContaining('2 entries.'), findsOneWidget);
    expect(find.textContaining('1 conversation, 1 with a short note'), findsOneWidget);
    expect(find.text('2 kept.'), findsOneWidget);
    expect(find.textContaining('1 day of patterns, kept for 180 days'), findsOneWidget);
  });

  testWidgets('moments and phone patterns lead to where they are managed', (tester) async {
    await pump(tester);

    await tester.tap(key('kept-moments'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatSolRemembersPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(key('kept-phone'));
    await tester.pumpAndSettle();
    expect(find.byType(PhonePatternsPage), findsOneWidget);
  });

  testWidgets('it claims nothing about a store it was not given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EverythingKeptPage(sessionController: sessions, profileController: profile),
      ),
    );
    await tester.pumpAndSettle();

    expect(key('kept-moments'), findsNothing);
    expect(key('kept-phone'), findsNothing);
    expect(key('kept-entries'), findsOneWidget);
  });
}

