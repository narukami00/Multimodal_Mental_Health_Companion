import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/user_profile.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import 'profile_controller.dart';
import 'quiz_questions.dart';

class BaselineQuizPage extends StatefulWidget {
  const BaselineQuizPage({
    required this.profileController,
    required this.safetyController,
    super.key,
  });

  final ProfileController profileController;
  final SafetyController safetyController;

  @override
  State<BaselineQuizPage> createState() => _BaselineQuizPageState();
}

class _BaselineQuizPageState extends State<BaselineQuizPage> {
  static const _sectionCount = 4;
  static const _activities = [
    'Movement',
    'Social',
    'Creative',
    'Nature',
    'Mindfulness',
    'Learning',
  ];
  static const _constraints = [
    'Short moments',
    'Low energy options',
    'Quiet at home',
    'Limited mobility',
  ];
  static const _interactionPreferences = [
    'Gentle tone',
    'Direct tone',
    'Quiet prompts',
    'More context',
  ];
  static const _neverSuggest = [
    'Exercise',
    'Social activities',
    'Breathing exercises',
    'Journaling',
  ];

  late int _section;
  late int _questionIndex;
  late Set<String> _selectedActivities;
  late Set<String> _selectedConstraints;
  late Set<String> _selectedInteractionPreferences;
  late Set<String> _selectedNeverSuggest;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Sets the page from the saved profile: where to resume, and what is already chosen.
  void _load() {
    final profile = widget.profileController.profile;
    _section = _initialSection(profile);
    _questionIndex = _firstUnanswered(_section, profile);
    _selectedActivities = profile.preferredActivities.toSet();
    _selectedConstraints = profile.constraints.toSet();
    _selectedInteractionPreferences = profile.interactionPreferences.toSet();
    _selectedNeverSuggest = profile.neverSuggest.toSet();
  }

  bool get _anythingAnswered {
    final p = widget.profileController.profile;
    return p.erqSAnswers.isNotEmpty || p.gad7Answers.isNotEmpty || p.phq9Answers.isNotEmpty || p.skippedBlocks.isNotEmpty || p.preferencesCompleted;
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = _section == _sectionCount;
    final colors = SolaceColors.from(context);
    final profile = widget.profileController.profile;
    return Scaffold(
      backgroundColor: colors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          PageHero(
            scene: HeroScene.baseline,
            title: 'Your baseline',
            subtitle: 'A starting point, not a verdict.',
            height: 190,
            trailing: _anythingAnswered
                ? IconButton(
                    key: const ValueKey('baseline-redo'),
                    tooltip: 'Redo the quiz',
                    onPressed: _isSaving ? null : _confirmReset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 21),
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFF8A6B33),
                      backgroundColor: const Color(0xFFFFF6E0),
                      minimumSize: const Size(40, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepStrip(
                  section: _section,
                  profile: profile,
                  furthest: _initialSection(profile),
                  onTap: (i) => setState(() {
                    _section = i;
                    _questionIndex = _firstUnanswered(i, profile);
                  }),
                ),
                const SizedBox(height: 16),
                if (isComplete) _CompletionView(profile: profile, onRedo: _confirmReset, onFits: _editPreferences) else _buildSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection() {
    if (_section == 0) return _buildPreferences();

    final block = _blockForSection(_section);
    final questions = questionsFor(block);
    final question = questions[_questionIndex];
    final answers = answersFor(widget.profileController.profile, block);
    final selectedValue = answers[question.id];

    return Column(
      key: ValueKey('baseline-section-$_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_titleFor(block), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: kitInk)),
        const SizedBox(height: 6),
        Text(_descriptionFor(block), style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: kitSoft)),
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              'Question ${_questionIndex + 1} of ${questions.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.coral),
            ),
            const Spacer(),
            for (var i = 0; i < questions.length; i++)
              Container(
                width: i == _questionIndex ? 16 : 7,
                height: 7,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: answers.containsKey(questions[i].id) || i == _questionIndex ? AppColors.amber : const Color(0xFFEDE4CF),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        KitCard(
          padding: const EdgeInsets.all(20),
          child: Text(question.prompt, style: const TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.w700, color: kitInk)),
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < question.options.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _OptionTile(
              label: question.options[index],
              level: question.options.length <= 1 ? 0 : index / (question.options.length - 1),
              selected: selectedValue == index,
              onTap: _isSaving ? null : () => _chooseOption(block, question, index),
            ),
          ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _isSaving ? null : _skipCurrentSection,
          child: const Text('Skip this section for now'),
        ),
        const Text(
          'Saved as you go. A reflection tool, not a diagnosis.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mutedInk, fontSize: 11, fontWeight: FontWeight.w600, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildPreferences() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('What fits you?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: kitInk)),
        const SizedBox(height: 6),
        const Text('Pick what you may enjoy. You can change these later.', style: TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: kitSoft)),
        const SizedBox(height: 16),
        _PreferenceGroup(
          icon: Icons.directions_walk_rounded,
          color: const Color(0xFFD98A12),
          title: 'Activities you might welcome',
          options: _activities,
          selected: _selectedActivities,
          onChanged: (value) => setState(() => _toggle(_selectedActivities, value)),
        ),
        const SizedBox(height: 12),
        _PreferenceGroup(
          icon: Icons.battery_3_bar_rounded,
          color: const Color(0xFF4F8A52),
          title: 'Helpful constraints',
          options: _constraints,
          selected: _selectedConstraints,
          onChanged: (value) => setState(() => _toggle(_selectedConstraints, value)),
        ),
        const SizedBox(height: 12),
        _PreferenceGroup(
          icon: Icons.record_voice_over_outlined,
          color: const Color(0xFF6E73C8),
          title: 'How should Solace sound?',
          options: _interactionPreferences,
          selected: _selectedInteractionPreferences,
          onChanged: (value) => setState(() => _toggle(_selectedInteractionPreferences, value)),
        ),
        const SizedBox(height: 12),
        _PreferenceGroup(
          icon: Icons.block_rounded,
          color: const Color(0xFFD9674A),
          title: 'Never suggest',
          options: _neverSuggest,
          selected: _selectedNeverSuggest,
          onChanged: (value) => setState(() => _toggle(_selectedNeverSuggest, value)),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _isSaving ? null : _savePreferences,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Continue to questions'),
        ),
        TextButton(
          onPressed: _isSaving ? null : _savePreferences,
          child: const Text('Skip preferences for now'),
        ),
      ],
    );
  }

  Future<void> _savePreferences() async {
    setState(() => _isSaving = true);
    await widget.profileController.savePreferences(
      preferredActivities: _selectedActivities.toList(),
      constraints: _selectedConstraints.toList(),
      interactionPreferences: _selectedInteractionPreferences.toList(),
      neverSuggest: _selectedNeverSuggest.toList(),
    );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _section = _section == 0 ? 1 : _section;
      _questionIndex = _firstUnanswered(
        _section,
        widget.profileController.profile,
      );
    });
  }

  /// From the finished view: back to the "what fits you" step, keeping every answer.
  void _editPreferences() => setState(() {
        _section = 0;
        _questionIndex = 0;
      });

  /// Asks, then clears the quiz so it can be taken again. What fits the person stays unless they choose otherwise.
  Future<void> _confirmReset() async {
    var includePreferences = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Redo the quiz?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your answers and totals are cleared from this phone, and you start the questions again.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('baseline-reset-prefs'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: includePreferences,
                onChanged: (v) => setLocal(() => includePreferences = v ?? false),
                title: const Text('Also clear what fits me', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep my answers')),
            TextButton(
              key: const ValueKey('baseline-reset-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear and redo'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _isSaving = true);
    await widget.profileController.resetBaseline(includePreferences: includePreferences);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _load();
    });
  }

  Future<void> _skipCurrentSection() async {
    setState(() => _isSaving = true);
    await widget.profileController.markBlockSkipped(_blockForSection(_section));
    if (!mounted) return;

    final nextSection = _section + 1;
    setState(() {
      _isSaving = false;
      _section = nextSection;
      _questionIndex = _firstUnanswered(
        _section,
        widget.profileController.profile,
      );
    });
    if (_section == _sectionCount) {
      await widget.profileController.markBaselineComplete();
    }
  }

  Future<void> _chooseOption(
    QuizBlock block,
    QuizQuestion question,
    int value,
  ) async {
    setState(() => _isSaving = true);
    await widget.profileController.saveAnswer(
      block: block,
      questionId: question.id,
      value: value,
    );

    if (block == QuizBlock.phq9 && question.id == 'phq9_9' && value > 0) {
      final assessment = await widget.safetyController.assessSignal(
        source: 'phq9_item_9',
        assessment: const SafetyAssessment(
          level: SafetyLevel.urgentSupport,
          matchedSignals: ['phq9_item_9_nonzero'],
        ),
      );
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SupportResourcesPage(
              safetyController: widget.safetyController,
              profileController: widget.profileController,
              assessment: assessment,
            ),
          ),
        );
      }
    }

    if (!mounted) return;
    final questions = questionsFor(block);
    setState(() {
      _isSaving = false;
      if (_questionIndex < questions.length - 1) {
        _questionIndex++;
      } else if (_section < _sectionCount - 1) {
        _section++;
        _questionIndex = _firstUnanswered(
          _section,
          widget.profileController.profile,
        );
      } else {
        _section = _sectionCount;
      }
    });
    if (_section == _sectionCount) {
      await widget.profileController.markBaselineComplete();
    }
  }

  int _initialSection(UserProfile profile) {
    if (!profile.preferencesCompleted) return 0;
    if (!profile.erqSComplete && !profile.erqSSkipped) return 1;
    if (!profile.gad7Complete && !profile.gad7Skipped) return 2;
    if (!profile.phq9Complete && !profile.phq9Skipped) return 3;
    return _sectionCount;
  }

  int _firstUnanswered(int section, UserProfile profile) {
    if (section == 0 || section == _sectionCount) return 0;
    final block = _blockForSection(section);
    final answers = answersFor(profile, block);
    final questions = questionsFor(block);
    final index = questions.indexWhere(
      (question) => !answers.containsKey(question.id),
    );
    return index == -1 ? 0 : index;
  }

  QuizBlock _blockForSection(int section) {
    return switch (section) {
      1 => QuizBlock.erqS,
      2 => QuizBlock.gad7,
      3 => QuizBlock.phq9,
      _ => QuizBlock.erqS,
    };
  }

  String _titleFor(QuizBlock block) {
    return switch (block) {
      QuizBlock.erqS => 'How do you handle emotions?',
      QuizBlock.gad7 => 'A little about worry',
      QuizBlock.phq9 => 'A little about mood',
    };
  }

  String _descriptionFor(QuizBlock block) {
    return switch (block) {
      QuizBlock.erqS =>
        'There are no right answers. Choose what feels most like you.',
      QuizBlock.gad7 =>
        'Over the last two weeks, how often have you been bothered by each experience?',
      QuizBlock.phq9 =>
        'Over the last two weeks, how often have you been bothered by each experience?',
    };
  }

  void _toggle(Set<String> selected, String value) {
    if (!selected.add(value)) selected.remove(value);
  }
}

/// The four parts of the baseline as a strip: done, skipped, the one you are on, and those still ahead.
/// Tap a part you have already reached to go back to it.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.section, required this.profile, required this.furthest, required this.onTap});

  final int section;
  final UserProfile profile;
  final int furthest;
  final ValueChanged<int> onTap;

  static const _labels = ['Fits you', 'Emotions', 'Worry', 'Mood'];
  static const _icons = [Icons.tune_rounded, Icons.self_improvement_rounded, Icons.cloud_outlined, Icons.wb_twilight_rounded];

  @override
  Widget build(BuildContext context) {
    final skipped = [false, profile.erqSSkipped, profile.gad7Skipped, profile.phq9Skipped];
    return Row(
      key: const ValueKey('baseline-steps'),
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: GestureDetector(
              key: ValueKey('baseline-step-$i'),
              behavior: HitTestBehavior.opaque,
              onTap: i <= furthest && i != section ? () => onTap(i) : null,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < furthest ? (skipped[i] ? const Color(0xFFEDE4CF) : AppColors.amber) : (i == section ? Colors.white : const Color(0xFFF4EEDF)),
                      border: Border.all(color: i == section ? AppColors.amber : Colors.transparent, width: 2.4),
                    ),
                    child: Icon(
                      i < furthest ? (skipped[i] ? Icons.remove_rounded : Icons.check_rounded) : _icons[i],
                      size: 20,
                      color: i < furthest ? (skipped[i] ? kitMuted : Colors.white) : (i == section ? const Color(0xFFB57A12) : kitMuted),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: i == section ? FontWeight.w800 : FontWeight.w600, color: i == section ? kitInk : kitMuted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PreferenceGroup extends StatelessWidget {
  const _PreferenceGroup({
    required this.icon,
    required this.color,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return KitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: icon, color: color, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kitInk))),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (_) => onChanged(option),
                  selectedColor: color.withValues(alpha: 0.22),
                  checkmarkColor: color,
                  side: BorderSide(color: selected.contains(option) ? color : kitLine),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An answer: its words, and a small ring that fills with how strong it is, so the scale reads without reading.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// 0 (least) .. 1 (most) along the answer scale.
  final double level;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? AppColors.amber.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? AppColors.amber : kitLine, width: selected ? 1.8 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: level == 0 ? 0.04 : level,
                        strokeWidth: 4,
                        backgroundColor: const Color(0xFFF1E8D3),
                        color: selected ? AppColors.deepAmber : AppColors.amber,
                      ),
                      if (selected) const Icon(Icons.check_rounded, size: 16, color: AppColors.deepAmber),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kitInk))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({required this.profile, required this.onRedo, required this.onFits});

  final UserProfile profile;
  final VoidCallback onRedo;
  final VoidCallback onFits;

  @override
  Widget build(BuildContext context) {
    final erqScore = scoreFor(profile, QuizBlock.erqS);
    final gadScore = scoreFor(profile, QuizBlock.gad7);
    final phqScore = scoreFor(profile, QuizBlock.phq9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'A useful starting point',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: kitInk),
        ),
        const SizedBox(height: 6),
        const Text(
          'Saved on this device. It helps personalise things; it does not define you or diagnose anything.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: kitSoft),
        ),
        const SizedBox(height: 18),
        KitCard(
          child: Row(
            key: const ValueKey('baseline-scores'),
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ScoreRing(label: 'Emotion regulation', score: erqScore, maximum: 42, color: const Color(0xFF4F8A52)),
              _ScoreRing(label: 'Worry', score: gadScore, maximum: 21, color: const Color(0xFF6E73C8)),
              _ScoreRing(label: 'Mood', score: phqScore, maximum: 27, color: const Color(0xFFD98A12)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('baseline-redo-button'),
          onPressed: onRedo,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Redo the questions'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            foregroundColor: const Color(0xFF96620C),
            side: const BorderSide(color: Color(0xFFE2D6C0)),
          ),
        ),
        TextButton(
          key: const ValueKey('baseline-fits-button'),
          onPressed: onFits,
          child: const Text('Change what fits me'),
        ),
        const SizedBox(height: 6),
        const Text(
          'Private to this phone. Not a clinical result.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mutedInk, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.label, required this.score, required this.maximum, required this.color});

  final String label;
  final int? score;
  final int maximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RingGauge(value: (score ?? 0).toDouble(), max: maximum.toDouble(), centre: score == null ? '—' : '$score', caption: score == null ? null : 'of $maximum', size: 84, color: color),
        const SizedBox(height: 8),
        SizedBox(
          width: 86,
          child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kitSoft)),
        ),
      ],
    );
  }
}
