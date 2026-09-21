import '../../core/models/activity.dart';

abstract final class ActivitySafetyPolicy {
  static bool isAllowed(Activity activity) {
    final searchable = [
      activity.title,
      activity.description,
      ...activity.contexts,
      ...activity.targetStates,
    ].join(' ').toLowerCase();
    return !_blockedTerms.any(searchable.contains);
  }

  static const _blockedTerms = [
    'self-harm',
    'self harm',
    'suicide',
    'kill yourself',
    'overdose',
    'cutting yourself',
    'alcohol',
    'cocaine',
    'heroin',
    'cannabis',
    'drug',
    'diagnose',
    'cure',
    'treat depression',
    'stop taking medication',
    'replace therapy',
    'push through pain',
    'maximum effort',
    'no rest',
    'extreme workout',
  ];
}
