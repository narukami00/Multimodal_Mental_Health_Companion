import '../../core/models/activity.dart';

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
      if (_containsBlockedContent(activity)) {
        issue('contains a blocked recommendation category');
      }
    }

    return ActivityLibraryReview(issues: List.unmodifiable(issues));
  }

  static bool _containsBlockedContent(Activity activity) {
    final searchable = [
      activity.title,
      activity.description,
      ...activity.contexts,
      ...activity.targetStates,
    ].join(' ').toLowerCase();

    return _blockedTerms.any(searchable.contains);
  }

  static const _blockedTerms = [
    // Self-harm and acute-risk adjacent content belongs to the safety layer.
    'self-harm',
    'self harm',
    'suicide',
    'kill yourself',
    'overdose',
    'cutting yourself',
    // Substance use recommendations are not allowed in the first library.
    'alcohol',
    'cocaine',
    'heroin',
    'cannabis',
    'drug',
    // Medical claims or medication instructions require a separate review path.
    'diagnose',
    'cure',
    'treat depression',
    'stop taking medication',
    'replace therapy',
    // Unsafe exertion advice is excluded from the lifestyle starter set.
    'push through pain',
    'maximum effort',
    'no rest',
    'extreme workout',
  ];
}
