import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/insights/helps_tab.dart';
import 'package:solace_mobile/features/insights/ideas_invitation_card.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_page.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

class _Library implements ActivityLibraryRepository {
  const _Library(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

Activity _activity(String id) => Activity(
  id: id,
  title: 'Idea $id',
  description: 'A small thing to try.',
  type: ActivityType.movement,
  effort: ActivityEffort.low,
  durationMinutes: 10,
  contexts: const [],
  targetStates: const [],
  review: ActivityReviewMetadata(
    status: ActivityReviewStatus.approved,
    evidenceTier: ActivityEvidenceTier.lifestyle,
    reviewerRole: 'test',
    reviewedAt: DateTime(2026, 1, 1),
  ),
);

const _context = RecommendationContext(profileAgeDays: 20);

Future<SuggestionController> _controller([List<String> ids = const ['a', 'b', 'c']]) async {
  final controller = SuggestionController(
    libraryRepository: _Library([for (final id in ids) _activity(id)]),
    suggestionRepository: InMemorySuggestionRepository(),
  );
  await controller.load();
  await controller.warmUp();
  return controller;
}

void main() {
  group('the idea scene', () {
    IdeaScene at(int hour, {List<double> scores = const [], int tries = 0}) =>
        IdeaScene.from(now: DateTime(2026, 10, 1, hour), moodScores: scores, tries: tries);

    test('follows the time of day', () {
      expect(at(6).part, DayPart.dawn);
      expect(at(12).part, DayPart.day);
      expect(at(18).part, DayPart.dusk);
      expect(at(23).part, DayPart.night);
      expect(at(2).part, DayPart.night);
    });

    test('says something different at different times, in a few plain words', () {
      final lines = {at(6).invitation, at(12).invitation, at(18).invitation, at(23).invitation};
      expect(lines, hasLength(4));
    });

    test('turns soft and slow when the last days have been heavy, and never says why', () {
      final heavy = at(12, scores: const [0.25, 0.0, -0.25, -1.0, -1.0]);
      expect(heavy.gentle, isTrue);
      expect(heavy.pace, lessThan(1.0));
      expect(heavy.invitation, 'Something small, if you feel like it.');
      for (final word in ['sad', 'low', 'down', 'sorry', 'struggl', 'hard time']) {
        expect(heavy.invitation.toLowerCase(), isNot(contains(word)));
      }
    });

    test('stays as it is when things are steady or lifting, or when there is nothing to go on', () {
      expect(at(12, scores: const [0.25, 0.25, 0.25]).gentle, isFalse);
      expect(at(12, scores: const [-0.25, 0.25, 1.0]).gentle, isFalse);
      expect(at(12).gentle, isFalse);
    });

    test('a sharp drop is enough even if the average is fine', () {
      expect(at(12, scores: const [1.0, 1.0, 1.0, 0.0, -0.25, -0.25]).gentle, isTrue);
    });
  });

  group('asking for an idea', () {
    late SuggestionController controller;
    late SessionController sessions;
    late ProfileController profile;

    Future<void> open(WidgetTester tester, {String? resume, bool finished = false, bool onDemand = true}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
      profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();
      await profile.ensureFirstRun();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SuggestionPage(
            key: UniqueKey(),
            suggestionController: controller,
            profileController: profile,
            safetyController: SafetyController(screener: const KeywordSafetyScreener(), repository: InMemorySafetyEventRepository()),
            sessionController: sessions,
            onDemand: onDemand,
            resumeRecordId: resume,
            resumeFinished: finished,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() async => controller = await _controller());

    testWidgets('starts by asking how they are, and skipping it is fine', (tester) async {
      await open(tester);

      expect(find.text('How are you right now?'), findsOneWidget);
      await tester.tap(find.text('Skip, just show me'));
      await tester.pumpAndSettle();

      expect(find.text("I'll do it"), findsOneWidget);
      expect(find.text('Another idea'), findsOneWidget);
      expect(controller.history, isEmpty, reason: 'looking is never written down');
    });

    testWidgets('another idea shows a different one, again and again, and none of it is recorded', (tester) async {
      await open(tester);
      await tester.tap(find.text('Skip, just show me'));
      await tester.pumpAndSettle();

      final seen = <String>{};
      for (var i = 0; i < 3; i++) {
        seen.add(tester.widgetList<Text>(find.textContaining('Idea ')).first.data!);
        if (i < 2) {
          await tester.tap(find.text('Another idea'));
          await tester.pumpAndSettle();
        }
      }
      expect(seen, hasLength(3));

      // All three have been seen: nothing more, and still nothing written.
      await tester.tap(find.text('Another idea'));
      await tester.pumpAndSettle();
      expect(find.text("That's all I have for now."), findsOneWidget);
      expect(controller.history, isEmpty);
    });

    testWidgets("saying how they are first is kept, but only once they say they'll do it", (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('feel-Wobbly')));
      await tester.pump();
      await tester.tap(find.text('Show me an idea'));
      await tester.pumpAndSettle();
      expect(controller.history, isEmpty);

      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();

      final record = controller.history.single;
      expect(record.proactive, isFalse, reason: "asked for, so it never uses up the day's unasked slot");
      expect(record.acceptedAt, isNotNull);
      expect(record.moodBefore, 'Wobbly');
      expect(record.done, isNull);
      expect(find.text("YOU'RE ON THIS"), findsOneWidget);
      expect(find.text("I'm done"), findsOneWidget);
      expect(find.text('Something came up'), findsOneWidget);
    });

    testWidgets('done writes the time, asks how they feel, and keeps the before and after as a pair', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('feel-Wobbly')));
      await tester.pump();
      await tester.tap(find.text('Show me an idea'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("I'm done"));
      await tester.pumpAndSettle();
      expect(find.text('How do you feel now?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('feel-Steady')));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final record = controller.history.single;
      expect(record.done, isTrue);
      expect(record.completedAt, isNotNull);
      expect(record.moodBefore, 'Wobbly');
      expect(record.moodAfter, 'Steady');
      expect(find.text('Another idea'), findsOneWidget);

      // Another one starts again from how they are, every time.
      await tester.tap(find.text('Another idea'));
      await tester.pumpAndSettle();
      expect(find.text('How are you right now?'), findsOneWidget);
    });

    testWidgets('something came up ends it with no verdict and nothing learned', (tester) async {
      await open(tester);
      await tester.tap(find.text('Skip, just show me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Something came up'));
      await tester.pumpAndSettle();

      final record = controller.history.single;
      expect(record.done, isNull);
      expect(record.status, SuggestionStatus.skipped);
      expect(record.skipReason, SuggestionSkipReason.notNow);
      expect(record.moodAfter, isNull);
      expect(controller.doingNow(), isNull);
    });

    testWidgets('with one in progress there is nothing to shuffle through: it opens on that one', (tester) async {
      final recommendation = controller.peek(profile: const UserProfile(), context: _context)!;
      final record = await controller.commit(recommendation, context: _context, fresh: true);
      await controller.startDoing(record.id);

      await open(tester);

      expect(find.text("YOU'RE ON THIS"), findsOneWidget);
      expect(find.text(recommendation.activity.title), findsOneWidget);
      expect(find.text('Another idea'), findsNothing);
      expect(find.text('How are you right now?'), findsNothing);
      expect(find.text("I'll do it"), findsNothing);
    });

    testWidgets('an idea started earlier opens straight on the doing screen, and a finished one on how they feel', (tester) async {
      final recommendation = controller.peek(profile: const UserProfile(), context: _context)!;
      final record = await controller.commit(recommendation, context: _context, fresh: true);
      await controller.startDoing(record.id);

      await open(tester, resume: record.id, onDemand: false);
      expect(find.text("YOU'RE ON THIS"), findsOneWidget);

      await controller.completeRecord(record.id);
      await open(tester, resume: record.id, finished: true, onDemand: false);
      expect(find.text('How do you feel now?'), findsOneWidget);
    });

    testWidgets('the doing screen still fits when the text is enlarged', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);
      await tester.tap(find.text('Skip, just show me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'll do it"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('the Helps tab card', () {
    Future<List<String>> pump(WidgetTester tester, {bool inProgress = false, bool wired = true}) async {
      final controller = await _controller(['a']);
      if (inProgress) {
        final recommendation = controller.peek(profile: const UserProfile(), context: _context)!;
        final record = await controller.commit(recommendation, context: _context, fresh: true);
        await controller.startDoing(record.id);
      }
      final calls = <String>[];
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HelpsTab(
                suggestionController: controller,
                ideaActions: wired
                    ? IdeaActions(
                        ask: () => calls.add('ask'),
                        resume: (_) => calls.add('resume'),
                        finish: (_) => calls.add('finish'),
                        interrupt: (_) => calls.add('interrupt'),
                      )
                    : null,
                clock: () => DateTime(2026, 10, 1, 12),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return calls;
    }

    testWidgets('invites them to try something, and asking opens the flow', (tester) async {
      final calls = await pump(tester);

      expect(find.text('Want to try something?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ideas-start')));
      expect(calls, ['ask']);
    });

    testWidgets('with one in progress it shows that one, and offers no way to ask for another', (tester) async {
      final calls = await pump(tester, inProgress: true);

      expect(find.text('Idea a'), findsOneWidget);
      expect(find.text("I'm done"), findsOneWidget);
      expect(find.text('Something came up'), findsOneWidget);
      expect(find.byKey(const ValueKey('ideas-start')), findsNothing);
      expect(find.text('Show me an idea'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('ideas-done')));
      await tester.tap(find.byKey(const ValueKey('ideas-interrupt')));
      expect(calls, ['finish', 'interrupt']);
    });

    testWidgets('is not shown where nothing is wired to it', (tester) async {
      await pump(tester, wired: false);

      expect(find.byKey(const ValueKey('ideas-invitation')), findsNothing);
    });

    testWidgets('fits when the text is enlarged', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, inProgress: true);

      expect(tester.takeException(), isNull);
    });
  });
}
