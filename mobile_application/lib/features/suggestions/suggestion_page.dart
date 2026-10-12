import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/activity.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/recommendations/mood_change.dart';
import '../../domain/recommendations/recommendation_engine.dart';
import '../art/activity_art.dart';
import '../insights/mood_tab.dart' show moodColors;
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
    this.extraEventTags = const [],
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

  /// Themes the person chose when asked what was going on, to count as context
  /// alongside what they wrote about.
  final List<String> extraEventTags;

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

  /// How they said they feel after doing it, if they said. Never assumed.
  String? _feelNow;

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
      _feelNow = null;
    });
    try {
      await widget.suggestionController.suggest(
        profile: widget.profileController.profile,
        // Built from the user's most recent check-in rather than passed empty,
        // which is what previously made every context match zero.
        context: buildRecommendationContext(
          profile: widget.profileController.profile,
          sessions: widget.sessionController?.sessions ?? const [],
          extraTags: widget.extraEventTags,
        ),
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

  /// Saves how they feel now against the idea they just did, together with the
  /// mood from the check-in before it when there is one close enough.
  Future<void> _recordFeel(String mood) async {
    final record =
        _ratingTarget ?? widget.suggestionController.currentRecord;
    if (record == null) return;
    setState(() => _feelNow = mood);
    await widget.suggestionController.recordMoodAfter(
      recordId: record.id,
      moodAfter: mood,
      moodBefore: moodBeforeFor(
        shownAt: record.shownAt,
        sessions: widget.sessionController?.sessions ?? const [],
      ),
    );
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
      // No title: every step has its own heading. The close button floats over the artwork.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: IconButton.filled(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Close',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.78),
              foregroundColor: const Color(0xFF3A3125),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
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
              type: (_ratingActivity ?? recommendation.activity).type,
              outcome: _outcome,
              onNext: _requestSuggestion,
              onDone: () => Navigator.of(context).maybePop(),
              feelNow: _feelNow,
              onFeel: _outcome.wasDone ? _recordFeel : null,
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
    final activity = recommendation.activity;
    final palette = ActivityArt.paletteFor(activity.type);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Hero(type: activity.type, height: 290),
        // The details card rides up over the artwork.
        Transform.translate(
          offset: const Offset(0, -36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                _DetailsCard(activity: activity, palette: palette),
                if (pending != null && pendingActivity != null) ...[
                  const SizedBox(height: 12),
                  _PendingRatingCard(
                    title: pendingActivity.title,
                    onRate: () => setState(() {
                      _ratingTarget = pending;
                      _rating = null;
                      _step = _Step.rate;
                    }),
                    onDismiss: () => setState(() => _ratingPromptDismissed = true),
                  ),
                ],
                const SizedBox(height: 12),
                _WhyThis(explanation: recommendation.explanation, ink: palette.ink),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _ActionButton(label: 'I did it', filled: true, onPressed: _didIt),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _ActionButton(label: 'Not today', filled: false, onPressed: _openNotToday),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Suggestions are optional lifestyle ideas, not treatment or medical advice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedInk, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 8),
              ],
            ),
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
    final palette = activity == null ? null : ActivityArt.paletteFor(activity.type);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (activity != null) _Hero(type: activity.type, height: 190) else const SizedBox(height: 90),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How did it go?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
              ),
              if (activity != null && palette != null) ...[
                const SizedBox(height: 6),
                Text(
                  activity.title,
                  style: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w700, color: palette.ink),
                ),
              ],
              const SizedBox(height: 4),
              const Text(
                'Entirely optional. Nothing here is required to keep using Solace.',
                style: TextStyle(color: AppColors.mutedInk, height: 1.45, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _StarRow(value: _rating, onRate: _rate),
              const SizedBox(height: 18),
              TextField(
                controller: _commentController,
                minLines: 2,
                maxLines: 4,
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
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _skipRating,
                  child: const Text('Skip this'),
                ),
              ),
            ],
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

/// A pill button: a warm gradient when it is the main answer, a quiet outline otherwise.
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
    final radius = BorderRadius.circular(18);
    if (filled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(colors: [Color(0xFFFFB534), Color(0xFFFF8F5A)]),
          boxShadow: const [BoxShadow(color: Color(0x40FF8F5A), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: AppColors.mutedInk.withValues(alpha: 0.35)),
        foregroundColor: AppColors.mutedInk,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

/// The activity's painted scene across the top of a page, with a soft rounded foot.
class _Hero extends StatelessWidget {
  const _Hero({required this.type, required this.height});

  final ActivityType type;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
        child: ActivityArt(type: type),
      ),
    );
  }
}

String _kindName(ActivityType type) => switch (type) {
      ActivityType.movement => 'MOVE',
      ActivityType.social => 'CONNECT',
      ActivityType.creative => 'CREATE',
      ActivityType.nature => 'OUTSIDE',
      ActivityType.mindfulness => 'PAUSE',
      ActivityType.learning => 'LEARN',
      ActivityType.productivity => 'SMALL TASK',
    };

/// Title, what it is, and how big a thing it is (time and effort), in the scene's own colours.
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.activity, required this.palette});

  final Activity activity;
  final ArtPalette palette;

  @override
  Widget build(BuildContext context) {
    final effort = switch (activity.effort) {
      ActivityEffort.low => 1,
      ActivityEffort.medium => 2,
      ActivityEffort.high => 3,
    };
    final effortWord = switch (activity.effort) {
      ActivityEffort.low => 'Gentle',
      ActivityEffort.medium => 'Some effort',
      ActivityEffort.high => 'More effort',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.a.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: palette.ink.withValues(alpha: 0.16), blurRadius: 26, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: palette.a, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(
                _kindName(activity.type),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: palette.ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            activity.title,
            style: const TextStyle(fontSize: 25, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: Color(0xFF2E2418)),
          ),
          const SizedBox(height: 8),
          Text(
            activity.description,
            style: const TextStyle(fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500, color: Color(0xFF5C4C36)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Fact(
                key: const ValueKey('fact-time'),
                color: palette,
                leading: Icon(Icons.schedule_rounded, size: 15, color: palette.ink),
                label: '${activity.durationMinutes} min',
              ),
              _Fact(
                key: const ValueKey('fact-effort'),
                color: palette,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < effort ? palette.ink : palette.ink.withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ),
                label: effortWord,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.color, required this.leading, required this.label, super.key});

  final ArtPalette color;
  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color.skyTop.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color.ink)),
        ],
      ),
    );
  }
}

/// Why this particular idea was chosen: always visible, because on an app that asks for trust the
/// reasoning is not a detail behind a tap.
class _WhyThis extends StatelessWidget {
  const _WhyThis({required this.explanation, required this.ink});

  final String explanation;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ink.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: ink.withValues(alpha: 0.75)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why this one',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: ink.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 4),
                Text(
                  explanation,
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF5C4C36)),
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

  /// Whether the user said they did the idea, which is what makes "how do you
  /// feel now?" a fair question.
  bool get wasDone => switch (this) {
    _Outcome.completed ||
    _Outcome.completedUnrated ||
    _Outcome.ratedUp ||
    _Outcome.ratedDown => true,
    _ => false,
  };

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
    required this.type,
    required this.outcome,
    required this.onNext,
    required this.onDone,
    this.feelNow,
    this.onFeel,
  });

  final ActivityType type;
  final _Outcome outcome;
  final VoidCallback onNext;
  final VoidCallback onDone;

  /// Offered only after an idea that was done. Null [onFeel] hides it.
  final String? feelNow;
  final ValueChanged<String>? onFeel;

  @override
  Widget build(BuildContext context) {
    final upbeat = outcome.offersAnother;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 56, 26, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Celebrate(type: type, celebrate: outcome.wasDone),
              const SizedBox(height: 26),
              Text(
                outcome.headline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                outcome.impact,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.mutedInk, height: 1.5, fontSize: 14),
              ),
              if (onFeel != null) ...[
                const SizedBox(height: 24),
                _FeelNow(selected: feelNow, onSelect: onFeel!),
              ],
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _ActionButton(
                      label: upbeat ? 'Another idea' : 'Done',
                      filled: true,
                      onPressed: upbeat ? onNext : onDone,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The only way out used to be a small close icon in the far corner, nowhere near the thumb.
                  Expanded(
                    flex: 2,
                    child: _ActionButton(label: 'Not now', filled: false, onPressed: onDone),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The activity's scene in a circle, with a ring that draws itself around it and, after something was
/// done, a small burst of colour. Plays once.
class _Celebrate extends StatefulWidget {
  const _Celebrate({required this.type, required this.celebrate});

  final ActivityType type;
  final bool celebrate;

  @override
  State<_Celebrate> createState() => _CelebrateState();
}

class _CelebrateState extends State<_Celebrate> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ActivityArt.paletteFor(widget.type);
    return SizedBox(
      width: 220,
      height: 190,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _CelebratePainter(t: _c.value, palette: palette, burst: widget.celebrate),
          child: Center(
            child: Transform.scale(
              scale: Curves.easeOutBack.transform((_c.value * 2).clamp(0.0, 1.0)),
              child: SizedBox(width: 132, height: 132, child: ActivityArt(type: widget.type, circle: true)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebratePainter extends CustomPainter {
  _CelebratePainter({required this.t, required this.palette, required this.burst});

  final double t;
  final ArtPalette palette;
  final bool burst;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ring = Curves.easeInOut.transform((t / 0.7).clamp(0.0, 1.0));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 76),
      -math.pi / 2,
      2 * math.pi * ring,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = palette.a,
    );
    if (!burst || t < 0.45) return;
    final k = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    for (var i = 0; i < 14; i++) {
      final angle = i / 14 * 2 * math.pi + 0.2;
      final dist = 82 + 34 * Curves.easeOut.transform(k) + (i % 3) * 6;
      final o = c + Offset(math.cos(angle), math.sin(angle)) * dist;
      canvas.drawCircle(
        o,
        (i.isEven ? 4.5 : 3) * (1 - k * 0.5),
        Paint()..color = [palette.a, palette.b, const Color(0xFFFFB534), palette.c][i % 4].withValues(alpha: 1 - k),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CelebratePainter old) => old.t != t || old.burst != burst;
}

/// A quiet, optional "how do you feel now?" under the closing message.
///
/// One tap on a mood word and it is saved; ignoring it costs nothing. The words wear the same colours
/// as everywhere else in the app.
class _FeelNow extends StatelessWidget {
  const _FeelNow({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          selected == null ? 'How do you feel now?' : 'Noted, thank you.',
          style: const TextStyle(color: AppColors.mutedInk, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mood in Moods.values)
              ChoiceChip(
                key: ValueKey('feel-$mood'),
                avatar: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: moodColors[mood], shape: BoxShape.circle),
                ),
                label: Text(Moods.display(mood)),
                selected: selected == mood,
                showCheckmark: false,
                onSelected: (_) => onSelect(mood),
              ),
          ],
        ),
      ],
    );
  }
}
