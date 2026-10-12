import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_back_button.dart';
import '../../data/repositories/asset_activity_library_repository.dart';
import '../suggestions/suggestion_controller.dart';

class ActivityLibraryPage extends StatefulWidget {
  const ActivityLibraryPage({this.suggestionController, super.key});

  final SuggestionController? suggestionController;

  @override
  State<ActivityLibraryPage> createState() => _ActivityLibraryPageState();
}

class _ActivityLibraryPageState extends State<ActivityLibraryPage> {
  late final Future<List<Activity>> _activities;

  @override
  void initState() {
    super.initState();
    _activities = AssetActivityLibraryRepository().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const PageBackButton(),
        title: const Text('Activity library'),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<List<Activity>>(
        future: _activities,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This library is unavailable until every entry passes review.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final activities = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            children: [
              Card(
                color: AppColors.amber.withValues(alpha: 0.16),
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: AppColors.deepAmber,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Small ideas, offered gently',
                        style: TextStyle(
                          color: AppColors.deepAmber,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'These are lifestyle ideas, not treatment plans. Solace will never present an unreviewed entry as a suggestion.',
                        style: TextStyle(
                          color: AppColors.mutedInk,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${activities.length} reviewed starter ideas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              for (final activity in activities) ...[
                _ActivityCard(activity: activity),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.coral.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(_iconFor(activity.type), color: AppColors.coral),
          ),
        ),
        title: Text(activity.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${activity.description}\n${_labelFor(activity.type)} · ${activity.durationMinutes} min · ${_labelFor(activity.effort)} effort',
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.verified_outlined, color: AppColors.amber),
      ),
    );
  }

  IconData _iconFor(ActivityType type) {
    return switch (type) {
      ActivityType.movement => Icons.directions_walk_rounded,
      ActivityType.social => Icons.people_outline_rounded,
      ActivityType.creative => Icons.palette_outlined,
      ActivityType.nature => Icons.park_outlined,
      ActivityType.mindfulness => Icons.self_improvement_rounded,
      ActivityType.learning => Icons.lightbulb_outline_rounded,
      ActivityType.productivity => Icons.checklist_rounded,
    };
  }

  String _labelFor(Enum value) {
    final words = value.name.split('_');
    return words
        .map(
          (word) =>
              word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }
}
