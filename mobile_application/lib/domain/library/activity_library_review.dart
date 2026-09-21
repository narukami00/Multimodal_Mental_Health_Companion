import '../../core/models/activity.dart';
import '../recommendations/activity_safety_policy.dart';

class ActivityReviewIssue {
  const ActivityReviewIssue({required this.activityId, required this.message});

  final String activityId;
  final String message;

  @override
  String toString() => '$activityId: $message';
}

class ActivityLibraryReview {
  const ActivityLibraryReview({required this.issues});

  final List<ActivityReviewIssue> issues;

  bool get isValid => issues.isEmpty;

  String get summary => issues.map((issue) => issue.toString()).join('\n');

  factory ActivityLibraryReview.validate(Iterable<Activity> activities) {
    final issues = <ActivityReviewIssue>[];
    final seenIds = <String>{};

    for (final activity in activities) {
      void issue(String message) {
        issues.add(
          ActivityReviewIssue(activityId: activity.id, message: message),
        );
      }

      if (activity.id.trim().isEmpty) issue('missing id');
      if (!seenIds.add(activity.id)) issue('duplicate id');
      if (activity.title.trim().isEmpty) issue('missing title');
      if (activity.description.trim().isEmpty) issue('missing description');
      if (activity.durationMinutes < 1 || activity.durationMinutes > 180) {
        issue('duration must be between 1 and 180 minutes');
      }
      if (activity.contexts.isEmpty) issue('at least one context is required');
      if (activity.targetStates.isEmpty) {
        issue('at least one target state is required');
      }
      if (!activity.review.isApprovedForPrototype) {
        issue('entry is not approved for the prototype catalog');
      }
      if (activity.review.reviewerRole.trim().isEmpty) {
        issue('reviewer role is required');
      }
      if (!ActivitySafetyPolicy.isAllowed(activity)) {
        issue('contains a blocked recommendation category');
      }
    }

    return ActivityLibraryReview(issues: List.unmodifiable(issues));
  }

}
