import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/rhythm/welcome_back_ladder.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/rhythm/welcome_back_notice.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  group('WelcomeBackLadder', () {
    test('steps up with the length of the gap', () {
      expect(WelcomeBackLadder.tierFor(null), ReturnTier.none);
      expect(WelcomeBackLadder.tierFor(0), ReturnTier.none);
      expect(WelcomeBackLadder.tierFor(2), ReturnTier.none);
      expect(WelcomeBackLadder.tierFor(3), ReturnTier.brief);
      expect(WelcomeBackLadder.tierFor(6), ReturnTier.brief);
      expect(WelcomeBackLadder.tierFor(7), ReturnTier.week);
      expect(WelcomeBackLadder.tierFor(13), ReturnTier.week);
      expect(WelcomeBackLadder.tierFor(14), ReturnTier.longAway);
      expect(WelcomeBackLadder.tierFor(29), ReturnTier.longAway);
      expect(WelcomeBackLadder.tierFor(30), ReturnTier.freshStart);
      expect(WelcomeBackLadder.tierFor(400), ReturnTier.freshStart);
    });

    test('says nothing when nothing should be said', () {
      expect(WelcomeBackLadder.message(ReturnTier.none), isNull);
    });

    test('uses the first name when there is one, and is fine without', () {
      expect(WelcomeBackLadder.message(ReturnTier.brief, name: ' Sam Rivera '), startsWith('Welcome back, Sam.'));
      expect(WelcomeBackLadder.message(ReturnTier.brief, name: '  '), startsWith('Welcome back.'));
      expect(WelcomeBackLadder.message(ReturnTier.brief), startsWith('Welcome back.'));
    });

    test('mentions the paused reminder only for the long gaps, and only when it was paused', () {
      expect(WelcomeBackLadder.message(ReturnTier.longAway, reminderPaused: true), contains('paused'));
      expect(WelcomeBackLadder.message(ReturnTier.freshStart, reminderPaused: true), contains('paused'));
      expect(WelcomeBackLadder.message(ReturnTier.longAway), isNot(contains('paused')));
      expect(WelcomeBackLadder.message(ReturnTier.brief, reminderPaused: true), isNot(contains('paused')));
    });

    test('every welcome stays gentle: no counting, no loss, no urgency', () {
      final banned = RegExp(r'\d|missed|lost|streak|haven.t|should have|behind|at last|finally', caseSensitive: false);
      for (final tier in ReturnTier.values) {
        final text = WelcomeBackLadder.message(tier, name: 'Sam', reminderPaused: true);
        if (text == null) continue;
        expect(banned.hasMatch(text), isFalse, reason: text);
      }
    });

    test('is given once per lapse', () {
      final lastCheckIn = DateTime(2026, 1, 1);
      expect(WelcomeBackLadder.shouldShow(daysSinceLastCheckIn: 2, lastCheckIn: lastCheckIn, lastShownAt: null), isFalse);
      expect(WelcomeBackLadder.shouldShow(daysSinceLastCheckIn: 5, lastCheckIn: lastCheckIn, lastShownAt: null), isTrue);
      expect(WelcomeBackLadder.shouldShow(daysSinceLastCheckIn: 5, lastCheckIn: lastCheckIn, lastShownAt: DateTime(2026, 1, 6)), isFalse);
      // after they check in again and drift away a second time, it can be given again
      expect(WelcomeBackLadder.shouldShow(daysSinceLastCheckIn: 5, lastCheckIn: DateTime(2026, 2, 1), lastShownAt: DateTime(2026, 1, 6)), isTrue);
    });
  });

  group('the welcome on Today', () {
    Future<void> pumpAfter(WidgetTester tester, int days, {String? name, VoidCallback? onOneWord}) async {
      final repository = InMemorySessionRepository();
      await repository.save(SessionRecord(
        id: 'old',
        createdAt: DateTime.now().subtract(Duration(days: days)),
        mode: CaptureMode.text,
        mood: 'Steady',
      ));
      final sessions = SessionController(repository: repository, emotionAnalyzer: const MockEmotionAnalyzer());
      await sessions.load();
      final profile = ProfileController(repository: InMemoryProfileRepository());
      await profile.load();
      if (name != null) await profile.saveIdentity(displayName: name);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: WelcomeBackNotice(sessionController: sessions, profileController: profile, onOneWord: onOneWord)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a few days away gets a light hello, with no mention of a paused reminder', (tester) async {
      await pumpAfter(tester, 4);
      expect(find.textContaining('No catch-up needed'), findsOneWidget);
      expect(find.textContaining('paused'), findsNothing);
    });

    testWidgets('about a week away gets the softer week welcome, by name', (tester) async {
      await pumpAfter(tester, 9, name: 'Sam');
      expect(find.textContaining('Good to see you, Sam'), findsOneWidget);
    });

    testWidgets('a month away is offered a fresh start', (tester) async {
      await pumpAfter(tester, 45);
      expect(find.textContaining('A fresh start'), findsOneWidget);
      expect(find.textContaining('paused'), findsOneWidget);
    });

    testWidgets('the smallest way back in is one tap, when the app offers it', (tester) async {
      var tapped = 0;
      await pumpAfter(tester, 10, onOneWord: () => tapped++);
      await tester.tap(find.byKey(const ValueKey('welcome-back-one-word')));
      expect(tapped, 1);
    });

    testWidgets('without a way in to offer, no button is shown', (tester) async {
      await pumpAfter(tester, 10);
      expect(find.byKey(const ValueKey('welcome-back-one-word')), findsNothing);
    });
  });
}
