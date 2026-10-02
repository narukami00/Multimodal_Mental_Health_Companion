import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/memory/moment_extractor.dart';
import 'package:solace_mobile/features/chat/chat_controller.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/day_rhythm_card.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/insights/insights_page.dart';
import 'package:solace_mobile/features/memory/companion_memory_context.dart';
import 'package:solace_mobile/features/memory/moment_proposal_card.dart';
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

/// Fails with the widget that overflowed, not just that something did.
void _noOverflow(WidgetTester tester) {
  final error = tester.takeException();
  expect(error, isNull, reason: error is FlutterError ? error.toStringDeep() : '$error');
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Phone-width screens at large font sizes: anything that overflows throws, so a
/// page that passes here stays readable for someone who has enlarged their text.
void main() {
  final now = DateTime(2026, 10, 31, 9);

  late SessionController sessions;
  late ProfileController profile;
  late MomentsController moments;
  late ChatController chat;
  late ConsentController consent;
  late PhonePatternsController phone;
  late CompanionMemoryContext memory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sessionRepository = InMemorySessionRepository();
    for (var d = 1; d <= 20; d++) {
      for (final hour in [9, 19]) {
        await sessionRepository.save(
          SessionRecord(
            id: '$d-$hour',
            createdAt: DateTime(2026, 10, d, hour),
            mode: CaptureMode.text,
            text: 'x',
            mood: hour == 19 && d <= 8 ? 'Wobbly' : 'Steady',
          ),
        );
      }
    }
    sessions = SessionController(
      repository: sessionRepository,
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessions.load();
    profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
    moments = MomentsController(repository: InMemoryMomentRepository());
    await moments.load();
    await moments.addManual('I had coffee with a friend and it was really nice, we laughed a lot.');
    chat = ChatController(preferences: await SharedPreferences.getInstance());
    await chat.load();
    consent = ConsentController(repository: InMemoryConsentRepository());
    await consent.load();

    final features = InMemoryDailyFeaturesRepository();
    for (var back = 1; back <= 28; back++) {
      final day = DateTime(2026, 10, 31 - back);
      await features.upsert(
        DailyFeatures(
          dayKey: _key(day),
          sources: const {'usage', 'usageFinal'},
          screenOnMinutes: 200 + back,
          sessionCount: 60,
          longestSessionMinutes: 38,
          hourlyActiveMinutes: [for (var h = 0; h < 24; h++) h == 21 ? 40 : (h >= 8 && h < 20 ? 10 : 0)],
          categoryMinutes: const {'social': 90, 'messaging': 40, 'video': 20, 'productivity': 15},
          estimatedSleepStartMinute: 23 * 60 + 30,
          estimatedSleepEndMinute: 7 * 60,
          estimatedSleepMinutes: 450,
        ),
      );
    }
    phone = PhonePatternsController(
      consent: consent,
      collector: _Collector(),
      repository: features,
    );
    memory = CompanionMemoryContext(
      consent: consent,
      profile: profile,
      moments: moments,
      sessions: () => sessions.sessions,
      themes: () => const [],
    );
  });

  Future<void> show(WidgetTester tester, Widget page, {double scale = 2.0}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            // The ring breathes forever; settling needs it still.
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final scale in [1.3, 2.0]) {
    group('at ${scale}x text', () {
      testWidgets('My phone patterns', (tester) async {
        await tester.runAsync(() => phone.refresh());
        await show(tester, PhonePatternsPage(phonePatterns: phone, profileController: profile, clock: () => now), scale: scale);
        _noOverflow(tester);
      });

      testWidgets('What Sol remembers', (tester) async {
        await show(
          tester,
          WhatSolRemembersPage(moments: moments, memory: memory, consent: consent, profileController: profile, chat: chat),
          scale: scale,
        );
        _noOverflow(tester);
      });

      testWidgets('Everything Solace keeps', (tester) async {
        await show(
          tester,
          EverythingKeptPage(
            sessionController: sessions,
            profileController: profile,
            chatController: chat,
            moments: moments,
            memory: memory,
            phonePatterns: phone,
          ),
          scale: scale,
        );
        _noOverflow(tester);
      });

      for (final tab in ['mood', 'helps', 'phone', 'moments']) {
        testWidgets('Insights, $tab tab', (tester) async {
          await show(
            tester,
            InsightsPage(
              sessionController: sessions,
              phonePatterns: phone,
              profileController: profile,
              momentsTab: const Placeholder(fallbackHeight: 40),
              clock: () => now,
            ),
            scale: scale,
          );
          final finder = find.byKey(ValueKey('insights-tab-$tab'));
          if (finder.evaluate().isNotEmpty) {
            await tester.tap(finder);
            await tester.pump(const Duration(milliseconds: 600));
          }
          _noOverflow(tester);
        });
      }

      testWidgets('the day ring card and the moment card', (tester) async {
        await tester.runAsync(() => phone.refresh());
        await tester.runAsync(
          () => moments.consider(
            MomentCandidate(
              text: 'We went for a walk by the river and I felt calmer.',
              source: MomentSource.journal,
              createdAt: now,
              sourceRef: 'r1',
            ),
          ),
        );
        await show(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  DayRhythmCard(phonePatterns: phone, profileController: profile, clock: () => now),
                  MomentProposalCard(controller: moments, consent: consent, onStopAsking: () {}),
                ],
              ),
            ),
          ),
          scale: scale,
        );
        _noOverflow(tester);
      });
    });
  }
}
