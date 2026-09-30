import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/rhythm/reminder_lapse_policy.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/rhythm/welcome_back_notice.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  group('ReminderLapsePolicy.daysSince', () {
    test('is null when there has never been a check-in', () {
      expect(ReminderLapsePolicy.daysSince(null), isNull);
    });

    test('counts whole days from the last check-in', () {
      final now = DateTime(2026, 9, 26, 9, 0);

      expect(
        ReminderLapsePolicy.daysSince(DateTime(2026, 9, 26, 7, 0), now: now),
        0,
      );
      expect(
        ReminderLapsePolicy.daysSince(DateTime(2026, 9, 25, 23, 0), now: now),
        1,
      );
      expect(
        ReminderLapsePolicy.daysSince(DateTime(2026, 9, 12), now: now),
        14,
      );
    });
  });

  group('WelcomeBackNotice', () {
    late SessionController sessionController;
    late ProfileController profileController;

    setUp(() {
      sessionController = SessionController(
        repository: InMemorySessionRepository(),
        emotionAnalyzer: const MockEmotionAnalyzer(),
      );
      profileController = ProfileController(
        repository: InMemoryProfileRepository(),
      );
    });

    Future<void> pumpNotice(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: WelcomeBackNotice(
              sessionController: sessionController,
              profileController: profileController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('stays silent while the user is still around', (tester) async {
      await sessionController.saveSession(
        mode: CaptureMode.text,
        mood: 'Steady',
      );
      await profileController.load();

      await pumpNotice(tester);

      expect(find.textContaining('No catch-up needed'), findsNothing);
    });

    testWidgets('stays silent for someone who never started', (tester) async {
      await profileController.load();

      await pumpNotice(tester);

      expect(find.textContaining('No catch-up needed'), findsNothing);
    });

    testWidgets('speaks once after a long gap, naming the paused reminder', (
      tester,
    ) async {
      final repository = InMemorySessionRepository();
      await repository.save(
        SessionRecord(
          id: 'old',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          mode: CaptureMode.text,
          mood: 'Steady',
        ),
      );
      sessionController = SessionController(
        repository: repository,
        emotionAnalyzer: const MockEmotionAnalyzer(),
      );
      await sessionController.load();
      await profileController.load();

      await pumpNotice(tester);

      expect(find.textContaining('No catch-up needed'), findsOneWidget);
      expect(find.textContaining('paused'), findsOneWidget);
      // Marked as shown, so the next launch is quiet.
      expect(profileController.profile.welcomeBackShownAt, isNotNull);
    });

    testWidgets('does not repeat within the same lapse', (tester) async {
      final repository = InMemorySessionRepository();
      await repository.save(
        SessionRecord(
          id: 'old',
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          mode: CaptureMode.text,
          mood: 'Steady',
        ),
      );
      sessionController = SessionController(
        repository: repository,
        emotionAnalyzer: const MockEmotionAnalyzer(),
      );
      await sessionController.load();
      await profileController.load();
      // Already shown during this lapse.
      await profileController.markWelcomeBackShown();

      await pumpNotice(tester);

      expect(find.textContaining('No catch-up needed'), findsNothing);
    });
  });
}
