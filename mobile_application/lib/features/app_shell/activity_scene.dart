import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../art/activity_art.dart';

/// The illustration for an activity, used on its cards. A thin wrapper over [ActivityArt] (the painted,
/// animated scenes); [color] is kept so existing callers still compile, the scene brings its own palette.
class ActivityScene extends StatelessWidget {
  const ActivityScene({
    required this.type,
    this.color,
    this.animate = true,
    this.radius = 20,
    this.circle = false,
    super.key,
  });

  final ActivityType type;
  final Color? color;
  final bool animate;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) =>
      ActivityArt(type: type, animate: animate, radius: radius, circle: circle);
}
