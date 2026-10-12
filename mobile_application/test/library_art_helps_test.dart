import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/domain/insights/what_helped.dart';
import 'package:solace_mobile/domain/library/activity_stats.dart';
import 'package:solace_mobile/features/art/activity_art.dart';
import 'package:solace_mobile/features/art/checkin_art.dart';
import 'package:solace_mobile/features/library/activity_library_page.dart';

SuggestionRecord _rec(
  String id,
  String activity, {
  bool? done,
  String? before,
  String? after,
  int? rating,
  SuggestionStatus status = SuggestionStatus.shown,
  DateTime? at,
}) =>
    SuggestionRecord(
      id: id,
      activityId: activity,
      shownAt: at ?? DateTime(2026, 10, 10),
      contextTags: const [],
      status: status,
      done: done,
      moodBefore: before,
      moodAfter: after,
      rating: rating,
    );

Activity _act(String id, ActivityType type) => Activity(
      id: id,
      title: id,
      description: '',
      type: type,
      effort: ActivityEffort.low,
      durationMinutes: 5,
      contexts: const [],
      targetStates: const [],
      review: ActivityReviewMetadata(
        status: ActivityReviewStatus.approved,
        evidenceTier: ActivityEvidenceTier.lifestyle,
        reviewerRole: 't',
        reviewedAt: DateTime(2026, 1, 1),
      ),
    );

void main() {
  group('what the history says about one activity', () {
    test('counts offers, doing, skipping, ratings and how it felt afterwards', () {
      final stats = ActivityStats.byActivity([
        _rec('1', 'walk', done: true, before: 'Wobbly', after: 'Steady', rating: 5, at: DateTime(2026, 10, 1)),
        _rec('2', 'walk', done: true, before: 'Steady', after: 'Steady', rating: 3, at: DateTime(2026, 10, 8)),
        _rec('3', 'walk', status: SuggestionStatus.skipped),
        _rec('4', 'walk', done: true, before: 'Steady', after: 'Wobbly'),
        _rec('5', 'read', done: true),
      ]);
      final walk = stats['walk']!;
      expect(walk.offered, 4);
      expect(walk.done, 3);
      expect(walk.skipped, 1);
      expect(walk.ratedCount, 2);
      expect(walk.averageRating, 4.0);
      expect(walk.lighter, 1);
      expect(walk.same, 1);
      expect(walk.heavier, 1);
      expect(walk.feltAfter['Steady'], 2);
      expect(walk.lastDone, DateTime(2026, 10, 10));
      expect(stats['read']!.compared, 0); // no mood words: it says nothing, never "no change"
      expect(stats['nothing'], isNull);
    });
  });

  group('the Helps tab progress', () {
    test('counts only tries with both mood words, per kind', () {
      final library = [_act('walk', ActivityType.movement), _act('read', ActivityType.learning)];
      final progress = helpsProgress([
        _rec('1', 'walk', done: true, before: 'Wobbly', after: 'Steady'),
        _rec('2', 'walk', done: true, before: 'Steady'), // no "after": not counted
        _rec('3', 'walk', done: false, before: 'Steady', after: 'Bright'), // not done: not counted
        _rec('4', 'read', done: true, before: 'Quiet', after: 'Quiet'),
      ], library);
      expect(progress[ActivityType.movement], 1);
      expect(progress[ActivityType.learning], 1);
      expect(progress[ActivityType.nature], 0);
    });
  });

  group('the painted scenes', () {
    testWidgets('every kind of activity and every way to check in draws without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (final type in ActivityType.values) ...[
                  for (final t in [0.0, 0.3, 0.7, 0.99]) SizedBox(width: 120, height: 100, child: ActivityArt(type: type, progress: t, radius: 12)),
                ],
                for (final kind in CheckInKind.values) SizedBox(width: 120, height: 100, child: CheckInArt(kind: kind, progress: 0.5)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('the activity library', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const MaterialApp(home: ActivityLibraryPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the ideas by name, filters by kind, and opens one to show its scene and details', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('library-summary')), findsOneWidget);
      expect(find.text('40'), findsOneWidget); // the whole reviewed catalogue

      await tester.tap(find.byKey(const ValueKey('kind-Move')));
      await tester.pumpAndSettle();
      final tiles = find.byWidgetPredicate((w) {
        final k = w.key;
        if (k is! ValueKey<String>) return false;
        return k.value.startsWith('idea-') && k.value != 'idea-art' && k.value != 'idea-details' && k.value != 'idea-untried';
      });
      expect(tiles, findsWidgets);
      expect(tiles.evaluate().length, lessThan(40));

      await tester.tap(tiles.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('idea-art')), findsOneWidget);
      expect(find.byKey(const ValueKey('idea-details')), findsOneWidget);
      expect(find.byKey(const ValueKey('idea-untried')), findsOneWidget); // no history wired: honest about it

      await tester.tap(tiles.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('idea-art')), findsNothing);
    });
  });
}
