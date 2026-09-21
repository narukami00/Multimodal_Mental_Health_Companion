import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/home/home_card_priority.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    this.primaryCard = HomeCardType.checkIn,
    this.onStartCheckIn,
    this.onOpenSupport,
    super.key,
  });

  final HomeCardType primaryCard;
  final VoidCallback? onStartCheckIn;
  final VoidCallback? onOpenSupport;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context).formatMediumDate(DateTime.now());
    final card = _PrimaryCardContent.fromType(primaryCard);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
        children: [
          Text('Good to see you', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(date, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Card(
            color: card.color,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: card.foregroundColor,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    card.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: card.foregroundColor.withValues(alpha: 0.78),
                        ),
                  ),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    onPressed: onStartCheckIn,
                    icon: Icon(card.icon),
                    label: Text(card.action),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: card.foregroundColor,
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
            onPressed: onOpenSupport,
            icon: const Icon(Icons.support_outlined, size: 18),
            label: const Text('Support resources'),
          ),
        ],
      ),
    );
  }
}

class _PrimaryCardContent {
  const _PrimaryCardContent({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.icon,
    required this.color,
    required this.foregroundColor,
  });

  final String title;
  final String subtitle;
  final String action;
  final IconData icon;
  final Color color;
  final Color foregroundColor;

  factory _PrimaryCardContent.fromType(HomeCardType type) {
    return switch (type) {
      HomeCardType.support => const _PrimaryCardContent(
          title: 'Support is\nhere when needed',
          subtitle: 'You do not have to figure out the next moment alone.',
          action: 'View support',
          icon: Icons.favorite_border_rounded,
          color: AppColors.coral,
          foregroundColor: Colors.white,
        ),
      HomeCardType.checkIn => const _PrimaryCardContent(
          title: 'A small check-in\nfor right now',
          subtitle: 'There is no perfect answer. Just notice what is here.',
          action: 'Start a check-in',
          icon: Icons.arrow_forward,
          color: AppColors.amber,
          foregroundColor: AppColors.deepAmber,
        ),
      HomeCardType.onboarding => const _PrimaryCardContent(
          title: 'Make Solace\nfeel more like you',
          subtitle: 'A few gentle choices help shape what you see here.',
          action: 'Continue setup',
          icon: Icons.arrow_forward,
          color: AppColors.amber,
          foregroundColor: AppColors.deepAmber,
        ),
      HomeCardType.suggestion => const _PrimaryCardContent(
          title: 'A gentle idea\nfor today',
          subtitle: 'Something small, offered without pressure.',
          action: 'See the idea',
          icon: Icons.arrow_forward,
          color: AppColors.amber,
          foregroundColor: AppColors.deepAmber,
        ),
      HomeCardType.defaultAction => const _PrimaryCardContent(
          title: 'What feels present\nright now?',
          subtitle: 'Open a journal or conversation whenever you are ready.',
          action: 'Open journal',
          icon: Icons.arrow_forward,
          color: AppColors.amber,
          foregroundColor: AppColors.deepAmber,
        ),
    };
  }
}
