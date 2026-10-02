import '../../core/models/activity.dart';
import '../../core/models/suggestion_record.dart';
import '../recommendations/mood_change.dart';

/// How often a kind of activity was followed by a lighter mood word, from the
/// person's own answers.
class HelpedKind {
  const HelpedKind({
    required this.type,
    required this.tries,
    required this.lighter,
    required this.same,
    required this.heavier,
  });

  final ActivityType type;

  /// Times they did it and said how they felt afterwards.
  final int tries;
  final int lighter;
  final int same;
  final int heavier;

  /// One plain sentence. It says what they reported, never what caused it.
  String get text {
    final kind = typeName(type);
    if (lighter == tries) return 'After $kind, you said you felt lighter all $tries times.';
    return 'After $kind, you said you felt lighter $lighter of $tries times.';
  }

  static String typeName(ActivityType type) => switch (type) {
    ActivityType.movement => 'moving your body',
    ActivityType.social => 'time with people',
    ActivityType.creative => 'something creative',
    ActivityType.nature => 'time outside',
    ActivityType.mindfulness => 'a moment of stillness',
    ActivityType.learning => 'learning something',
    ActivityType.productivity => 'a small task',
  };
}

/// The kinds of activity with at least [minTries] before-and-after answers and
/// at least one lighter outcome, most reliably lighter first.
///
/// Only records where they said they did it and gave both mood words count. A
/// record without them says nothing: it is never counted as "no change".
List<HelpedKind> whatHelped(
  List<SuggestionRecord> history,
  List<Activity> library, {
  int minTries = 3,
}) {
  final typeOf = {for (final a in library) a.id: a.type};
  final counts = <ActivityType, List<int>>{};
  for (final record in history) {
    if (record.done != true) continue;
    final change = moodChange(record.moodBefore, record.moodAfter);
    final type = typeOf[record.activityId];
    if (change == null || type == null) continue;
    final c = counts.putIfAbsent(type, () => [0, 0, 0, 0]);
    c[0]++;
    if (change >= 0.5) {
      c[1]++;
    } else if (change <= -0.5) {
      c[3]++;
    } else {
      c[2]++;
    }
  }
  final result = [
    for (final e in counts.entries)
      if (e.value[0] >= minTries && e.value[1] > 0)
        HelpedKind(
          type: e.key,
          tries: e.value[0],
          lighter: e.value[1],
          same: e.value[2],
          heavier: e.value[3],
        ),
  ]..sort((a, b) {
      final byShare = (b.lighter / b.tries).compareTo(a.lighter / a.tries);
      return byShare != 0 ? byShare : b.tries.compareTo(a.tries);
    });
  return result;
}
