import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/insights/insights_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

SessionController _controller() => SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: InsightsPage(sessionController: _controller())),
  );
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('renders header, chart card, noticings, and footer', (tester) async {
    await _pump(tester);

    expect(find.text('PATTERNS OVER TIME'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('EMOTIONAL DRIFT'), findsOneWidget);
    expect(find.text('Mornings are easing up'), findsOneWidget);
    expect(find.text('Tender · Steadying'), findsOneWidget);
    expect(find.text('Last 7 days · 6 check-ins'), findsOneWidget);
    expect(find.text('Steady · Tea walk'), findsOneWidget);
    expect(find.text('NOTICINGS'), findsOneWidget);
    expect(find.text('MORNING CHECK-INS'), findsOneWidget);
    expect(find.text('MIDDAY VOICE'), findsOneWidget);
    expect(find.text('EVENING TEXT'), findsOneWidget);
    expect(find.text('GENTLE NOTICING'), findsOneWidget);
    expect(find.text('Explore this moment'), findsOneWidget);
    expect(find.text('Keep it as is'), findsOneWidget);
    expect(
      find.text('Patterns are reflections of what you logged, never clinical conclusions.'),
      findsOneWidget,
    );
  });

  testWidgets('month toggle switches to the 30-day view', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Month'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Last 30 days · 6 check-ins'), findsOneWidget);
    expect(find.text('Steady · Two walks'), findsOneWidget);
  });

  testWidgets('noticing expands to reveal tip and link chip', (tester) async {
    await _pump(tester);

    expect(find.text('Explore breathing practice'), findsNothing);

    await tester.ensureVisible(
      find.text('Stepping into morning light aligns with calmer check-ins later.'),
    );
    await tester.tap(
      find.text('Stepping into morning light aligns with calmer check-ins later.'),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Explore breathing practice'), findsOneWidget);
  });
}
