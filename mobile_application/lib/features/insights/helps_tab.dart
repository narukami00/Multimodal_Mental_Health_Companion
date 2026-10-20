import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/models/suggestion_record.dart';
import '../../domain/insights/what_helped.dart';
import '../suggestions/suggestion_controller.dart';
import '../art/activity_art.dart';
import 'ideas_invitation_card.dart';
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

/// What the Helps tab's "Want to try something?" card can do, supplied by the app shell (which owns the
/// controllers the idea page needs).
class IdeaActions {
  const IdeaActions({required this.ask, required this.resume, required this.finish, required this.interrupt});

  /// Open the page that asks how they are and offers an idea.
  final VoidCallback ask;

  /// Open the idea they are in the middle of.
  final void Function(SuggestionRecord record) resume;

  /// They are done with it: write the time, then ask how they feel.
  final void Function(SuggestionRecord record) finish;

  /// Something came up: it ends with no verdict.
  final void Function(SuggestionRecord record) interrupt;
}

/// What seemed to help, from how the person said they felt after trying things.
class HelpsTab extends StatelessWidget {
  const HelpsTab({
    required this.suggestionController,
    this.ideaActions,
    this.moodScores = const [],
    this.clock,
    super.key,
  });

  final SuggestionController suggestionController;

  /// Without it there is no "Want to try something?" card.
  final IdeaActions? ideaActions;

  /// Recent daily mood scores, oldest first, which tint the card's scene.
  final List<double> moodScores;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: suggestionController,
      builder: (context, _) {
        final kinds = whatHelped(
          suggestionController.history,
          suggestionController.library,
        );
        final progress = helpsProgress(suggestionController.history, suggestionController.library);
        final invitation = _invitation();
        if (kinds.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?invitation,
              if (invitation != null) const SizedBox(height: 14),
              const InsightCard(
                key: ValueKey('helps-how'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nothing to say yet, and that is fine',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: insightInk),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'It fills in by itself, in three steps:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: insightSoft),
                    ),
                    SizedBox(height: 16),
                    _Step(n: 1, icon: Icons.lightbulb_outline_rounded, title: 'Try an idea', sub: 'From Today, or ask for one above.'),
                    _Step(n: 2, icon: Icons.sentiment_satisfied_alt_rounded, title: 'Say how you feel after', sub: 'One tap on a mood word.'),
                    _Step(n: 3, icon: Icons.auto_graph_rounded, title: 'After three tries of a kind', sub: 'Then what lifted you shows up here.', last: true),
                  ],
                ),
              ),
              const InsightLabel('YOUR PROGRESS'),
              _ProgressGrid(progress: progress),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?invitation,
            if (invitation != null) const SizedBox(height: 14),
            for (final kind in kinds) ...[
              _KindCard(kind: kind),
              const SizedBox(height: 10),
            ],
            const InsightLabel('YOUR PROGRESS'),
            _ProgressGrid(progress: progress),
            const SizedBox(height: 10),
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

  /// The card at the top. With an idea under way it shows that instead, and offers no way to ask for another.
  Widget? _invitation() {
    final actions = ideaActions;
    if (actions == null) return null;
    final now = (clock ?? DateTime.now)();
    final doing = suggestionController.doingNow(now: now);
    final doingActivity = doing == null ? null : suggestionController.activityFor(doing.activityId);
    final tries = suggestionController.history.where((record) => record.done == true).length;
    final scene = IdeaScene.from(now: now, moodScores: moodScores, tries: tries);
    if (doing != null && doingActivity != null) {
      return IdeasInvitationCard(
        scene: scene,
        onStart: () => actions.resume(doing),
        doingTitle: doingActivity.title,
        onResume: () => actions.resume(doing),
        onDone: () => actions.finish(doing),
        onInterrupt: () => actions.interrupt(doing),
      );
    }
    return IdeasInvitationCard(scene: scene, onStart: actions.ask);
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

/// One step of how the tab fills up: a numbered icon on a thread, with a title and a line under it.
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.icon, required this.title, required this.sub, this.last = false});

  final int n;
  final IconData icon;
  final String title;
  final String sub;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFF0CC)),
                  child: Icon(icon, size: 19, color: const Color(0xFFB57A12)),
                ),
                if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: const Color(0xFFF0E2C0))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$n. $title', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: insightInk)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: insightSoft, height: 1.35)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every kind of activity with three dots: one filled per try that has a before and an after, up to the
/// three it waits for. Shows what is still missing instead of leaving the tab blank.
class _ProgressGrid extends StatelessWidget {
  const _ProgressGrid({required this.progress});

  final Map<ActivityType, int> progress;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      key: const ValueKey('helps-progress'),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 12,
        runSpacing: 14,
        children: [
          for (final type in ActivityType.values)
            SizedBox(
              width: 88,
              child: Column(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: ActivityArt(type: type, animate: false, progress: 0.3, circle: true),
                  ),
                  const SizedBox(height: 6),
                  Text(_label(type), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: insightInk)),
                  const SizedBox(height: 4),
                  Row(
                    key: ValueKey('progress-${type.name}'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < (progress[type] ?? 0) ? const Color(0xFFFFB534) : const Color(0xFFEDE4CF),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _label(ActivityType type) => switch (type) {
        ActivityType.movement => 'Move',
        ActivityType.social => 'Connect',
        ActivityType.creative => 'Create',
        ActivityType.nature => 'Outside',
        ActivityType.mindfulness => 'Pause',
        ActivityType.learning => 'Learn',
        ActivityType.productivity => 'Small task',
      };
}
