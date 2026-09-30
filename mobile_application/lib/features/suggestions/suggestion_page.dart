import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/recommendations/recommendation_engine.dart';
import '../app_shell/activity_scene.dart';
import '../app_shell/home_suggestion_card.dart';
import '../profile/baseline_quiz_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../sessions/session_controller.dart';
import 'suggestion_card_surface.dart';
import 'suggestion_context.dart';
import 'suggestion_controller.dart';

class SuggestionPage extends StatefulWidget {
  const SuggestionPage({
    required this.suggestionController,
    required this.profileController,
    required this.safetyController,
    this.sessionController,
    this.seededRecordId,
    this.seededChoice,
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

  /// A suggestion Home peeked at but did not record, so this page can show it
  /// in full before anything is written down.
  ///
  /// Opening this page must not count as having been offered the idea — only
  /// answering does — so the record is created on the first answer instead.
  final SuggestionCardChoice? seededChoice;

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

  /// The suggestion this page is showing when Home peeked at it.
  SuggestionCardChoice? _seeded;

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
    if (widget.seededChoice != null) {
      // Opened by tapping the card: show it in full, record nothing yet.
      _seeded = widget.seededChoice;
      _isLoading = false;
      return;
    }
    _requestSuggestion();
  }

  /// Creates the record for a peeked suggestion, the first time it is answered.
  ///
  /// Reading about an idea is not the same as being offered it, so nothing is
  /// written until the user actually says something.
  Future<bool> _ensureRecord() async {
    if (_currentRecordId != null) return true;
    final seeded = _seeded;
    if (seeded == null) return false;
    await widget.suggestionController.commit(
      seeded.recommendation,
      context: seeded.context,
    );
    return true;
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
    if (!await _ensureRecord()) return;
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
    if (!await _ensureRecord()) return;
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
      // No title. "A gentle idea" told the user nothing, and every step here
      // already has its own heading.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: AnimatedBuilder(
        animation: widget.suggestionController,
        builder: (context, _) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          // A peeked suggestion takes precedence: it is what the user tapped.
          final recommendation = _seeded?.recommendation ??
              widget.suggestionController.current;
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
        // The activity leads, in its own palette and with its own scene, so the
        // page is about one specific thing rather than a generic idea in a
        // block of flat colour.
        _ActivityHeadline(activity: recommendation.activity),
        const SizedBox(height: 18),
        // The reasoning is shown, not folded away. "Why this?" behind a tap is
        // the first thing anyone would want to know and the last thing the
        // layout was offering.
        _WhyThis(
          explanation: recommendation.explanation,
          ink: ActivitySuggestionCard.paletteFor(
            recommendation.activity.type,
          ).ink,
        ),
        const SizedBox(height: 20),
        // Two buttons that hug their own labels rather than two slabs spanning
        // the screen. A full-width pill around three words is 80% empty space.
        Row(
          children: [
            _ActionButton(
              label: 'I did it',
              filled: true,
              onPressed: _didIt,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              label: 'Not today',
              filled: false,
              onPressed: _openNotToday,
            ),
          ],
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
  /// The activity appears once, as a quiet line with its scene — not repeated
  /// in a second full card. Repeating what the user just read was noise.
  Widget _buildRate() {
    final activity = _ratingActivity;
    final palette = activity == null
        ? null
        : ActivitySuggestionCard.paletteFor(activity.type);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
      children: [
        Text(
          'How did it go?',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Entirely optional. Nothing here is required to keep using Solace.',
          style: TextStyle(color: AppColors.mutedInk, height: 1.45),
        ),
        if (activity != null && palette != null) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.wash,
                    border: Border.all(
                      color: palette.ink.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: ActivityScene(
                      type: activity.type,
                      color: palette.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  activity.title,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        _StarRow(value: _rating, onRate: _rate),
        const SizedBox(height: 22),
        TextField(
          controller: _commentController,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Anything worth remembering?',
            hintStyle: const TextStyle(color: AppColors.mutedInk),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: AppColors.mutedInk.withValues(alpha: 0.25)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: AppColors.mutedInk.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.coral, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _skipRating,
            child: const Text('Skip this'),
          ),
        ),
      ],
    );
  }

  /// The activity being rated, whether it came from Home or this page.
  Activity? get _ratingActivity {
    final target = _ratingTarget ?? widget.suggestionController.currentRecord;
    if (target == null) return null;
    return widget.suggestionController.activityFor(target.activityId);
  }
}

/// An action sized to its own label.
///
/// Not a full-width bar: a pill spanning the screen around three words is
/// mostly empty, and reads as a slab rather than as a button.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final base = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(const Size(0, 50)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: base,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: base.copyWith(
        side: WidgetStatePropertyAll(
          BorderSide(color: AppColors.mutedInk.withValues(alpha: 0.35)),
        ),
        foregroundColor: const WidgetStatePropertyAll(AppColors.mutedInk),
      ),
      child: Text(label),
    );
  }
}

/// The activity, leading the page in its own palette with its own scene drawn
/// behind it.
class _ActivityHeadline extends StatelessWidget {
  const _ActivityHeadline({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final palette = ActivitySuggestionCard.paletteFor(activity.type);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.wash,
              Color.lerp(palette.wash, palette.ink, 0.16)!,
            ],
          ),
          border: Border.all(color: palette.ink.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 4,
              top: 6,
              bottom: 6,
              width: 108,
              child: ActivityScene(type: activity.type, color: palette.ink),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      activity.description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.42,
                        fontWeight: FontWeight.w500,
                        color: palette.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Why this particular idea was chosen.
///
/// Always visible rather than folded into an expander: on an app that asks for
/// trust, the reasoning is not a detail behind a tap.
class _WhyThis extends StatelessWidget {
  const _WhyThis({required this.explanation, required this.ink});

  final String explanation;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // An accent rail, so this block is identifiable by shape rather than
          // by being another card.
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(top: 2, right: 13),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why this one',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: ink.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  explanation,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Color(0xFF5C4C36),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Five stars, drawn so their weight can be tuned and so they do not depend on
/// an icon font being present.
class _StarRow extends StatelessWidget {
  const _StarRow({required this.value, required this.onRate});

  final int? value;
  final void Function(int) onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var star = 1; star <= 5; star++)
          GestureDetector(
            key: ValueKey('rating-$star'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onRate(star),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 9),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 160),
                scale: (value ?? 0) >= star ? 1.0 : 0.9,
                child: CustomPaint(
                  size: const Size(40, 40),
                  painter: _StarPainter(
                    filled: (value ?? 0) >= star,
                    active: AppColors.amber,
                    idle: AppColors.mutedInk.withValues(alpha: 0.32),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter({
    required this.filled,
    required this.active,
    required this.idle,
  });

  final bool filled;
  final Color active;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final outer = size.width * 0.46;
    final inner = outer * 0.46;

    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      // Start at the top point rather than the right.
      final angle = (math.pi / 5) * i - math.pi / 2;
      final point = Offset(
        centre.dx + radius * math.cos(angle),
        centre.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    if (filled) {
      canvas.drawPath(path, Paint()..color = active);
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = idle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) {
    return oldDelegate.filled != filled ||
        oldDelegate.active != active ||
        oldDelegate.idle != idle;
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

  /// A short heading for the closing screen, so it is not one line on a blank
  /// page.
  String get headline => switch (this) {
    _Outcome.completedUnrated => 'Good to know you did it',
    _Outcome.ratedUp => 'Noted, thank you',
    _Outcome.ratedDown => 'Thanks for being honest',
    _Outcome.notNow => 'No rush at all',
    _Outcome.notForMe => 'Understood',
    _Outcome.tooHard => 'Thanks for saying',
    _ => 'All set',
  };

  /// What actually changes, described plainly.
  ///
  /// Each line matches a real rule in the engine rather than encouragement:
  /// "not for me" hides the activity for a month, "too much right now" lowers
  /// the effort ceiling for a fortnight.
  String get impact => switch (this) {
    _Outcome.completedUnrated =>
      'A rating is always optional. Nothing else is needed from you.',
    _Outcome.ratedUp => 'That shapes what comes next.',
    _Outcome.ratedDown =>
      'We will look for something that fits you better.',
    _Outcome.notNow => 'This one can come back around another time.',
    _Outcome.notForMe => 'We will leave this one out for a while.',
    _Outcome.tooHard => 'We will keep things gentler for a bit.',
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
    final upbeat = outcome.offersAnother;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A drawn mark rather than a lone heart on an otherwise empty page.
            SizedBox(
              width: 96,
              height: 96,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFF0E8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: CustomPaint(
                    painter: _StarPainter(
                      filled: true,
                      active: AppColors.coral,
                      idle: AppColors.coral,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              outcome.headline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              outcome.impact,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mutedInk,
                height: 1.5,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  label: upbeat ? 'Another idea' : 'Done',
                  filled: true,
                  onPressed: upbeat ? onNext : onDone,
                ),
                const SizedBox(width: 10),
                // The only way out used to be a small close icon in the far
                // corner, which is nowhere near the thumb.
                _ActionButton(
                  label: 'Not now',
                  filled: false,
                  onPressed: onDone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
