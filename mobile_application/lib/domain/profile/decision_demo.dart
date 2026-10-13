import '../../core/models/activity.dart';
import '../capacity/capacity_estimator.dart';
import '../recommendations/recommendation_engine.dart';

/// What the "try it" demo on How Solace decides shows for a pretend situation.
///
/// Reads the engine's own constants rather than restating them, so the demo can
/// not drift from what the picker really does. It illustrates the rules; it is
/// not a forecast of any particular idea.
class DecisionDemo {
  const DecisionDemo({
    required this.capacity,
    required this.recentTooHard,
    required this.avoidedMovement,
  });

  final CapacityLevel capacity;
  final bool recentTooHard;
  final bool avoidedMovement;

  /// The longest an idea may run, or null for no cap.
  int? get maxMinutes => switch (capacity) {
    CapacityLevel.low => RecommendationEngine.lowCapacityMaxMinutes,
    CapacityLevel.medium => RecommendationEngine.mediumCapacityMaxMinutes,
    _ => null,
  };

  /// Whether ideas are held to the lowest effort.
  bool get gentleEffortOnly => recentTooHard || capacity == CapacityLevel.low;

  /// Whether the kinds that ask least are leaned towards.
  bool get leansGentleKinds => capacity == CapacityLevel.low;

  /// The kinds that stay in play, in a fixed order.
  List<ActivityType> get kindsInPlay {
    final all = [...ActivityType.values];
    if (avoidedMovement) all.remove(ActivityType.movement);
    return all;
  }

  /// Kinds given a small lean at the moment.
  Set<ActivityType> get leaned =>
      leansGentleKinds ? RecommendationEngine.gentleTypes : const {};
}
