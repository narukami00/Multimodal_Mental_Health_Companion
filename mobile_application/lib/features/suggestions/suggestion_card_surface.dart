import '../../core/models/activity.dart';
import '../../domain/recommendations/recommendation_engine.dart';

/// A suggestion offered on Home, held together with the context it was chosen
/// in.
///
/// The peek that produced this is read-only, so nothing is recorded until the
/// user responds. Keeping the context alongside the recommendation means the
/// record can be written exactly as the suggestion was shown, even though the
/// peek itself left no trace.
class SuggestionCardChoice {
  const SuggestionCardChoice({
    required this.recommendation,
    required this.context,
  });

  final Recommendation recommendation;
  final RecommendationContext context;

  Activity get activity => recommendation.activity;
}
