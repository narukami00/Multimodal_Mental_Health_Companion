import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../domain/insights/what_helped.dart';
import '../suggestions/suggestion_controller.dart';
import 'insight_widgets.dart';

IconData _icon(ActivityType type) => switch (type) {
  ActivityType.movement => Icons.directions_walk_rounded,
  ActivityType.social => Icons.people_alt_rounded,
  ActivityType.creative => Icons.brush_rounded,
  ActivityType.nature => Icons.park_rounded,
  ActivityType.mindfulness => Icons.spa_rounded,
  ActivityType.learning => Icons.menu_book_rounded,
  ActivityType.productivity => Icons.check_circle_outline_rounded,
};

/// What seemed to help, from how the person said they felt after trying things.
class HelpsTab extends StatelessWidget {
  const HelpsTab({required this.suggestionController, super.key});

  final SuggestionController suggestionController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: suggestionController,
      builder: (context, _) {
        final kinds = whatHelped(
          suggestionController.history,
          suggestionController.library,
        );
        if (kinds.isEmpty) {
          return const InsightEmpty(
            icon: Icons.favorite_border_rounded,
            title: 'Nothing to say yet, and that is fine',
            body:
                'When you try an idea and tell Solace how you feel afterwards, '
                'it can show what seemed to lift you. It waits for three tries of '
                'a kind, so it does not read too much into one good day.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final kind in kinds) ...[
              _KindCard(kind: kind),
              const SizedBox(height: 10),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: Text(
                'This is what you reported after trying things. It is not proof '
                'that one thing caused the other.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: insightMuted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({required this.kind});
  final HelpedKind kind;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      key: ValueKey('helped-${kind.type.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon(kind.type), size: 19, color: const Color(0xFFB57A12)),
              ),
              const SizedBox(width: 12),
              Expanded(child: InsightBody(kind.text, strong: true)),
            ],
          ),
          const SizedBox(height: 12),
          // One dot per try, so the weight of the evidence is visible.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < kind.lighter; i++) _dot(const Color(0xFFFFB534)),
              for (var i = 0; i < kind.same; i++) _dot(const Color(0xFFD9CBB0)),
              for (var i = 0; i < kind.heavier; i++) _dot(const Color(0xFFB4ADD6)),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _Key(color: Color(0xFFFFB534), label: 'Lighter'),
              SizedBox(width: 12),
              _Key(color: Color(0xFFD9CBB0), label: 'About the same'),
              SizedBox(width: 12),
              _Key(color: Color(0xFFB4ADD6), label: 'Heavier'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: insightSoft),
      ),
    ],
  );
}
