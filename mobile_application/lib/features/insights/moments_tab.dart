import 'package:flutter/material.dart';

import '../../core/models/memory_moment.dart';
import '../memory/moments_controller.dart';
import 'insight_widgets.dart';
import 'mood_tab.dart' show moodColors;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

/// The good things the person chose to keep, in their own words, newest first.
///
/// Only warm, confirmed moments appear here. Hard ones are kept private to Sol's
/// tone and never listed in analytics, and a moment that was set aside or is
/// still waiting for a yes is not shown at all.
class MomentsInsightsTab extends StatelessWidget {
  const MomentsInsightsTab({required this.moments, this.onManage, super.key});

  final MomentsController moments;

  /// Opens "What Sol remembers", where moments are changed and deleted.
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: moments,
      builder: (context, _) {
        final list = [...moments.forInsights]
          ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
        if (list.isEmpty) {
          return const InsightEmpty(
            icon: Icons.auto_awesome_rounded,
            title: 'Good moments will gather here',
            body:
                'When you write about something good, Solace may ask whether to '
                'remember it. The ones you say yes to are kept here, in your own '
                'words, for the days you want a reminder.',
          );
        }

        final children = <Widget>[];
        String? month;
        for (final m in list) {
          final date = DateTime.tryParse(m.occurredOn);
          final heading = date == null ? null : '${_months[date.month - 1]} ${date.year}';
          if (heading != null && heading != month) {
            month = heading;
            children.add(InsightLabel(heading.toUpperCase()));
          }
          children
            ..add(_MomentCard(moment: m, date: date))
            ..add(const SizedBox(height: 10));
        }
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text(
              'Only you see these. Change or delete any of them in What Sol remembers.',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: insightMuted,
              ),
            ),
          ),
        );
        if (onManage != null) {
          children.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('manage-moments'),
                onPressed: onManage,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF96620C),
                  padding: const EdgeInsets.only(left: 6),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Manage what Sol remembers',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          );
        }
        return Column(
          key: const ValueKey('moments-list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.moment, required this.date});

  final MemoryMoment moment;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final mood = moment.moodWord;
    final color = mood == null ? null : moodColors[mood];
    return InsightCard(
      key: ValueKey('moment-card-${moment.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(
              color: color ?? const Color(0xFFFFD27A),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moment.text,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                    color: insightInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (date != null) '${date!.day} ${_months[date!.month - 1].substring(0, 3)}',
                    if (mood != null) 'you checked in as $mood',
                  ].join('  ·  '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: insightMuted,
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
