import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/app_description.dart';
import 'package:solace_mobile/core/models/break_annotation.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/usage_event.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_break_annotation_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_consent_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_daily_features_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/features/app_shell/app_shell.dart';
import 'package:solace_mobile/features/consent/consent_controller.dart';
import 'package:solace_mobile/features/footprint/break_prompt_card.dart';
import 'package:solace_mobile/features/footprint/break_prompt_controller.dart';
import 'package:solace_mobile/features/footprint/phone_patterns_controller.dart';
import 'package:solace_mobile/features/profile/phone_patterns_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/usage_collector_service.dart';

String _key(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// A steady person with a two-family shift over the last three finished days.
List<DailyFeatures> _shiftedRows() {
  final random = math.Random(5);
  double gauss() =>
      math.sqrt(-2 * math.log(1 - random.nextDouble())) *
      math.cos(2 * math.pi * random.nextDouble());
  return [
    for (var i = 0; i < 60; i++)
      DailyFeatures(
        dayKey: _key(DateTime(2026, 9, 1 + i)),
        sources: const {'usage', 'usageFinal'},
        screenOnMinutes: (200 + 18 * gauss() + (i >= 57 ? 130 : 0)).round(),
        estimatedSleepStartMinute:
            ((23 * 60 + 30 + 18 * gauss() + (i >= 57 ? 190 : 0)).round()) % 1440,
      ),
  ];
}

final _now = DateTime(2026, 10, 31, 9);

class _NoCollector implements UsageCollectorService {
  @override
  Future<bool> hasAccess() async => false;
  @override
  Future<bool> openAccessSettings() async => true;
  @override
  Future<List<UsageEvent>> events({required DateTime from, required DateTime to}) async =>
      const [];
  @override
  Future<Map<String, AppDescription>> describeApps(List<String> packages) async =>
      const {};
}

void main() {
  late InMemoryBreakAnnotationRepository repository;
  late BreakPromptController controller;
  var shifted = true;

  setUp(() {
    repository = InMemoryBreakAnnotationRepository();
    shifted = true;
    controller = BreakPromptController(
      repository: repository,
      rows: () async => shifted ? _shiftedRows() : const [],
      sessions: () => [
        SessionRecord(
          id: '1',
          createdAt: DateTime(2026, 10, 29, 20),
          mode: CaptureMode.text,
          text: 'So much work and I am tired',
        ),
      ],
      muted: () => false,
      safetyActive: () => false,
      clock: () => _now,
    );
  });

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => BreakPromptCard(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  group('BreakPromptCard', () {
    testWidgets('takes no room when there is nothing to ask', (tester) async {
      shifted = false;
      await pumpCard(tester);

      expect(key('break-prompt'), findsNothing);
      expect(find.text('A GENTLE NOTICING'), findsNothing);
    });

    testWidgets('says what looked different in general terms and asks', (
      tester,
    ) async {
      await pumpCard(tester);

      expect(find.text('A GENTLE NOTICING'), findsOneWidget);
      expect(
        find.text('Your days looked a little different lately.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Over the last few days, how much you have been on your phone and '
          'when your days start and end looked different from your usual. '
          'Anything going on?',
        ),
        findsOneWidget,
      );
    });

    testWidgets('quotes no time, number, app or cause', (tester) async {
      await pumpCard(tester);

      final body = tester.widget<Text>(key('break-prompt-body')).data!;
      expect(RegExp(r'\d').hasMatch(body), isFalse);
      for (final word in ['because', 'caused', 'due to', 'depress', 'anxi', '3am', 'night']) {
        expect(body.toLowerCase(), isNot(contains(word)));
      }
    });

    testWidgets('offers the themes they wrote about first, then the rest', (
      tester,
    ) async {
      await pumpCard(tester);

      final chips = tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((chip) => (chip.label as Text).data)
          .toList();

      expect(chips.take(2).toSet(), {'Work', 'Sleep'});
      expect(chips, containsAll(['People', 'Health', 'Home', 'Money']));
      expect(chips.last, 'Nothing in particular');
    });

    testWidgets('choosing a theme answers and closes the card', (tester) async {
      await pumpCard(tester);

      await tester.tap(key('break-theme-work'));
      await tester.pumpAndSettle();

      expect(key('break-prompt'), findsNothing);
      final saved = (await repository.loadAll()).single;
      expect(saved.status, BreakAnnotationStatus.answered);
      expect(saved.theme, 'work');
    });

    testWidgets('"Nothing in particular" is a complete answer', (tester) async {
      await pumpCard(tester);

      await tester.tap(key('break-nothing'));
      await tester.pumpAndSettle();

      expect(key('break-prompt'), findsNothing);
      final saved = (await repository.loadAll()).single;
      expect(saved.status, BreakAnnotationStatus.answered);
      expect(saved.theme, isNull);
    });

    testWidgets('"Not now" declines and is not asked again', (tester) async {
      await pumpCard(tester);

      await tester.tap(key('break-not-now'));
      await tester.pumpAndSettle();
      await controller.refresh();
      await tester.pumpAndSettle();

      expect(key('break-prompt'), findsNothing);
      expect(
        (await repository.loadAll()).single.status,
        BreakAnnotationStatus.dismissed,
      );
    });

    testWidgets('tells them how to turn it off', (tester) async {
      await pumpCard(tester);

      expect(
        find.text('You can turn these questions off in My phone patterns.'),
        findsOneWidget,
      );
    });
  });

  group('turning it off', () {
    test('is a profile setting that defaults to asking and round-trips', () {
      expect(const UserProfile().patternPromptsMuted, isFalse);

      final restored = UserProfile.fromMap(
        const UserProfile(patternPromptsMuted: true).toMap(),
      );

      expect(restored.patternPromptsMuted, isTrue);
      expect(UserProfile.fromMap(const {}).patternPromptsMuted, isFalse);
    });

    test('the controller changes it', () async {
      final profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();

      await profile.setPatternPromptsMuted(true);
      expect(profile.profile.patternPromptsMuted, isTrue);

      await profile.setPatternPromptsMuted(false);
      expect(profile.profile.patternPromptsMuted, isFalse);
    });

    testWidgets('the switch on My phone patterns is real', (tester) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final consent = ConsentController(repository: InMemoryConsentRepository());
      await consent.load();
      final profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PhonePatternsPage(
            phonePatterns: PhonePatternsController(
              consent: consent,
              collector: _NoCollector(),
              repository: InMemoryDailyFeaturesRepository(),
            ),
            profileController: profile,
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(key('patterns-ask-switch')).value, isTrue);

      await tester.ensureVisible(key('patterns-ask-switch'));
      await tester.tap(key('patterns-ask-switch'));
      await tester.pumpAndSettle();

      expect(profile.profile.patternPromptsMuted, isTrue);
      expect(tester.widget<Switch>(key('patterns-ask-switch')).value, isFalse);
    });
  });

  testWidgets('the Today page shows the question under the rail', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          sessionController: SessionController(
            repository: InMemorySessionRepository(),
            emotionAnalyzer: const MockEmotionAnalyzer(),
          ),
          safetyController: SafetyController(
            screener: const KeywordSafetyScreener(),
            repository: InMemorySafetyEventRepository(),
          ),
          profileController: ProfileController(
            repository: InMemoryProfileRepository(),
          ),
          suggestionController: SuggestionController(
            libraryRepository: AssetActivityLibraryRepository(),
            suggestionRepository: InMemorySuggestionRepository(),
          ),
          breakPrompts: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A GENTLE NOTICING'), findsOneWidget);

    await tester.ensureVisible(key('break-not-now'));
    await tester.tap(key('break-not-now'));
    await tester.pumpAndSettle();

    expect(find.text('A GENTLE NOTICING'), findsNothing);
  });
}
