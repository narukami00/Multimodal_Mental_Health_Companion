import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'tree_geometry.dart';

/// Fixed world regions, each roughly two and a half phone widths across.
/// A region is revealed when the tree extent plus 80% of a viewport reaches it.
const riverRegionWidth = 950.0;
const riverRevealMargin = 304.0;

Iterable<int> riverRegions(double leftTree, double rightTree) sync* {
  final first = math.min(0, ((leftTree - riverRevealMargin) / riverRegionWidth).ceil());
  final last = math.max(0, ((rightTree + riverRevealMargin) / riverRegionWidth).floor());
  for (var index = first; index <= last; index++) {
    yield index;
  }
}

/// A stable channel in terrain coordinates. Y is distance down the landscape.
/// Tree roots are reserved ahead of time, independent of how many are visible.
class ForestRiver {
  ForestRiver(this.region, List<Offset> roots)
      : roots = List.unmodifiable(roots) {
    final random = mulberry32(28181 + region * 7919);
    final originalAnchor = region * riverRegionWidth + 148 + random() * 18;
    final originalPhase = random() * 2 * math.pi;
    bend = 22 + random() * 17;
    frequency = 0.013 + random() * 0.004;
    var bestScore = double.negativeInfinity;
    var bestAnchor = originalAnchor, bestPhase = originalPhase;
    // Pick a whole smooth curve through the reserved terrain. Moving individual
    // points around roots produces visible kinks, especially in distant regions.
    for (var candidate = 0; candidate < 720; candidate++) {
      final radius = (candidate ~/ 24) * 9.0;
      final candidateAnchor = originalAnchor + (candidate.isEven ? radius : -radius);
      final candidatePhase = originalPhase + (candidate % 24) * math.pi / 12;
      var score = double.infinity;
      for (final root in roots) {
        final center = candidateAnchor +
            math.sin((root.dy - 360) * frequency + candidatePhase) * bend +
            math.sin((root.dy - 360) * 0.005 + candidatePhase * 0.7) * 13;
        score = math.min(score, (center - root.dx).abs() -
            halfWidthAt(root.dy) - bankAt(root.dy) - 16);
      }
      if (score > bestScore) {
        bestScore = score;
        bestAnchor = candidateAnchor;
        bestPhase = candidatePhase;
      }
      if (score >= 0) break;
    }
    anchor = bestAnchor;
    phase = bestPhase;
  }

  final int region;
  final List<Offset> roots;
  late final double anchor, phase, bend, frequency;

  double baseAt(double y) =>
      anchor + math.sin((y - 360) * frequency + phase) * bend +
      math.sin((y - 360) * 0.005 + phase * 0.7) * 13;

  double halfWidthAt(double y) =>
      math.min(76, math.max(0.1, y - 358) * 0.083);

  double bankAt(double y) => 17 * smooth(358, 435, y);

  double centerAt(double y) => baseAt(y);

  bool excludes(double x, double y, {double margin = 0}) =>
      (x - centerAt(y)).abs() < halfWidthAt(y) + bankAt(y) + 5 + margin;
}
