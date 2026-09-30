import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/app_shell/home_suggestion_card.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/rhythm/rhythm_detail_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_card_surface.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_page.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';

/// Renders the screens to PNG files so they can actually be looked at.
///
/// Named without a _test suffix so the normal suite does not run it. Run it
/// deliberately, with --update-goldens to write the files:
///   flutter test test/screenshots/render_ui.dart --update-goldens
///
/// This exists because the UI was written for weeks without anyone looking at
/// it, and every review passed anyway. Tests do not tell you whether something
/// looks good.
const _phone = Size(390, 844);

/// Loads a real font. Without this the test environment renders every glyph as
/// a filled box, which makes any screenshot useless for judging.
Future<void> _loadFonts() async {
  const candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    'C:/Windows/Fonts/segoeuib.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  // The app theme asks for Nunito, which is not bundled, so on a device this
  // falls back to the platform font. Registering the system font under that
  // name is what makes the text legible here.
  final loader = FontLoader('Nunito');
  var loaded = 0;
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
    loaded++;
  }
  // ignore: avoid_print
  print('FONTS LOADED: $loaded');
  await loader.load();
}

/// Serves a fixed library so nothing waits on an asset read under fake async.
class _FixedLibrary implements ActivityLibraryRepository {
  const _FixedLibrary(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

/// Renders a whole screen, rather than a single widget.
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: RepaintBoundary(key: const ValueKey('shot'), child: page),
    ),
  );
  await tester.pump();
}

Activity _activity({
  String id = 'walk',
  String title = 'Take a short easy walk',
  String description = 'Walk at a comfortable pace for a few minutes.',
  ActivityType type = ActivityType.movement,
}) {
  return Activity(
    id: id,
    title: title,
    description: description,
    type: type,
    effort: ActivityEffort.low,
    durationMinutes: 5,
    contexts: const [],
    targetStates: const [],
    review: ActivityReviewMetadata(
      status: ActivityReviewStatus.approved,
      evidenceTier: ActivityEvidenceTier.lifestyle,
      reviewerRole: 'test',
      reviewedAt: DateTime(2026, 1, 1),
    ),
  );
}

SuggestionCardChoice _choice({
  String title = 'Take a short easy walk',
  String description = 'Walk at a comfortable pace for a few minutes.',
  ActivityType type = ActivityType.movement,
}) {
  return SuggestionCardChoice(
    recommendation: Recommendation(
      activity: _activity(title: title, description: description, type: type),
      confidence: 0,
      isProactive: true,
      explanation: 'A gentle starter idea.',
      source: SuggestionSource.starter,
    ),
    context: const RecommendationContext(profileAgeDays: 3),
  );
}

/// Captures the widget to a PNG.
///
/// Uses the golden machinery rather than painting to an image directly: the
/// latter hung after one capture, and this is the path Flutter actually
/// supports. Run with --update-goldens to write the files.
Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(const ValueKey('shot')),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Color background = const Color(0xFFF7F1E7),
  double? height,
}) async {
  tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // A Scaffold, because without a Material ancestor the themed text style
      // never reaches the text and everything falls back to the test font.
      home: Scaffold(
        backgroundColor: background,
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _phone.width,
            height: height,
            // A ListView, like Home really is, so the card is laid out under
            // the same constraints it gets in the app.
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
              children: [
                RepaintBoundary(
                  key: const ValueKey('shot'),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('render the suggestion card', (tester) async {
    await _pump(
      tester,
      HomeSuggestionCard(choice: _choice(), onAccept: (_) {}),
    );
    await _capture(tester, 'card_movement');
  });

  testWidgets('render a mindfulness card', (tester) async {
    await _pump(
      tester,
      HomeSuggestionCard(
        choice: _choice(
          title: 'Make a one-minute pause',
          description:
              'Set a gentle timer for one minute and notice what changes in your attention while you wait.',
          type: ActivityType.mindfulness,
        ),
        onAccept: (_) {},
      ),
    );
    await _capture(tester, 'card_mindfulness');
  });

  testWidgets('render a productivity card', (tester) async {
    await _pump(
      tester,
      HomeSuggestionCard(
        choice: _choice(
          title: 'Create a softer stopping point',
          description:
              'Choose where to pause a task and write one sentence that makes restarting easier later.',
          type: ActivityType.productivity,
        ),
        onAccept: (_) {},
      ),
    );
    await _capture(tester, 'card_productivity');
  });

  testWidgets('render the rating step', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _FixedLibrary([
        _activity(
          title: 'Create a softer stopping point',
          description:
              'Choose where to pause a task and write one sentence that makes restarting easier later.',
          type: ActivityType.productivity,
        ),
      ]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();
    final peeked = controller.peek(
      profile: const UserProfile(),
      context: const RecommendationContext(profileAgeDays: 3),
    )!;
    final record = await controller.commit(
      peeked,
      context: const RecommendationContext(profileAgeDays: 3),
    );

    await _pumpPage(
      tester,
      SuggestionPage(
        suggestionController: controller,
        profileController: ProfileController(
          repository: InMemoryProfileRepository(),
        ),
        safetyController: SafetyController(
          screener: const KeywordSafetyScreener(),
          repository: InMemorySafetyEventRepository(),
        ),
        seededRecordId: record.id,
      ),
    );
    await _capture(tester, 'page_rating');
  });

  testWidgets('render the decide step', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _FixedLibrary([
        _activity(
          title: 'Create a softer stopping point',
          description:
              'Choose where to pause a task and write one sentence that makes restarting easier later.',
          type: ActivityType.productivity,
        ),
      ]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpPage(
      tester,
      SuggestionPage(
        suggestionController: controller,
        profileController: ProfileController(
          repository: InMemoryProfileRepository(),
        ),
        safetyController: SafetyController(
          screener: const KeywordSafetyScreener(),
          repository: InMemorySafetyEventRepository(),
        ),
      ),
    );
    // The page requests its suggestion asynchronously, so pump a few frames.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, 'page_decide');
  });

  testWidgets('render the whole Home screen', (tester) async {
    final sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessions.load();
    await sessions.seedInitialSessions();

    final controller = SuggestionController(
      libraryRepository: AssetActivityLibraryRepository(),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    final onboarding = InMemoryOnboardingRepository();
    await onboarding.complete();

    tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: SolaceApp(
          onboardingRepository: onboarding,
          sessionController: sessions,
          suggestionController: controller,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, 'home_full');
  });

  testWidgets('render the rhythm detail page', (tester) async {
    final sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessions.load();
    await sessions.seedInitialSessions();

    final controller = SuggestionController(
      libraryRepository: _FixedLibrary([_activity()]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpPage(
      tester,
      RhythmDetailPage(
        sessionController: sessions,
        profileController: ProfileController(
          repository: InMemoryProfileRepository(),
        ),
        suggestionController: controller,
        libraryRepository: _FixedLibrary([_activity()]),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, 'rhythm_detail');
  });
}
