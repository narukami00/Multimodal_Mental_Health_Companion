import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/navigation/app_tab.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/features/app_shell/app_shell.dart';
import 'package:solace_mobile/features/app_shell/today_page.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  test('TodayPage dynamic greeting matches time of day correctly', () {
    expect(TodayPage.greetingForHour(0), 'Still awake');
    expect(TodayPage.greetingForHour(4), 'Still awake');
    expect(TodayPage.greetingForHour(5), 'Good morning');
    expect(TodayPage.greetingForHour(11), 'Good morning');
    expect(TodayPage.greetingForHour(12), 'Good afternoon');
    expect(TodayPage.greetingForHour(16), 'Good afternoon');
    expect(TodayPage.greetingForHour(17), 'Good evening');
    expect(TodayPage.greetingForHour(23), 'Good evening');
  });

  testWidgets('TodayPage renders dynamic greeting, high-fidelity cards, and footer', (tester) async {
    var checkInTapped = false;
    var supportTapped = false;
    final fixedTime = DateTime(2026, 9, 22, 9, 30); // 9:30 AM -> Good morning

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            currentTime: fixedTime,
            onStartCheckIn: () => checkInTapped = true,
            onOpenSupport: () => supportTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('DAILY CHECK-IN'), findsOneWidget);
    expect(find.text('How does your mind\nfeel right now?'), findsOneWidget);
    expect(find.text('A calm 2-minute space to notice where you are.'), findsOneWidget);
    expect(find.text('Check in now'), findsOneWidget);

    expect(find.text('Talk it through'), findsOneWidget);
    expect(find.text('A quiet space with Sol · voice or text'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    expect(find.textContaining('4 days present'), findsOneWidget);
    expect(find.text('Your pace is enough for today.'), findsOneWidget);
    expect(find.text('Support resources'), findsOneWidget);

    await tester.tap(find.text('Check in now'));
    expect(checkInTapped, isTrue);

    await tester.tap(find.text('Support resources'));
    expect(supportTapped, isTrue);
  });

  testWidgets('AppShell switches tabs smoothly and supports initialTab', (tester) async {
    final sessionController = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    final safetyController = SafetyController(
      screener: const KeywordSafetyScreener(),
      repository: InMemorySafetyEventRepository(),
    );
    final profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
    final suggestionController = SuggestionController(
      libraryRepository: AssetActivityLibraryRepository(),
      suggestionRepository: InMemorySuggestionRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          sessionController: sessionController,
          safetyController: safetyController,
          profileController: profileController,
          suggestionController: suggestionController,
          initialTab: AppTab.journal,
        ),
      ),
    );

    // Initial tab is Journal
    expect(find.text('Journal'), findsNWidgets(2));
    expect(find.text('YOUR DAYS, GENTLY KEPT'), findsOneWidget);

    // Tap on Today tab
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text(TodayPage.greetingForHour(DateTime.now().hour)), findsOneWidget);

    // Tap on Insights tab
    await tester.tap(find.text('Insights').last);
    await tester.pumpAndSettle();
    expect(find.text('PATTERNS OVER TIME'), findsOneWidget);

    // Tap on You tab
    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(find.text('Maya Lin'), findsOneWidget);
  });
}
