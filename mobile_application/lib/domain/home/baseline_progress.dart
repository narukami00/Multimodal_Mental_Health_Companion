import '../../core/models/user_profile.dart';

/// How much of the baseline setup is done.
///
/// A skipped part counts as done: choosing to skip is an answer, not a gap, and
/// nothing here should make someone feel behind for declining a questionnaire.
///
/// This is the single definition, shared by the You page and the Home card, so
/// the two can never disagree about how far along someone is.
class BaselineProgress {
  const BaselineProgress({required this.completed, required this.total});

  factory BaselineProgress.of(UserProfile profile) {
    var completed = profile.preferencesCompleted ? 1 : 0;
    if (profile.erqSComplete || profile.erqSSkipped) completed++;
    if (profile.gad7Complete || profile.gad7Skipped) completed++;
    if (profile.phq9Complete || profile.phq9Skipped) completed++;
    return BaselineProgress(completed: completed, total: totalSteps);
  }

  static const totalSteps = 4;

  final int completed;
  final int total;

  bool get isComplete => completed >= total;

  bool get hasStarted => completed > 0;

  double get fraction => total == 0 ? 1 : (completed / total).clamp(0, 1);

  int get percent => (fraction * 100).round();
}
