import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/domain/library/activity_library_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'starter activity asset loads as an approved lifestyle catalog',
    () async {
      final activities = await AssetActivityLibraryRepository().load();

      expect(activities, hasLength(152)); // the 40 starters and the 112 the project owner approved
      expect(
        activities.every(
          (activity) =>
              activity.review.status == ActivityReviewStatus.approved &&
              activity.review.evidenceTier == ActivityEvidenceTier.lifestyle,
        ),
        isTrue,
      );
      expect(activities.map((activity) => activity.id).toSet(), hasLength(152));
    },
  );

  test('review rejects blocked recommendation categories', () {
    final unsafe = Activity(
      id: 'unsafe-001',
      title: 'Push through pain',
      description: 'Use maximum effort and no rest.',
      type: ActivityType.movement,
      effort: ActivityEffort.high,
      durationMinutes: 30,
      contexts: ['home'],
      targetStates: ['steady'],
      review: ActivityReviewMetadata(
        status: ActivityReviewStatus.approved,
        evidenceTier: ActivityEvidenceTier.lifestyle,
        reviewerRole: 'lifestyle_reviewer',
        reviewedAt: DateTime(2026, 9, 22),
      ),
    );

    final review = ActivityLibraryReview.validate([unsafe]);

    expect(review.isValid, isFalse);
    expect(review.summary, contains('blocked recommendation category'));
  });

  test('therapeutic entries require clinician signoff', () {
    final therapeutic = Activity(
      id: 'therapeutic-001',
      title: 'A reviewed therapeutic idea',
      description: 'A description that is not a medical claim.',
      type: ActivityType.mindfulness,
      effort: ActivityEffort.low,
      durationMinutes: 5,
      contexts: ['alone'],
      targetStates: ['quiet'],
      review: ActivityReviewMetadata(
        status: ActivityReviewStatus.approved,
        evidenceTier: ActivityEvidenceTier.therapeutic,
        reviewerRole: 'lifestyle_reviewer',
        reviewedAt: DateTime(2026, 9, 22),
      ),
    );

    expect(ActivityLibraryReview.validate([therapeutic]).isValid, isFalse);
  });
}
