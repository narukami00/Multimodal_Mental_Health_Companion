import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/features/art/activity_art.dart';
import 'package:solace_mobile/features/exercises/guide_glyph.dart';
import 'package:solace_mobile/features/insights/helps_tab.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';

class _Library implements ActivityLibraryRepository {
  const _Library(this.activities);
  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

Activity _activity(String id, {ExerciseGuide? guide}) => Activity(
  id: id,
  title: 'Idea $id',
  description: 'A small thing to try.',
  type: ActivityType.mindfulness,
  effort: ActivityEffort.low,
  durationMinutes: 3,
  contexts: const [],
  targetStates: const [],
  guide: guide,
  review: ActivityReviewMetadata(
    status: ActivityReviewStatus.approved,
    evidenceTier: ActivityEvidenceTier.lifestyle,
    reviewerRole: 'test',
    reviewedAt: DateTime(2026, 1, 1),
  ),
);

void main() {
  Future<SuggestionController> controller() async {
    final c = SuggestionController(
      libraryRepository: _Library([
        _activity('plain'),
        _activity('breath', guide: ExerciseGuide.breathing),
        _activity('ground', guide: ExerciseGuide.grounding),
      ]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await c.load();
    await c.warmUp();
    return c;
  }

  Widget host(SuggestionController c, {void Function(Activity)? start}) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HelpsTab(
          suggestionController: c,
          ideaActions: IdeaActions(
            ask: () {},
            resume: (_) {},
            finish: (_) {},
            interrupt: (_) {},
            startGuided: start,
          ),
        ),
      ),
    ),
  );

  testWidgets('lists only the guided ideas, and tapping one starts it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = await controller();
    Activity? started;
    await tester.pumpWidget(host(c, start: (a) => started = a));
    await tester.pump();

    expect(find.byKey(const ValueKey('guided-exercises')), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-breath')), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-ground')), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-plain')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('guided-breath')));
    expect(started?.id, 'breath');
  });

  testWidgets('no card when the shell offers no way to start one', (tester) async {
    final c = await controller();
    await tester.pumpWidget(host(c));
    await tester.pump();
    expect(find.byKey(const ValueKey('guided-exercises')), findsNothing);
  });

  testWidgets('no card while another idea is under way: one thing at a time', (tester) async {
    final c = await controller();
    final activity = c.library.first;
    final record = await c.commit(
      Recommendation.restored(activity, null),
      context: const RecommendationContext(profileAgeDays: 20),
      fresh: true,
    );
    await c.startDoing(record.id);
    await tester.pumpWidget(host(c, start: (_) {}));
    await tester.pump();
    expect(find.byKey(const ValueKey('guided-exercises')), findsNothing);
  });

  testWidgets('every guide draws its picture, still and mid-loop, without errors', (tester) async {
    final palette = ActivityArt.paletteFor(ActivityType.mindfulness);
    for (final guide in ExerciseGuide.values) {
      for (final t in [0.0, 0.3, 0.7, 0.999]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: CustomPaint(size: const Size(80, 80), painter: GuideGlyphPainter(guide: guide, t: t, palette: palette)),
            ),
          ),
        );
      }
      await tester.pumpWidget(MaterialApp(home: Center(child: GuideGlyph(guide: guide))));
      expect(tester.takeException(), isNull, reason: guide.name);
    }
  });
}
