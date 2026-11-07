import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/insights/weekly_recap_card.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  late SessionController sessions;
  late ProfileController profile;

  Future<void> pumpCard(WidgetTester tester, DateTime now, VoidCallback onOpen) async {
    final repository = InMemorySessionRepository();
    await repository.save(SessionRecord(id: 'a', createdAt: DateTime(2026, 3, 3, 9), mode: CaptureMode.text, mood: 'Steady'));
    sessions = SessionController(repository: repository, emotionAnalyzer: const MockEmotionAnalyzer());
    await sessions.load();
    profile = ProfileController(repository: InMemoryProfileRepository());
    await profile.load();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: WeeklyRecapCard(sessionController: sessions, profileController: profile, onOpen: onOpen, clock: () => now)),
    ));
    await tester.pump();
  }

  testWidgets('shows on the Monday after a finished week, with one line from the recap', (tester) async {
    await pumpCard(tester, DateTime(2026, 3, 9, 9), () {});
    expect(find.byKey(const ValueKey('recap-card')), findsOneWidget);
    expect(find.text('You checked in on 1 day.'), findsOneWidget);
  });

  testWidgets('tapping opens the weeks and is remembered, so the card is gone', (tester) async {
    var opened = 0;
    await pumpCard(tester, DateTime(2026, 3, 9, 9), () => opened++);
    await tester.tap(find.byKey(const ValueKey('recap-card')));
    await tester.pump();
    expect(opened, 1);
    expect(profile.profile.recapSeenWeek, '2026-03-02');
    expect(find.byKey(const ValueKey('recap-card')), findsNothing);
  });

  testWidgets('dismissing hides it without opening anything', (tester) async {
    var opened = 0;
    await pumpCard(tester, DateTime(2026, 3, 10, 9), () => opened++);
    await tester.tap(find.byKey(const ValueKey('recap-card-dismiss')));
    await tester.pump();
    expect(opened, 0);
    expect(find.byKey(const ValueKey('recap-card')), findsNothing);
  });

  testWidgets('is not there in the middle of the week, or when nothing is to be recapped', (tester) async {
    await pumpCard(tester, DateTime(2026, 3, 14, 9), () {});
    expect(find.byKey(const ValueKey('recap-card')), findsNothing);
  });
}
