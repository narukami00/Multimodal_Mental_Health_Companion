import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../exercises/guide_glyph.dart';
import 'insight_widgets.dart';

/// The guided exercises in one place, so one can be started on purpose instead of waiting for it to be suggested.
/// Each row shows a small moving picture of what the exercise does. Starting one is the same as saying yes to any
/// other idea: it is written down as started, and finishing it asks how you feel.
class GuidedExercisesCard extends StatelessWidget {
  const GuidedExercisesCard({required this.activities, required this.onStart, super.key});

  final List<Activity> activities;
  final void Function(Activity activity) onStart;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      key: const ValueKey('guided-exercises'),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE3F2F6), Colors.white],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Guided exercises',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: insightInk),
          ),
          const SizedBox(height: 2),
          const Text(
            'Gentle, a few minutes each. Nothing you write is kept.',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: insightSoft),
          ),
          const SizedBox(height: 8),
          for (final a in activities)
            InkWell(
              key: ValueKey('guided-${a.id}'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => onStart(a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16)),
                      child: Center(child: GuideGlyph(guide: a.guide!, size: 44)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.25, color: insightInk),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'About ${a.durationMinutes} min',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: insightMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: insightMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
