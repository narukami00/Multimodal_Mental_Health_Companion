import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/activity.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/models/suggestion_record.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/recommendations/mood_change.dart';
import '../../domain/recommendations/recommendation_engine.dart';
import '../art/activity_art.dart';
import '../insights/mood_tab.dart' show moodColors;
import '../profile/baseline_quiz_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
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

  /// "Would you do it again?" when they answered it: true is yes, false is not really. Never assumed.
  bool? _again;

  bool _saving = false;

  /// Whether the note has already been through the safety check (support is shown once, then they can save).
  bool _noteScreened = false;

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
      _again = null;
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

  /// Whether this is a late review of something done earlier (opened from the quiet "want to say how it
  /// went?" card). How they feel now says nothing about what the idea did, so no mood is paired with it.
  bool get _late => _ratingTarget != null;

  /// Saves the "after" step: how they feel, whether they would do it again, and a note. Every part is
  /// optional and only what was actually given is kept.
  Future<void> _saveFeel() async {
    if (_saving) return;
    final record = _ratingTarget ?? widget.suggestionController.currentRecord;
    if (record == null) return;
    final note = _commentController.text.trim();

    // What they wrote is checked for safety first, the same as everywhere else words are typed in.
    if (note.isNotEmpty && !_noteScreened) {
      final assessment = await widget.safetyController.assessText(source: 'task_note', text: note);
      if (assessment.level != SafetyLevel.clear) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SupportResourcesPage(
              safetyController: widget.safetyController,
              profileController: widget.profileController,
              assessment: assessment,
            ),
          ),
        );
        if (mounted) setState(() => _noteScreened = true);
        return;
      }
    }

    setState(() => _saving = true);
    // How they feel now: the word they picked. With none picked, only a note the model reads clearly
    // as one mood stands in for it; a hint, or no reading, records nothing.
    var mood = _late ? null : _feelNow;
    if (!_late && mood == null && note.isNotEmpty) {
      final reading = await widget.sessionController?.readNote(note);
      if (reading != null && reading.tier == 'clear' && reading.mood != null) {
        mood = Moods.fromReadingMood(reading.mood);
      }
    }
    if (mood != null) {
      await widget.suggestionController.recordMoodAfter(
        recordId: record.id,
        moodAfter: mood,
        moodBefore: moodBeforeForRecord(
          record: record,
          sessions: widget.sessionController?.sessions ?? const [],
        ),
      );
    }
    final again = _again;
    if (again != null || note.isNotEmpty) {
      await widget.suggestionController.recordRating(
        recordId: record.id,
        usefulness: again == null ? null : (again ? SuggestionUsefulness.up : SuggestionUsefulness.down),
        comment: note.isEmpty ? null : note,
      );
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _outcome = again == true
          ? _Outcome.ratedUp
          : again == false
          ? _Outcome.ratedDown
          : (mood != null || note.isNotEmpty)
          ? _Outcome.felt
          : _Outcome.completedUnrated;
      _step = _Step.thanks;
    });
  }

  /// "I did it" was a mis-tap. The record goes back to a plain "not now" so nothing is learned from it.
  Future<void> _notActuallyDone() async {
    final record = _ratingTarget ?? widget.suggestionController.currentRecord;
    if (record == null) return;
    await widget.suggestionController.markNotDone(record.id);
    if (!mounted) return;
    setState(() {
      _outcome = _Outcome.notNow;
      _step = _Step.thanks;
    });
  }

  /// Takes back "I'm resting today", for a mis-tap.
  Future<void> _undoRest() async {
    await widget.profileController.removeRestDay(DateTime.now());
    if (!mounted) return;
    setState(() => _outcome = _Outcome.notNow);
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
    // Resting is the person's own choice and counts as showing up; it says nothing about the idea.
    if (outcome == _Outcome.resting) await widget.profileController.declareRestDay(DateTime.now());
    if (!mounted) return;
    setState(() => _step = _Step.thanks);
  }

  String? get _currentRecordId =>
      widget.suggestionController.currentRecord?.id;

  Future<void> _openNotToday() async {
    final choice = await showModalBottomSheet<_Outcome>(
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
              onTap: () => Navigator.of(context).pop(_Outcome.notNow),
            ),
            ListTile(
              key: const ValueKey('not-today-resting'),
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text("I'm resting today"),
              subtitle: const Text('Marks today as a rest day. Resting counts as showing up.'),
              onTap: () => Navigator.of(context).pop(_Outcome.resting),
            ),
            ListTile(
              leading: const Icon(Icons.do_not_disturb_alt_rounded),
              title: const Text('Not for me'),
              subtitle: const Text("We'll leave this one out for a while."),
              onTap: () => Navigator.of(context).pop(_Outcome.notForMe),
            ),
            ListTile(
              leading: const Icon(Icons.battery_2_bar_rounded),
              title: const Text('Too much right now'),
              subtitle: const Text("We'll keep things gentler for a bit."),
              onTap: () => Navigator.of(context).pop(_Outcome.tooHard),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _dismiss(choice);
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
              onUndoRest: _outcome == _Outcome.resting ? _undoRest : null,
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
                      _again = null;
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
    final hasNote = _commentController.text.trim().isNotEmpty;
    final canSave = _feelNow != null || _again != null || hasNote;
    final reads = widget.sessionController != null && !_late;

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
                _late ? 'How did it go?' : 'How do you feel now?',
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
              Text(
                _late
                    ? 'Everything here is optional.'
                    : 'Pick the word that fits, or write a line. Everything here is optional, and this is how Insights learns what helps you.',
                style: const TextStyle(color: AppColors.mutedInk, height: 1.45, fontSize: 13),
              ),
              if (!_late) ...[
                const SizedBox(height: 16),
                _MoodChips(selected: _feelNow, onSelect: (m) => setState(() => _feelNow = _feelNow == m ? null : m)),
              ],
              const SizedBox(height: 20),
              const Text(
                'Would you do it again?',
                style: TextStyle(color: AppColors.mutedInk, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('again-yes'),
                    label: const Text('Yes, again'),
                    selected: _again == true,
                    onSelected: (_) => setState(() => _again = _again == true ? null : true),
                  ),
                  ChoiceChip(
                    key: const ValueKey('again-no'),
                    label: const Text('Not really'),
                    selected: _again == false,
                    onSelected: (_) => setState(() => _again = _again == false ? null : false),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _commentController,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() => _noteScreened = false),
                decoration: InputDecoration(
                  hintText: 'Anything you want to remember?',
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
              if (reads)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                    "If you don't pick a word, Solace can read one from what you write, when you've allowed that.",
                    style: TextStyle(color: AppColors.mutedInk, fontSize: 11.5, height: 1.4),
                  ),
                ),
              const SizedBox(height: 18),
              _ActionButton(
                label: _saving ? 'Saving…' : 'Save',
                filled: true,
                onPressed: canSave && !_saving ? _saveFeel : null,
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(onPressed: _skipRating, child: const Text('Skip this')),
              ),
              if (!_late)
                Center(
                  child: TextButton(
                    key: const ValueKey('not-actually-done'),
                    onPressed: _notActuallyDone,
                    child: const Text("I didn't actually do this"),
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

/// Where the user is in the flow.
enum _Step { decide, rate, thanks }

/// What they chose, so the closing screen can state what it changed.
enum _Outcome {
  none,
  completed,
  completedUnrated,
  felt,
  ratedUp,
  ratedDown,
  notNow,
  resting,
  notForMe,
  tooHard;

  /// Whether the user said they did the idea, which is what makes "how do you
  /// feel now?" a fair question.
  bool get wasDone => switch (this) {
    _Outcome.completed ||
    _Outcome.completedUnrated ||
    _Outcome.felt ||
    _Outcome.ratedUp ||
    _Outcome.ratedDown => true,
    _ => false,
  };

  SuggestionSkipReason? get skipReason => switch (this) {
    // Resting is "not now" as far as the idea goes: no verdict on it, and it can come back.
    _Outcome.notNow || _Outcome.resting => SuggestionSkipReason.notNow,
    _Outcome.notForMe => SuggestionSkipReason.notForMe,
    _Outcome.tooHard => SuggestionSkipReason.tooHard,
    _ => null,
  };

  /// A short heading for the closing screen, so it is not one line on a blank
  /// page.
  String get headline => switch (this) {
    _Outcome.completedUnrated => 'Good to know you did it',
    _Outcome.felt => 'Thanks for telling me',
    _Outcome.resting => 'Rest is part of it',
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
      'Everything here is optional. Nothing else is needed from you.',
    _Outcome.felt => 'How you feel after things is what Insights learns from.',
    _Outcome.resting => 'Today is marked as a rest day. Resting counts as showing up.',
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
      this == _Outcome.completedUnrated || this == _Outcome.felt || this == _Outcome.ratedUp;
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
    this.onUndoRest,
  });

  final ActivityType type;
  final _Outcome outcome;
  final VoidCallback onNext;
  final VoidCallback onDone;

  /// Shown only after "I'm resting today", to take it back.
  final VoidCallback? onUndoRest;

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
              if (onUndoRest != null) ...[
                const SizedBox(height: 10),
                TextButton(key: const ValueKey('undo-rest'), onPressed: onUndoRest, child: const Text('Undo')),
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

/// The five mood words as tappable chips, in the colours used everywhere else in the app.
class _MoodChips extends StatelessWidget {
  const _MoodChips({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
    );
  }
}
