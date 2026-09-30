import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/app_shell/home_suggestion_card.dart';
import 'package:solace_mobile/features/suggestions/suggestion_card_surface.dart';

Activity _activity({
  String id = 'walk',
  ActivityType type = ActivityType.movement,
}) {
  return Activity(
    id: id,
    title: 'Take a five minute walk',
    description: 'A short walk at a comfortable pace.',
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

SuggestionCardChoice _choice({ActivityType type = ActivityType.movement}) {
  return SuggestionCardChoice(
    recommendation: Recommendation(
      activity: _activity(type: type),
      confidence: 0,
      isProactive: true,
      explanation: "A gentle starter idea, since we're just getting to know what fits you.",
      source: SuggestionSource.starter,
    ),
    context: const RecommendationContext(profileAgeDays: 3),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  SuggestionCardChoice? choice,
  void Function(SuggestionCardChoice)? onAccept,
  VoidCallback? onDecline,
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
        body: HomeSuggestionCard(
          choice: choice,
          onAccept: onAccept ?? (_) {},
          onDecline: onDecline,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the sentence and exactly two answers', (tester) async {
    await _pump(tester, choice: _choice());

    expect(find.text('Take a five minute walk'), findsOneWidget);
    expect(find.byKey(const ValueKey('suggestion-accept')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggestion-decline')), findsOneWidget);

    // Nothing else: no eyebrow, no explanation, no third option.
    expect(find.text('I did it'), findsNothing);
    expect(find.text('Not today'), findsNothing);
  });

  testWidgets('renders nothing when nothing is due', (tester) async {
    await _pump(tester);

    expect(find.text('Take a five minute walk'), findsNothing);
    expect(find.byKey(const ValueKey('suggestion-accept')), findsNothing);
  });

  testWidgets('the tick reports the suggestion the user actually saw', (
    tester,
  ) async {
    SuggestionCardChoice? accepted;
    await _pump(
      tester,
      choice: _choice(),
      onAccept: (choice) => accepted = choice,
    );

    await tester.tap(find.byKey(const ValueKey('suggestion-accept')));
    await tester.pump();

    expect(accepted, isNotNull);
    expect(accepted!.activity.id, 'walk');
  });

  testWidgets('the cross says goodbye, then the card closes up', (
    tester,
  ) async {
    var declined = false;
    await _pump(
      tester,
      choice: _choice(),
      onDecline: () => declined = true,
    );

    await tester.tap(find.byKey(const ValueKey('suggestion-decline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(declined, isTrue);
    expect(find.text('Okay, have a nice day.'), findsOneWidget);
    expect(find.text('Take a five minute walk'), findsNothing);

    // Then it goes, and the space it took with it.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Okay, have a nice day.'), findsNothing);
  });

  testWidgets('a suggestion already on screen is not swapped underneath', (
    tester,
  ) async {
    await _pump(tester, choice: _choice());
    expect(find.text('Take a five minute walk'), findsOneWidget);

    // Home rebuilds often. The card must not change what it is offering
    // mid-reach.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSuggestionCard(
            choice: _choice(type: ActivityType.nature),
            onAccept: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Take a five minute walk'), findsOneWidget);
  });
}
