import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/data/repositories/in_memory_moment_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/domain/personalization/personal_calibration.dart';
import 'package:solace_mobile/features/chat/chat_page.dart';
import 'package:solace_mobile/features/memory/moments_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';

PersonalPatternProfile _profile({
  LifePulseSignal? latestPulse,
  List<({String context, int count})> contexts = const [],
  List<String> helpfulTags = const [],
}) {
  return PersonalPatternProfile(
    totalReviewedMoods: 0,
    acceptedMoods: 0,
    correctedMoods: 0,
    rulesByBucket: const {},
    correctionRankByBucket: const {},
    recurringShiftContexts: contexts,
    helpfulTags: helpfulTags,
    latestPulse: latestPulse,
  );
}

void main() {
  SafetyController safety() => SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );

  group('personalChatStarters', () {
    test('returns default starters when profile is absent or empty', () {
      expect(personalChatStarters(), defaultChatStarters);
      expect(personalChatStarters(profile: _profile()), defaultChatStarters);
    });

    test('prioritizes fresh pulse note over tag and ignores stale pulse', () {
      final now = DateTime(2026, 11, 13, 12);
      final fresh = _profile(
        latestPulse: LifePulseSignal(
          moodTag: 'stressed',
          at: now.subtract(const Duration(hours: 6)),
          note: '  Big demo tomorrow  ',
        ),
      );
      final starters = personalChatStarters(profile: fresh, now: now);
      expect(starters.first, 'Talk about "Big demo tomorrow"');
      expect(starters.length, 4);

      final stale = _profile(
        latestPulse: LifePulseSignal(
          moodTag: 'stressed',
          at: now.subtract(const Duration(hours: 60)),
          note: 'Old thing',
        ),
      );
      expect(personalChatStarters(profile: stale, now: now), defaultChatStarters);
    });

    test('includes recurring shift contexts (>=2) and helpful tags without duplicates', () {
      final now = DateTime(2026, 11, 13, 12);
      final profile = _profile(
        latestPulse: LifePulseSignal(
          moodTag: 'tired',
          at: now.subtract(const Duration(hours: 2)),
        ),
        contexts: const [
          (context: 'Sleep', count: 3),
          (context: 'Health', count: 1),
        ],
        helpfulTags: const ['short walks', 'breathing exercises'],
      );
      final starters = personalChatStarters(
        profile: profile,
        fallback: const [
          'Try short walks together',
          'Just want to vent',
          'Reflect on my day',
        ],
        now: now,
      );
      expect(starters, const [
        'Help me wind down — I feel tired',
        "Let's unpack what's been happening with sleep",
        'Try short walks together',
        'Just want to vent',
      ]);
    });
  });

  group('ChatPage personalized starters & handoff draft', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('uses ChatPage.personalization when customStarters is unset', (tester) async {
      addTearDown(() => ChatPage.personalization = null);
      ChatPage.personalization = () => _profile(
            latestPulse: LifePulseSignal(
              moodTag: 'stressed',
              at: DateTime.now().subtract(const Duration(hours: 1)),
            ),
            helpfulTags: const ['grounding exercises'],
          );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            safetyController: safety(),
            autoConnect: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.widgetWithText(ActionChip, "Let's unpack what's making things busy"),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ActionChip, 'Try grounding exercises together'),
        findsOneWidget,
      );
    });

    testWidgets('customStarters overrides personalization and initialDraft prefills input', (tester) async {
      addTearDown(() => ChatPage.personalization = null);
      ChatPage.personalization = () => _profile(
            latestPulse: LifePulseSignal(
              moodTag: 'all_good',
              at: DateTime.now(),
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            safetyController: safety(),
            autoConnect: false,
            customStarters: const [
              'Talk about "Overwhelmed with exams"',
              'Just want to vent',
            ],
            initialDraft: 'Overwhelmed with exams',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.widgetWithText(ActionChip, 'Talk about "Overwhelmed with exams"'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ActionChip, 'Check in on what is going well'),
        findsNothing,
      );
      expect(find.text('What’s on your mind?'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'Overwhelmed with exams');
    });
  });

  group('Track C3 seed_context & waiting cross-session proposals', () {
    test('buildSessionConfigurePayload sends trimmed seed_context only when non-empty', () {
      final withSeed = CompanionWebSocketService.buildSessionConfigurePayload(
        sessionId: 's1',
        mode: 'chat_voice_playback',
        seedContext: '  Opened from home check-in (tired)  ',
      );
      expect(withSeed['seed_context'], 'Opened from home check-in (tired)');

      final blankSeed = CompanionWebSocketService.buildSessionConfigurePayload(
        sessionId: 's1',
        mode: 'chat_voice_playback',
        seedContext: '   ',
      );
      expect(blankSeed.containsKey('seed_context'), isFalse);
    });

    test('proposePatternTheme stages once in waiting, never in forSol until kept', () async {
      final moments = MomentsController(
        repository: InMemoryMomentRepository(),
        clock: () => DateTime(2026, 11, 13, 15),
      );
      await moments.load();

      final profile = _profile(helpfulTags: const ['short walks']);
      final proposed = await moments.proposePatternTheme(profile);
      expect(proposed, isNotNull);
      expect(proposed!.state, MomentState.pending);
      expect(moments.pending.length, 1);
      expect(moments.forSol, isEmpty);

      // Deduplicates even when called again while waiting or after set aside.
      expect(await moments.proposePatternTheme(profile), isNull);
      await moments.hide(proposed.id);
      expect(await moments.proposePatternTheme(profile), isNull);
    });
  });
}
