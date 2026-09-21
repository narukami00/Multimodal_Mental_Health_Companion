import 'package:flutter/material.dart';

import '../../core/models/session_record.dart';
import '../../core/models/session_input.dart';
import '../../core/theme/app_theme.dart';

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({
    required this.session,
    super.key,
  });

  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context).formatMediumDate(session.createdAt);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(session.createdAt),
    );
    final label = session.emotionResults
        .expand((result) => result.labels ?? const [])
        .map((item) => item.label)
        .firstWhere((item) => item.isNotEmpty, orElse: () => 'still getting to know this signal');

    return Scaffold(
      appBar: AppBar(
        title: Text('$date · $time'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            _SummaryCard(
              label: label,
              mood: session.mood,
              mode: session.mode,
            ),
            const SizedBox(height: 18),
            if (session.text?.trim().isNotEmpty ?? false) ...[
              Text('Your words', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    session.text!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.55,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            Card(
              color: AppColors.amber.withValues(alpha: 0.10),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.deepAmber),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Solace offers reflections, not diagnoses. Model signals are optional and may be incomplete.',
                        style: TextStyle(
                          color: AppColors.deepAmber,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.mood,
    required this.mode,
  });

  final String label;
  final String? mood;
  final CaptureMode mode;

  @override
  Widget build(BuildContext context) {
    final modeLabel = switch (mode) {
      CaptureMode.text => 'Text check-in',
      CaptureMode.voice => 'Voice check-in',
      CaptureMode.video => 'Video check-in',
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Container(height: 9, color: AppColors.amber)),
              Expanded(child: Container(height: 9, color: AppColors.coral)),
              Expanded(child: Container(height: 9, color: AppColors.amber.withValues(alpha: 0.45))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOW THIS SESSION FELT',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.mutedInk,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 7),
                Text(
                  label == 'steady' ? 'Mostly steady' : _humanize(label),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'A soft summary from the signals available in this session.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(icon: Icons.circle, label: _humanize(label)),
                    _Pill(icon: Icons.tune_rounded, label: modeLabel),
                    if (mood != null) _Pill(icon: Icons.favorite_border, label: mood!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _humanize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.deepAmber),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.deepAmber,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
