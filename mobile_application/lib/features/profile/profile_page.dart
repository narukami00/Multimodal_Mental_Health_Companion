import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/user_profile.dart';
import '../../core/theme/app_theme.dart';
import '../library/activity_library_page.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../suggestions/suggestion_controller.dart';
import '../suggestions/suggestion_page.dart';
import 'baseline_quiz_page.dart';
import 'profile_controller.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.profileController,
    required this.safetyController,
    required this.suggestionController,
    super.key,
  });

  final ProfileController profileController;
  final SafetyController safetyController;
  final SuggestionController suggestionController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profileController,
      builder: (context, _) {
        final profile = profileController.profile;
        final completeCount = _completedBlocks(profile);
        final hasStarted =
            profile.preferencesCompleted ||
            profile.hasPreferences ||
            profile.skippedBlocks.isNotEmpty ||
            profile.erqSAnswers.isNotEmpty ||
            profile.gad7Answers.isNotEmpty ||
            profile.phq9Answers.isNotEmpty;

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.amber, AppColors.coral],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(15),
                      child: Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 3),
                        const Text('Your choices stay yours to revisit.'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.amber,
                          ),
                          const SizedBox(width: 9),
                          Text(
                            'Baseline profile',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        profile.baselineComplete
                            ? 'Your starting point is complete. You can revisit it anytime.'
                            : hasStarted
                            ? 'You are partway through. Nothing is lost when you leave.'
                            : 'A few gentle questions help Solace make better suggestions.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.mutedInk,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: completeCount / 4,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: AppColors.amber.withValues(
                          alpha: 0.16,
                        ),
                        color: AppColors.amber,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$completeCount of 4 sections complete',
                        style: const TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => BaselineQuizPage(
                                profileController: profileController,
                                safetyController: safetyController,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            profile.baselineComplete
                                ? 'Review baseline'
                                : 'Continue baseline',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.tune_rounded, color: AppColors.coral),
                      title: Text('Preferences'),
                      subtitle: Text(
                        'Activities, constraints, tone, and boundaries',
                      ),
                    ),
                    if (profile.preferredActivities.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final preference
                                  in profile.preferredActivities)
                                Chip(label: Text(preference)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.amber,
                  ),
                  title: const Text('Try a gentle idea'),
                  subtitle: const Text(
                    'Optional suggestions with feedback and an easy skip',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SuggestionPage(
                        suggestionController: suggestionController,
                        profileController: profileController,
                        safetyController: safetyController,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.local_library_outlined,
                    color: AppColors.amber,
                  ),
                  title: const Text('Activity library'),
                  subtitle: const Text(
                    'Browse the reviewed lifestyle starter set',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ActivityLibraryPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.support_outlined,
                    color: AppColors.coral,
                  ),
                  title: const Text('Crisis resources & support'),
                  subtitle: const Text(
                    'Always available, without automatic notifications',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SupportResourcesPage(
                        safetyController: safetyController,
                        assessment:
                            safetyController.activeAssessment ??
                            const SafetyAssessment.clear(),
                        regionCode:
                            Localizations.localeOf(context).countryCode ??
                            'GLOBAL',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int _completedBlocks(UserProfile profile) {
    var completed = profile.preferencesCompleted ? 1 : 0;
    if (profile.erqSComplete || profile.erqSSkipped) completed++;
    if (profile.gad7Complete || profile.gad7Skipped) completed++;
    if (profile.phq9Complete || profile.phq9Skipped) completed++;
    return completed;
  }
}
