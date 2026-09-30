import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/recommendations/recommendation_engine.dart';
import '../profile/baseline_quiz_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../sessions/session_controller.dart';
import 'suggestion_context.dart';
import 'suggestion_controller.dart';

class SuggestionPage extends StatefulWidget {
  const SuggestionPage({
    required this.suggestionController,
    required this.profileController,
    required this.safetyController,
    this.sessionController,
    this.seededRecordId,
    super.key,
  });

  final SuggestionController suggestionController;
  final ProfileController profileController;
  final SafetyController safetyController;

  /// Supplies the most recent check-in, which is what the suggestion is
  /// actually chosen from. Optional so the page still works without it.
  final SessionController? sessionController;

  /// A suggestion Home already offered, whose record is already written.
  ///
  /// When set, the page opens straight on the rating step instead of asking for
  /// a suggestion, because asking again would write a second record for the
  /// same thing the user is looking at.
  final String? seededRecordId;

  @override
  State<SuggestionPage> createState() => _SuggestionPageState();
}

class _SuggestionPageState extends State<SuggestionPage> {
  final _commentController = TextEditingController();
  bool _isLoading = true;
  _Step _step = _Step.decide;

  /// Left unset unless the user chooses. A rating is never assumed.
  int? _rating;

  /// What the user just did, so the closing screen can say what changes.
  _Outcome _outcome = _Outcome.none;

  /// The completion being rated when it is not the one on screen.
  SuggestionRecord? _ratingTarget;

  /// Session-only, so declining to rate is not asked again right away.
  bool _ratingPromptDismissed = false;

  @override
  void initState() {
    super.initState();
    if (widget.seededRecordId != null) {
      // Opened from Home for something already offered: the record exists, so
      // go straight to rating it.
      _isLoading = false;
      _outcome = _Outcome.completed;
      _step = _Step.rate;
      return;
    }
    _requestSuggestion();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _requestSuggestion() async {
    setState(() {
      _isLoading = true;
      _rating = null;
      _outcome = _Outcome.none;
      _step = _Step.decide;
      _ratingTarget = null;
    });
    try {
      await widget.suggestionController.suggest(
        profile: widget.profileController.profile,
        // Built from the user's most recent check-in rather than passed empty,
        // which is what previously made every context match zero.
        context: buildRecommendationContext(
          profile: widget.profileController.profile,
          sessions: widget.sessionController?.sessions ?? const [],
        ),
        userInitiated: true,
      );
    } finally {
      // Always clear the spinner: a failed lookup must fall through to the
      // empty state rather than leaving the page loading forever.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// The user did it. Completion is recorded first so that walking away from
  /// the rating step still counts.
  Future<void> _didIt() async {
    await widget.suggestionController.recordCompletion();
    if (!mounted) return;
    setState(() {
      _outcome = _Outcome.completed;
      _step = _Step.rate;
    });
  }

  Future<void> _rate(int stars) async {
    // Four and above helped, two and below did not. Three is neutral and is
    // not recorded as either, because the model has no middle verdict.
    final usefulness = stars >= 4
        ? SuggestionUsefulness.up
        : stars <= 2
        ? SuggestionUsefulness.down
        : null;
    setState(() => _rating = stars);

    final recordId = _ratingTarget?.id ?? _currentRecordId;
    if (recordId != null) {
      await widget.suggestionController.recordRating(
        recordId: recordId,
        usefulness: usefulness,
        rating: stars,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );
    }
    if (!mounted) return;
    setState(() {
      _outcome = usefulness == SuggestionUsefulness.down
          ? _Outcome.ratedDown
          : _Outcome.ratedUp;
      _step = _Step.thanks;
    });
  }

  Future<void> _skipRating() async {
    if (!mounted) return;
    setState(() {
      _commentController.clear();
      _outcome = _Outcome.completedUnrated;
      _step = _Step.thanks;
    });
  }

  Future<void> _dismiss(_Outcome outcome) async {
    setState(() => _outcome = outcome);
    await widget.suggestionController.submitFeedback(
      status: SuggestionStatus.skipped,
      skipReason: outcome.skipReason,
    );
    if (!mounted) return;
    setState(() => _step = _Step.thanks);
  }

  String? get _currentRecordId =>
      widget.suggestionController.currentRecord?.id;

  Future<void> _openNotToday() async {
    final choice = await showModalBottomSheet<SuggestionSkipReason>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Not right now'),
              subtitle: const Text('It can come back around. Nothing is lost.'),
              onTap: () =>
                  Navigator.of(context).pop(SuggestionSkipReason.notNow),
            ),
            ListTile(
              leading: const Icon(Icons.do_not_disturb_alt_rounded),
              title: const Text('Not for me'),
              subtitle: const Text("We'll leave this one out for a while."),
              onTap: () =>
                  Navigator.of(context).pop(SuggestionSkipReason.notForMe),
            ),
            ListTile(
              leading: const Icon(Icons.battery_2_bar_rounded),
              title: const Text('Too much right now'),
              subtitle: const Text("We'll keep things gentler for a bit."),
              onTap: () =>
                  Navigator.of(context).pop(SuggestionSkipReason.tooHard),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _dismiss(switch (choice) {
      SuggestionSkipReason.notNow => _Outcome.notNow,
      SuggestionSkipReason.notForMe => _Outcome.notForMe,
      SuggestionSkipReason.tooHard => _Outcome.tooHard,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('A gentle idea'),
        backgroundColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: widget.suggestionController,
        builder: (context, _) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final recommendation = widget.suggestionController.current;
          if (widget.suggestionController.shouldHelpMeKnowYouBetter) {
            return _FallbackState(
              onRevisit: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BaselineQuizPage(
                    profileController: widget.profileController,
                    safetyController: widget.safetyController,
                  ),
                ),
              ),
            );
          }
          if (recommendation == null) return const _EmptyState();

          return switch (_step) {
            _Step.decide => _buildDecide(context, recommendation),
            _Step.rate => _buildRate(),
            _Step.thanks => _FeedbackThanks(
              outcome: _outcome,
              onNext: _requestSuggestion,
              onDone: () => Navigator.of(context).maybePop(),
            ),
          };
        },
      ),
    );
  }

  /// The two real choices: do it, or not today.
  ///
  /// The reasons behind "not today" live in a menu rather than sitting on
  /// screen, because four visible buttons make a small offer feel like a form.
  Widget _buildDecide(BuildContext context, Recommendation recommendation) {
    final pending = _ratingPromptDismissed
        ? null
        : widget.suggestionController.pendingRating();
    final pendingActivity = pending == null
        ? null
        : widget.suggestionController.activityFor(pending.activityId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      children: [
        if (pending != null && pendingActivity != null) ...[
          _PendingRatingCard(
            title: pendingActivity.title,
            onRate: () => setState(() {
              _ratingTarget = pending;
              _rating = null;
              _step = _Step.rate;
            }),
            onDismiss: () => setState(() => _ratingPromptDismissed = true),
          ),
          const SizedBox(height: 14),
        ],
        Card(
          color: AppColors.amber,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.deepAmber,
                  size: 30,
                ),
                const SizedBox(height: 15),
                Text(
                  recommendation.activity.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.deepAmber,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  recommendation.activity.description,
                  style: const TextStyle(
                    color: AppColors.deepAmber,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  '${recommendation.activity.durationMinutes} minutes · ${_label(recommendation.activity.effort)} effort',
                  style: const TextStyle(
                    color: AppColors.deepAmber,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: ExpansionTile(
            leading: const Icon(
              Icons.help_outline_rounded,
              color: AppColors.coral,
            ),
            title: const Text('Why this?'),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            children: [Text(recommendation.explanation)],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _didIt,
          icon: const Icon(Icons.check_rounded),
          label: const Text('I did it'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _openNotToday,
          child: const Text('Not today'),
        ),
        const SizedBox(height: 14),
        const Text(
          'Suggestions are optional lifestyle ideas, not treatment or medical advice.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.mutedInk,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// How it went, asked only after the user says they did it.
  ///
  /// The activity is shown again here, in full. Rating a bare row of stars with
  /// no reminder of what the idea was gives the user nothing to answer against.
  Widget _buildRate() {
    final activity = _ratingActivity;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      children: [
        if (activity != null) ...[
          Card(
            color: AppColors.amber,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.deepAmber,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activity.description,
                    style: const TextStyle(
                      color: AppColors.deepAmber,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],
        Text(
          'How did it go?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Entirely optional. Nothing here is required to keep using Solace.',
          style: TextStyle(color: AppColors.mutedInk, height: 1.4),
        ),
        const SizedBox(height: 18),
        _buildRatingRow(),
        const SizedBox(height: 18),
        TextField(
          controller: _commentController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Optional note for next time',
            filled: true,
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton(onPressed: _skipRating, child: const Text('Skip')),
      ],
    );
  }

  /// The activity being rated, whether it came from Home or this page.
  Activity? get _ratingActivity {
    final target = _ratingTarget ?? widget.suggestionController.currentRecord;
    if (target == null) return null;
    return widget.suggestionController.activityFor(target.activityId);
  }

  String _label(Enum value) {
    return value.name[0].toUpperCase() + value.name.substring(1);
  }

  /// Optional 1–5 rating, asked only once the user has said they did it.
  ///
  /// Tapping saves straight away: a rating that costs an extra confirmation is
  /// a rating most people will not give.
  Widget _buildRatingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Not at all helpful to very helpful.',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedInk,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (var value = 1; value <= 5; value++) ...[
              if (value > 1) const SizedBox(width: 8),
              GestureDetector(
                key: ValueKey('rating-$value'),
                onTap: () => _rate(value),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (_rating ?? 0) >= value
                        ? AppColors.amber
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (_rating ?? 0) >= value
                          ? AppColors.amber
                          : const Color(0xFFE2D6C0),
                    ),
                  ),
                  child: Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: (_rating ?? 0) >= value
                          ? AppColors.deepAmber
                          : AppColors.mutedInk,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Where the user is in the flow.
enum _Step { decide, rate, thanks }

/// What they chose, so the closing screen can state what it changed.
enum _Outcome {
  none,
  completed,
  completedUnrated,
  ratedUp,
  ratedDown,
  notNow,
  notForMe,
  tooHard;

  SuggestionSkipReason? get skipReason => switch (this) {
    _Outcome.notNow => SuggestionSkipReason.notNow,
    _Outcome.notForMe => SuggestionSkipReason.notForMe,
    _Outcome.tooHard => SuggestionSkipReason.tooHard,
    _ => null,
  };

  /// What actually changes, described plainly.
  ///
  /// Each line matches a real rule in the engine rather than encouragement:
  /// "not for me" hides the activity for a month, "too much right now" lowers
  /// the effort ceiling for a fortnight.
  String get impact => switch (this) {
    _Outcome.completedUnrated =>
      'Good to know you did it. A rating is always optional.',
    _Outcome.ratedUp => 'Noted. That shapes what comes next.',
    _Outcome.ratedDown =>
      'Thanks for being straight with us. We will look for a better fit.',
    _Outcome.notNow => 'No rush. This one can come back around.',
    _Outcome.notForMe => 'Understood. We will leave this one out for a while.',
    _Outcome.tooHard =>
      'Thanks for saying. We will keep things gentler for a bit.',
    _ => 'Nothing was recorded.',
  };

  /// Whether offering another idea is welcome here. After a refusal it would
  /// read as not having listened.
  bool get offersAnother =>
      this == _Outcome.completedUnrated || this == _Outcome.ratedUp;
}

/// A quiet offer to rate something done earlier, never pushed.
class _PendingRatingCard extends StatelessWidget {
  const _PendingRatingCard({
    required this.title,
    required this.onRate,
    required this.onDismiss,
  });

  final String title;
  final VoidCallback onRate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'You did “$title”. Want to say how it went?',
                style: const TextStyle(height: 1.4),
              ),
            ),
            TextButton(onPressed: onRate, child: const Text('Rate')),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Not now',
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackState extends StatelessWidget {
  const _FallbackState({required this.onRevisit});

  final VoidCallback onRevisit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, color: AppColors.amber, size: 48),
            const SizedBox(height: 16),
            Text(
              'Help me know you better',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'A few updated preferences may help future ideas fit better. You can skip this and keep using reflection features.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRevisit,
              child: const Text('Review preferences'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'There is no suggestion to show right now. You can keep reflecting without one.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FeedbackThanks extends StatelessWidget {
  const _FeedbackThanks({
    required this.outcome,
    required this.onNext,
    required this.onDone,
  });

  final _Outcome outcome;
  final VoidCallback onNext;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: AppColors.coral,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Thanks for telling us',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              outcome.impact,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 20),
            if (outcome.offersAnother)
              FilledButton(
                onPressed: onNext,
                child: const Text('Try another idea'),
              )
            else
              FilledButton(onPressed: onDone, child: const Text('Okay')),
          ],
        ),
      ),
    );
  }
}
