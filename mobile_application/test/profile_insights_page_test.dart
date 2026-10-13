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
import 'package:solace_mobile/domain/profile/behavioral_profile.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/profile/profile_insights_page.dart';
import 'package:solace_mobile/features/profile/profile_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

final _now = DateTime(2026, 10, 1, 10);

BehavioralProfile _profile({
  UserProfile userProfile = const UserProfile(),
  List<SuggestionRecord> history = const [],
}) {
  return BehavioralProfile.compute(
    profile: userProfile,
    sessions: const [],
    suggestionHistory: history,
    library: [
      Activity(
        id: 'movement-1',
        title: 'Two-minute stretch',
        description: '',
        type: ActivityType.movement,
        effort: ActivityEffort.low,
        durationMinutes: 2,
        contexts: [],
        targetStates: [],
        review: ActivityReviewMetadata(
          status: ActivityReviewStatus.approved,
          evidenceTier: ActivityEvidenceTier.lifestyle,
          reviewerRole: 'test',
          reviewedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ),
    ],
    context: const RecommendationContext(),
    now: _now,
  );
}

Future<void> _pump(
  WidgetTester tester,
  BehavioralProfile profile, {
  DecisionSignals signals = const DecisionSignals(),
}) async {
  // Tall viewport: the page is a lazy ListView, so sections below the fold
  // would otherwise never build and the finds below would miss them.
  tester.view.physicalSize = const Size(1080, 9000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ProfileInsightsPage(profile: profile, signals: signals),
    ),
  );
  await tester.pump();
}

void main() {
  widerPictureTests();

  testWidgets('a fresh user sees honest empty states, not fake numbers', (tester) async {
    await _pump(tester, _profile());

    expect(find.text('HOW IDEAS ARE CHOSEN RIGHT NOW'), findsOneWidget);
    expect(find.textContaining('gentle starter tour'), findsOneWidget);
    expect(find.textContaining('No type has enough history'), findsOneWidget);
    expect(find.textContaining('Nothing is hidden'), findsOneWidget);
    expect(find.textContaining('No ideas answered yet'), findsOneWidget);
  });

  testWidgets('answers show per-type rows with counts, not percentages alone', (tester) async {
    final history = [
      SuggestionRecord(
        id: 'r1',
        activityId: 'movement-1',
        shownAt: _now.subtract(const Duration(days: 1)),
        contextTags: const [],
        status: SuggestionStatus.completed,
        done: true,
        useful: SuggestionUsefulness.up,
      ),
      SuggestionRecord(
        id: 'r2',
        activityId: 'movement-1',
        shownAt: _now.subtract(const Duration(days: 2)),
        contextTags: const [],
        status: SuggestionStatus.skipped,
        skipReason: SuggestionSkipReason.notForMe,
      ),
    ];
    await _pump(tester, _profile(history: history));

    expect(find.text('1 accepted of 2 answered, and how each kind has gone:'),
        findsOneWidget);
    expect(find.text('Movement'), findsOneWidget);
    expect(find.text('1 of 2 completed'), findsOneWidget);
  });

  testWidgets('preferences appear verbatim with their labels', (tester) async {
    await _pump(
      tester,
      _profile(
        userProfile: const UserProfile(
          preferredActivities: ['Movement', 'Nature'],
          constraints: ['Short moments'],
          neverSuggest: ['Exercise'],
        ),
      ),
    );

    expect(find.text('You like:'), findsOneWidget);
    expect(find.text('Movement'), findsOneWidget);
    expect(find.text('Nature'), findsOneWidget);
    expect(find.text('Within:'), findsOneWidget);
    expect(find.text('Short moments'), findsOneWidget);
    expect(find.text('Never suggest:'), findsOneWidget);
    expect(find.text('Exercise'), findsOneWidget);
  });

  testWidgets('never-suggest shows as the type actually being hidden', (tester) async {
    await _pump(
      tester,
      _profile(
        userProfile: const UserProfile(neverSuggest: ['Exercise']),
      ),
    );

    expect(find.textContaining('You asked not to see: movement'), findsOneWidget);
  });

  testWidgets('a recent too-hard explains the gentle cap; the baseline never does', (tester) async {
    // The baseline's gentle-first effect is deliberately never surfaced as
    // reasoning (see RecommendationContext.preferGentle), so even with a
    // moderate GAD-7 the page must not explain the effort ceiling that way.
    final gad7Answers = {
      for (var i = 1; i <= 7; i++) 'gad7_$i': 2,
    };
    final baselineOnly = _profile(
      userProfile: UserProfile(gad7Answers: gad7Answers),
    );
    final withTooHard = _profile(
      userProfile: UserProfile(gad7Answers: gad7Answers),
      history: [
        SuggestionRecord(
          id: 'r1',
          activityId: 'movement-1',
          shownAt: _now.subtract(const Duration(days: 1)),
          contextTags: const [],
          status: SuggestionStatus.skipped,
          skipReason: SuggestionSkipReason.tooHard,
        ),
      ],
    );
    await _pump(tester, baselineOnly);
    expect(find.textContaining('too hard'), findsNothing);

    await _pump(tester, withTooHard);
    expect(find.textContaining('too hard'), findsOneWidget);
  });

  testWidgets('the demo changes what is favoured as the pretend day changes', (tester) async {
    await _pump(tester, _profile());

    Text text(String key) => tester.widget<Text>(find.byKey(ValueKey(key)));
    expect(text('demo-length').data, 'Any length');
    expect(text('demo-effort').data, 'Any effort');
    expect(text('demo-kinds-note').data, 'No kind is leaned towards.');

    await tester.tap(find.byKey(const ValueKey('demo-low')));
    await tester.pump();
    expect(text('demo-length').data, 'Up to 8 min');
    expect(text('demo-effort').data, 'Gentle effort only');
    expect(text('demo-kinds-note').data, contains('small lean'));

    await tester.tap(find.byKey(const ValueKey('demo-medium')));
    await tester.pump();
    expect(text('demo-length').data, 'Up to 15 min');
    expect(text('demo-effort').data, 'Any effort');

    // a recent "Too hard" caps effort even when energy is fine
    await tester.tap(find.byKey(const ValueKey('demo-hard')));
    await tester.pump();
    expect(text('demo-effort').data, 'Gentle effort only');
  });

  testWidgets('the You tab row opens the page', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
    final suggestionController = SuggestionController(
      libraryRepository: _ListLibraryRepository([
        Activity(
          id: 'movement-1',
          title: 'Two-minute stretch',
          description: '',
          type: ActivityType.movement,
          effort: ActivityEffort.low,
          durationMinutes: 2,
          contexts: [],
          targetStates: [],
          review: ActivityReviewMetadata(
            status: ActivityReviewStatus.approved,
            evidenceTier: ActivityEvidenceTier.lifestyle,
            reviewerRole: 'test',
            reviewedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ),
      ]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await suggestionController.warmUp();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfilePage(
          profileController: profileController,
          safetyController: SafetyController(
            screener: const KeywordSafetyScreener(),
            repository: InMemorySafetyEventRepository(),
          ),
          suggestionController: suggestionController,
          sessionController: SessionController(
            repository: InMemorySessionRepository(),
            emotionAnalyzer: const MockEmotionAnalyzer(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('How Solace decides'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileInsightsPage), findsOneWidget);
    expect(find.text('WHAT YOU TOLD US'), findsOneWidget);
  });
}

class _ListLibraryRepository implements ActivityLibraryRepository {
  _ListLibraryRepository(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

void widerPictureTests() {
  group('the wider picture', () {
    testWidgets('lists what else shapes an idea, moments, and what is never used', (
      tester,
    ) async {
      await _pump(tester, _profile());

      for (final title in [
        'WHAT ELSE SHAPES AN IDEA',
        'AFTER YOU TRY SOMETHING',
        'YOUR PHONE PATTERNS',
        'MOMENTS, AND WHAT SOL IS TOLD',
        'NEVER USED',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.textContaining('never a diagnosis'), findsOneWidget);
    });

    testWidgets('says what is true for a person who switched nothing on', (tester) async {
      await _pump(tester, _profile());

      expect(find.textContaining('Off. Solace reads nothing from your phone'), findsOneWidget);
      expect(find.text('No moments are kept right now.'), findsOneWidget);
      expect(find.textContaining('not told anything about you beyond'), findsOneWidget);
      expect(find.text('Sol is not told your moments.'), findsOneWidget);
      // The short-night line only appears when phone patterns are on.
      expect(find.textContaining('A short night'), findsNothing);
    });

    testWidgets('says what is true for a person who switched things on', (tester) async {
      await _pump(
        tester,
        _profile(),
        signals: const DecisionSignals(
          phonePatterns: PhoneSignal.on,
          keptMoments: 3,
          snippetShared: true,
          momentsShared: true,
        ),
      );

      expect(find.textContaining('On. Solace reads screen time'), findsOneWidget);
      expect(find.textContaining('A short night'), findsOneWidget);
      expect(find.text('3 moments are kept, in your own words.'), findsOneWidget);
      expect(find.text('Sol is told a short note about how you like things.'), findsOneWidget);
      expect(find.text('Sol is told your few most recent kept moments.'), findsOneWidget);
    });

    testWidgets('says when access is missing, and uses the singular', (tester) async {
      await _pump(
        tester,
        _profile(),
        signals: const DecisionSignals(
          phonePatterns: PhoneSignal.needsAccess,
          keptMoments: 1,
        ),
      );

      expect(find.textContaining('usage access is off for Solace'), findsOneWidget);
      expect(find.text('1 moment is kept, in your own words.'), findsOneWidget);
    });

    testWidgets('promises nothing about emotion reading, and judges nothing', (tester) async {
      await _pump(tester, _profile());

      expect(find.textContaining('placeholders and shape nothing'), findsOneWidget);
      for (final word in ['too much', 'addict', 'unhealthy', 'diagnose you']) {
        expect(
          find.textContaining(RegExp(word, caseSensitive: false)),
          findsNothing,
          reason: '"$word" would be a judgement',
        );
      }
    });
  });
}
