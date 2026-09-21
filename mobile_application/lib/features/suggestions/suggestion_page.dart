import 'package:flutter/material.dart';

import '../../core/models/suggestion_record.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/recommendations/recommendation_engine.dart';
import '../profile/baseline_quiz_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import 'suggestion_controller.dart';

class SuggestionPage extends StatefulWidget {
  const SuggestionPage({
    required this.suggestionController,
    required this.profileController,
    required this.safetyController,
    super.key,
  });

  final SuggestionController suggestionController;
  final ProfileController profileController;
  final SafetyController safetyController;

  @override
  State<SuggestionPage> createState() => _SuggestionPageState();
}

class _SuggestionPageState extends State<SuggestionPage> {
  final _commentController = TextEditingController();
  bool _isLoading = true;
  bool _hasFeedback = false;

  @override
  void initState() {
    super.initState();
    _requestSuggestion();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _requestSuggestion() async {
    setState(() => _isLoading = true);
    await widget.suggestionController.suggest(
      profile: widget.profileController.profile,
      context: const RecommendationContext(),
      userInitiated: true,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasFeedback = false;
    });
  }

  Future<void> _submit(
    SuggestionStatus status, {
    SuggestionSkipReason? reason,
  }) async {
    await widget.suggestionController.submitFeedback(
      status: status,
      skipReason: reason,
      rating: status == SuggestionStatus.completed ? 5 : null,
      comment: _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _hasFeedback = true);
    _commentController.clear();
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
          if (_hasFeedback) {
            return _FeedbackThanks(onNext: _requestSuggestion);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            children: [
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: AppColors.deepAmber),
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
              const SizedBox(height: 16),
              Text(
                'How does this idea feel?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 9),
              TextField(
                controller: _commentController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Optional note for next time',
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _submit(SuggestionStatus.completed),
                icon: const Icon(Icons.check_rounded),
                label: const Text('I tried it'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _submit(
                  SuggestionStatus.skipped,
                  reason: SuggestionSkipReason.notNow,
                ),
                child: const Text('Not now'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _submit(
                        SuggestionStatus.skipped,
                        reason: SuggestionSkipReason.notForMe,
                      ),
                      child: const Text('Not for me'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _submit(
                        SuggestionStatus.skipped,
                        reason: SuggestionSkipReason.tooHard,
                      ),
                      child: const Text('Too hard'),
                    ),
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
        },
      ),
    );
  }

  String _label(Enum value) {
    return value.name[0].toUpperCase() + value.name.substring(1);
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
  const _FeedbackThanks({required this.onNext});

  final VoidCallback onNext;

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
            const Text(
              'Your response helps keep future ideas aligned with you. Nothing is required next.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onNext,
              child: const Text('Try another idea'),
            ),
          ],
        ),
      ),
    );
  }
}
