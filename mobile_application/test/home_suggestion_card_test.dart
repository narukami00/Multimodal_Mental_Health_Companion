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
  String description = 'A short walk at a comfortable pace.',
}) {
  return Activity(
    id: id,
    title: 'Take a five minute walk',
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
  ActivityType type = ActivityType.movement,
  String description = 'A short walk at a comfortable pace.',
}) {
  return SuggestionCardChoice(
    recommendation: Recommendation(
      activity: _activity(type: type, description: description),
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
  VoidCallback? onVanished,
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
          onVanished: onVanished,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the sentence, what it means, and exactly two answers', (
    tester,
  ) async {
    await _pump(tester, choice: _choice());

    expect(find.text('Take a five minute walk'), findsOneWidget);
    // The subtitle too: naming a task without saying what it involves leaves
    // the user to guess.
    expect(
      find.text('A short walk at a comfortable pace.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('suggestion-accept')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggestion-decline')), findsOneWidget);

    // Nothing else: no eyebrow, no explanation, no third option, and no
    // duration or effort readout.
    expect(find.text('I did it'), findsNothing);
    expect(find.text('Not today'), findsNothing);
    expect(find.textContaining('minutes'), findsNothing);
    expect(find.textContaining('effort'), findsNothing);
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
    var vanished = false;
    await _pump(
      tester,
      choice: _choice(),
      onDecline: () => declined = true,
      onVanished: () => vanished = true,
    );

    await tester.tap(find.byKey(const ValueKey('suggestion-decline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(declined, isTrue);
    expect(find.text('Okay, have a nice day.'), findsOneWidget);
    // Both lines go, not just the title.
    expect(find.text('Take a five minute walk'), findsNothing);
    expect(find.text('A short walk at a comfortable pace.'), findsNothing);
    // Not yet: the goodbye is still on screen.
    expect(vanished, isFalse);

    // Then it goes, and the space it took with it.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Okay, have a nice day.'), findsNothing);
    // And Home is told, so the next one can be brought in.
    expect(vanished, isTrue);
  });

  testWidgets('a long subtitle fits on a small phone', (tester) async {
    // The longest description in the library, at a narrow phone width. With the
    // glyph and both buttons sharing one row this left the text about 140dp,
    // which is not enough for a full sentence.
    const longest =
        'Choose where to pause a task and write one sentence that makes restarting easier later.';

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSuggestionCard(
            choice: _choice(description: longest),
            onAccept: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // A layout overflow would surface here as a thrown exception.
    expect(tester.takeException(), isNull);
    expect(find.text(longest), findsOneWidget);
    expect(find.byKey(const ValueKey('suggestion-accept')), findsOneWidget);
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
