import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context).formatMediumDate(DateTime.now());

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
        children: [
          Text('Good to see you', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(date, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Card(
            color: AppColors.amber,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A small check-in\nfor right now',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.deepAmber,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'There is no perfect answer. Just notice what is here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.deepAmber.withValues(alpha: 0.78),
                        ),
                  ),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Start a check-in'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.deepAmber,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              leading: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.forum_outlined, color: AppColors.coral),
                ),
              ),
              title: const Text('Talk it through'),
              subtitle: const Text('Open a gentle conversation when you want one.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 26),
          Center(
            child: Text(
              'Your pace is enough for today.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.support_outlined, size: 18),
            label: const Text('Support resources'),
          ),
        ],
      ),
    );
  }
}
