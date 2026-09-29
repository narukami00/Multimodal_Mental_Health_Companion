import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/user_profile.dart';
import '../../core/theme/app_theme.dart';
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
  late final Set<String> _selectedActivities;
  late final Set<String> _selectedConstraints;
  late final Set<String> _selectedInteractionPreferences;
  late final Set<String> _selectedNeverSuggest;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profileController.profile;
    _section = _initialSection(profile);
    _questionIndex = _firstUnanswered(_section, profile);
    _selectedActivities = profile.preferredActivities.toSet();
    _selectedConstraints = profile.constraints.toSet();
    _selectedInteractionPreferences = profile.interactionPreferences.toSet();
    _selectedNeverSuggest = profile.neverSuggest.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = _section == _sectionCount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your baseline'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: isComplete ? 1 : (_section + 1) / _sectionCount,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor: AppColors.amber.withValues(alpha: 0.16),
                      color: AppColors.amber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isComplete ? 'Done' : '${_section + 1} of $_sectionCount',
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isComplete
                  ? _CompletionView(profile: widget.profileController.profile)
                  : _buildSection(),
            ),
          ],
        ),
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

    return ListView(
      key: ValueKey('baseline-section-$_section'),
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      children: [
        Text(
          _titleFor(block),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _descriptionFor(block),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.mutedInk,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 25),
        Text(
          'Question ${_questionIndex + 1} of ${questions.length}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.coral,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          color: Colors.white.withValues(alpha: 0.78),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              question.prompt,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < question.options.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _OptionTile(
              label: question.options[index],
              selected: selectedValue == index,
              onTap: _isSaving
                  ? null
                  : () => _chooseOption(block, question, index),
            ),
          ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _isSaving ? null : _skipCurrentSection,
          child: const Text('Skip this section for now'),
        ),
        const Text(
          'Your answers are saved as you go. This is a reflection tool, not a diagnosis.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.mutedInk,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildPreferences() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      children: [
        Text(
          'What fits you?',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose what you may enjoy and what Solace should keep in mind. You can change these later.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.mutedInk,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        _PreferenceGroup(
          title: 'Activities you might welcome',
          options: _activities,
          selected: _selectedActivities,
          onChanged: (value) =>
              setState(() => _toggle(_selectedActivities, value)),
        ),
        const SizedBox(height: 21),
        _PreferenceGroup(
          title: 'Helpful constraints',
          options: _constraints,
          selected: _selectedConstraints,
          onChanged: (value) =>
              setState(() => _toggle(_selectedConstraints, value)),
        ),
        const SizedBox(height: 21),
        _PreferenceGroup(
          title: 'How should Solace sound?',
          options: _interactionPreferences,
          selected: _selectedInteractionPreferences,
          onChanged: (value) =>
              setState(() => _toggle(_selectedInteractionPreferences, value)),
        ),
        const SizedBox(height: 21),
        _PreferenceGroup(
          title: 'Never suggest',
          options: _neverSuggest,
          selected: _selectedNeverSuggest,
          onChanged: (value) =>
              setState(() => _toggle(_selectedNeverSuggest, value)),
        ),
        const SizedBox(height: 25),
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

class _PreferenceGroup extends StatelessWidget {
  const _PreferenceGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option),
                selected: selected.contains(option),
                onSelected: (_) => onChanged(option),
                selectedColor: AppColors.amber.withValues(alpha: 0.45),
                checkmarkColor: AppColors.deepAmber,
              ),
          ],
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: selected
          ? AppColors.amber.withValues(alpha: 0.24)
          : Colors.white.withValues(alpha: 0.82),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.deepAmber : AppColors.mutedInk,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final erqScore = scoreFor(profile, QuizBlock.erqS);
    final gadScore = scoreFor(profile, QuizBlock.gad7);
    final phqScore = scoreFor(profile, QuizBlock.phq9);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: AppColors.amber,
          size: 58,
        ),
        const SizedBox(height: 18),
        Text(
          'A useful starting point',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 9),
        const Text(
          'Your baseline is saved on this device. It helps personalize the experience, but it does not define you or diagnose anything.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mutedInk, height: 1.45),
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              _ScoreRow(
                label: 'Emotion regulation reflection',
                score: erqScore,
                maximum: 42,
              ),
              const Divider(height: 1),
              _ScoreRow(
                label: 'Worry reflection',
                score: gadScore,
                maximum: 21,
              ),
              const Divider(height: 1),
              _ScoreRow(label: 'Mood reflection', score: phqScore, maximum: 27),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'These totals are kept as private baseline context. Questionnaire licensing and clinical review are required before external use.',
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
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.score,
    required this.maximum,
  });

  final String label;
  final int? score;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(
        score == null
            ? 'Not scored until this block is complete'
            : 'Baseline reflection',
      ),
      trailing: Text(
        score == null ? '—' : '$score / $maximum',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: AppColors.deepAmber),
      ),
    );
  }
}
