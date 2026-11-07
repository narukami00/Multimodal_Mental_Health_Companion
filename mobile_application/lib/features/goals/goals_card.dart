import 'package:flutter/material.dart';

import '../../core/widgets/visual_kit.dart';
import '../../domain/goals/goals.dart';
import 'goals_controller.dart';

/// The goals on the phone page: how the last week went, each goal and how it did, and a gentle way to add, change
/// or remove one. It never scolds: a day that did not go to plan is "not this time", and a goal that is hard is offered
/// an easier number.
class GoalsCard extends StatelessWidget {
  const GoalsCard({required this.goals, super.key});

  final GoalsController goals;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: goals,
      builder: (context, _) {
        return KitCard(
          key: const ValueKey('goals-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconTile(icon: Icons.flag_rounded, color: kitAmber),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Your goals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kitInk)),
                  ),
                  if (goals.hasGoals && goals.goals.length < GoalMeasure.values.length)
                    TextButton(
                      key: const ValueKey('goal-add'),
                      onPressed: () => showGoalSheet(context, goals),
                      child: const Text('Add'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!goals.hasGoals) ..._empty(context) else ..._filled(context),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _empty(BuildContext context) => [
    const Text(
      'Pick something gentle to aim for, like fewer pickups or less late-night screen time. It is looked at the '
      'morning after. Meeting any goal on a day waters your tree once. Missing one takes nothing away.',
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5, color: kitSoft),
    ),
    const SizedBox(height: 12),
    SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey('goal-first'),
        onPressed: () => showGoalSheet(context, goals),
        child: const Text('Set a goal'),
      ),
    ),
  ];

  List<Widget> _filled(BuildContext context) {
    final week = goals.lastWeek;
    final recent = goals.days.length <= 7 ? goals.days : goals.days.sublist(goals.days.length - 7);
    return [
      Text(
        week.judged == 0
            ? 'Nothing to look at yet. Yesterday\'s numbers arrive in the morning.'
            : 'You met a goal on ${week.met} of the last ${week.judged} ${week.judged == 1 ? 'day' : 'days'}.',
        key: const ValueKey('goals-summary'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.4, color: kitInk),
      ),
      if (recent.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [for (final d in recent) _DayDot(day: d)]),
      ],
      const SizedBox(height: 6),
      for (final goal in goals.goals) _GoalTile(goal: goal, goals: goals),
    ];
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day});
  final GoalDay day;

  @override
  Widget build(BuildContext context) {
    final met = day.anyMet;
    final judged = day.judged;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: day.day,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: met ? kitAmber : Colors.transparent,
            border: Border.all(color: met ? kitAmber : (judged ? kitMuted : kitLine), width: 1.6),
          ),
          child: met ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal, required this.goals});

  final Goal goal;
  final GoalsController goals;

  @override
  Widget build(BuildContext context) {
    final yesterday = goals.days.isEmpty ? null : goals.days.last.results[goal.id];
    final offer = goals.adjustmentOffer(goal);
    final line = switch (yesterday?.outcome) {
      GoalOutcome.met => 'Yesterday: ${describeGoalValue(goal.measure, yesterday!.value!)}. Met.',
      GoalOutcome.notThisTime => 'Yesterday: ${describeGoalValue(goal.measure, yesterday!.value!)}. Not this time.',
      GoalOutcome.skipped => 'Yesterday was not counted for this goal.',
      _ => 'Waiting for yesterday\'s numbers.',
    };
    final tone = switch (yesterday?.outcome) {
      GoalOutcome.met => const Color(0xFF3F823B),
      _ => kitSoft,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        key: ValueKey('goal-${goal.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => showGoalSheet(context, goals, existing: goal),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFAF0),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kitLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${goal.measure.title}: ${goal.measure.stem.toLowerCase()} ${describeGoalValue(goal.measure, goal.target)}'
                      '${goal.weekdaysOnly ? ' (weekdays)' : ''}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kitInk),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: kitMuted),
                ],
              ),
              const SizedBox(height: 3),
              Text(line, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4, color: tone)),
              if (offer != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        offer.kind == GoalAdjustmentKind.ease
                            ? 'This one has been hard lately. Want an easier number?'
                            : 'You have kept this one steadily. Want to nudge it a little?',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4, color: kitSoft),
                      ),
                    ),
                    TextButton(
                      key: ValueKey('goal-offer-${goal.id}'),
                      onPressed: () => goals.update(goal.id, target: offer.newTarget),
                      child: Text('Set ${describeGoalValue(goal.measure, offer.newTarget)}'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds a goal, or edits (and can remove) [existing].
Future<void> showGoalSheet(BuildContext context, GoalsController goals, {Goal? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GoalSheet(goals: goals, existing: existing),
  );
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.goals, this.existing});

  final GoalsController goals;
  final Goal? existing;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late GoalMeasure _measure;
  late int _target;
  late bool _weekdays;

  bool get _editing => widget.existing != null;

  /// Measures not already used by another goal (one goal per measure keeps things clear).
  List<GoalMeasure> get _choices => [
    for (final m in GoalMeasure.values)
      if (m == widget.existing?.measure || !widget.goals.goals.any((g) => g.measure == m)) m,
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _measure = existing?.measure ?? _choices.first;
    _target = existing?.target ?? (widget.goals.suggestionFor(_measure) ?? _measure.defaultTarget);
    _weekdays = existing?.weekdaysOnly ?? false;
  }

  void _pick(GoalMeasure m) => setState(() {
    _measure = m;
    _target = widget.goals.suggestionFor(m) ?? m.defaultTarget;
  });

  void _nudge(int direction) => setState(() {
    _target = (_target + direction * _measure.step).clamp(_measure.minTarget, _measure.maxTarget);
  });

  Future<void> _save() async {
    if (_editing) {
      await widget.goals.update(widget.existing!.id, target: _target, weekdaysOnly: _weekdays);
    } else {
      await widget.goals.add(_measure, _target, weekdaysOnly: _weekdays);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    await widget.goals.remove(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = _editing ? null : widget.goals.suggestionFor(_measure);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 4, 22, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_editing ? 'Change this goal' : 'A gentle goal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kitInk)),
              const SizedBox(height: 12),
              if (!_editing)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _choices)
                      ChoiceChip(
                        key: ValueKey('goal-measure-${m.name}'),
                        label: Text(m.title),
                        selected: m == _measure,
                        onSelected: (_) => _pick(m),
                      ),
                  ],
                )
              else
                Text(_measure.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kitInk)),
              const SizedBox(height: 8),
              Text(_measure.explanation, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4, color: kitSoft)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(key: const ValueKey('goal-less'), onPressed: () => _nudge(-1), icon: const Icon(Icons.remove_rounded)),
                  Expanded(
                    child: Column(
                      children: [
                        Text(_measure.stem, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kitMuted)),
                        Text(
                          describeGoalValue(_measure, _target),
                          key: const ValueKey('goal-value'),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kitInk),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(key: const ValueKey('goal-more'), onPressed: () => _nudge(1), icon: const Icon(Icons.add_rounded)),
                ],
              ),
              if (suggestion != null && suggestion != _target)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    key: const ValueKey('goal-use-suggestion'),
                    onPressed: () => setState(() => _target = suggestion),
                    child: Text('A little below your usual: ${describeGoalValue(_measure, suggestion)}'),
                  ),
                ),
              SwitchListTile(
                key: const ValueKey('goal-weekdays'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Weekdays only', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                value: _weekdays,
                onChanged: (v) => setState(() => _weekdays = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(key: const ValueKey('goal-save'), onPressed: _save, child: Text(_editing ? 'Save' : 'Set this goal')),
              ),
              if (_editing)
                Center(
                  child: TextButton(key: const ValueKey('goal-remove'), onPressed: _remove, child: const Text('Remove this goal')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
