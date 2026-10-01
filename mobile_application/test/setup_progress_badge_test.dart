import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/home/baseline_progress.dart';
import 'package:solace_mobile/features/app_shell/setup_progress_badge.dart';
import 'package:solace_mobile/features/app_shell/today_page.dart';
import 'package:solace_mobile/features/rhythm/week_dots.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';

void main() {
  testWidgets('shows the percent complete and the fill matches it', (tester) async {
    await _pumpBadge(tester, const BaselineProgress(completed: 1, total: 4));

    expect(find.text('Setup · 25%'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.25, 0.001));
  });

  testWidgets('75% done reads 75%, not rounded or reset', (tester) async {
    await _pumpBadge(tester, const BaselineProgress(completed: 3, total: 4));

    expect(find.text('Setup · 75%'), findsOneWidget);
  });

  testWidgets('tapping the meter continues setup', (tester) async {
    var continued = false;
    await _pumpBadge(
      tester,
      const BaselineProgress(completed: 1, total: 4),
      onContinue: () => continued = true,
    );

    await tester.tap(find.text('Setup · 25%'));
    await tester.pump();

    expect(continued, isTrue);
  });

  testWidgets('greeting lines up with the date, week with the meter', (
    tester,
  ) async {
    await _pumpBadge(tester, const BaselineProgress(completed: 2, total: 4));

    final date = find.text(
      MaterialLocalizations.of(
        tester.element(find.byType(SetupProgressBadge)),
      ).formatMediumDate(DateTime(2026, 10, 1)),
    );
    final chip = tester.getRect(
      find.ancestor(of: date, matching: find.byType(Container)).first,
    );
    final greeting = tester.getRect(find.text('Still awake'));
    final badge = tester.getRect(find.byType(SetupProgressBadge));
    final week = tester.getRect(find.byType(WeekDots));

    // First row: greeting and date share a centre line, meter or no meter.
    expect(greeting.center.dy, closeTo(chip.center.dy, 1));
    // Second row: the week and the meter share one, below the first.
    expect(week.center.dy, closeTo(badge.center.dy, 1));
    expect(badge.top, greaterThan(chip.bottom));
    expect(badge.right, closeTo(chip.right, 0.5));
  });

  testWidgets('TodayPage without the slot shows no setup meter', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const TodayPage()),
    );
    await tester.pump();

    expect(find.textContaining('Setup ·'), findsNothing);
  });

  testWidgets('from Home, the meter opens the baseline quiz', (tester) async {
    final repository = InMemoryOnboardingRepository();
    await repository.complete();
    await tester.pumpWidget(
      SolaceApp(
        onboardingRepository: repository,
        sessionController: _testSessionController(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // A fresh profile has finished none of the four setup steps.
    expect(find.text('Setup · 0%'), findsOneWidget);

    await tester.tap(find.text('Setup · 0%'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Your baseline'), findsOneWidget);
  });
}

Future<void> _pumpBadge(
  WidgetTester tester,
  BaselineProgress progress, {
  VoidCallback? onContinue,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: TodayPage(
          currentTime: DateTime(2026, 10, 1),
          weekDots: WeekDots(
            checkedIn: List.filled(7, false),
            rested: List.filled(7, false),
          ),
          setupProgressBadge: SetupProgressBadge(
            progress: progress,
            onContinue: onContinue ?? () {},
          ),
        ),
      ),
    ),
  );
  // The page has ambient animations, so settle by pumping rather than waiting
  // for stillness.
  await tester.pump();
}

SessionController _testSessionController() {
  return SessionController(
    repository: InMemorySessionRepository(),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
}
