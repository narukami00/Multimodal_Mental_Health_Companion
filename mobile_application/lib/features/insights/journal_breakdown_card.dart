import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../../domain/insights/journal_breakdown.dart';
import 'insight_widgets.dart';

/// The journal side of the emotional picture for the last 30 days, kept to what can be taken in at a
/// glance: one big count, the three kinds of entry as tiles, how the entries read as a single bar, and
/// one quiet line for the overall lean. Descriptive, never a verdict.
class JournalBreakdownCard extends StatelessWidget {
  const JournalBreakdownCard({
    required this.breakdown,
    required this.colorForWord,
    required this.modeIcon,
    required this.modeName,
    super.key,
  });

  final JournalBreakdown breakdown;
  final Color Function(String word) colorForWord;
  final IconData Function(CaptureMode mode) modeIcon;
  final String Function(CaptureMode mode) modeName;

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    if (b.isEmpty) {
      return const InsightCard(
        key: ValueKey('journal-breakdown'),
        child: InsightBody('No journal entries in the last 30 days yet.'),
      );
    }
    final maxMode = b.byMode.values.reduce((a, c) => a > c ? a : c);
    final lean = b.leaning;
    final energy = b.energyWord;
    final dominant = b.dominantWord;
    final overall = [
      if (lean != null) 'Overall your entries read $lean',
      if (energy != null) '$energy energy',
    ].join(', ');
    return InsightCard(
      key: const ValueKey('journal-breakdown'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${b.total}',
                  style: const TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, color: insightInk),
                ),
                TextSpan(
                  text: ' ${b.total == 1 ? 'entry' : 'entries'} in the last ${b.days} days',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: insightSoft),
                ),
              ],
            ),
          ),
          if (dominant != null && b.read > 0) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('journal-dominant'),
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              decoration: BoxDecoration(
                color: colorForWord(dominant).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: colorForWord(dominant), shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(
                    'Mostly ${dominant.toLowerCase()}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: insightInk),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              for (final mode in CaptureMode.values) ...[
                if (mode != CaptureMode.values.first) const SizedBox(width: 8),
                Expanded(
                  child: _ModeTile(
                    key: ValueKey('journal-mode-${mode.name}'),
                    icon: modeIcon(mode),
                    name: modeName(mode),
                    count: b.byMode[mode] ?? 0,
                    share: maxMode == 0 ? 0 : (b.byMode[mode] ?? 0) / maxMode,
                    lean: b.leanByMode[mode],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'HOW THEY READ',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: insightMuted),
          ),
          const SizedBox(height: 8),
          if (b.read == 0)
            const InsightBody('None of these entries has been read for how it felt yet.')
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                key: const ValueKey('journal-mood-bar'),
                children: [
                  for (final w in JournalBreakdown.wordOrder)
                    if ((b.moodCounts[w] ?? 0) > 0)
                      Expanded(flex: b.moodCounts[w]!, child: Container(height: 14, color: colorForWord(w))),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final w in JournalBreakdown.wordOrder)
                  if ((b.moodCounts[w] ?? 0) > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: colorForWord(w), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(w, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: insightSoft)),
                        const SizedBox(width: 4),
                        Text(
                          '${b.moodCounts[w]}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: insightMuted),
                        ),
                      ],
                    ),
              ],
            ),
            if (overall.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                overall,
                key: const ValueKey('journal-overall'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: insightSoft),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One kind of entry: its icon, how many, a small fill relative to the busiest kind and, only when it is
/// clear, what that kind usually reads as.
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.name,
    required this.count,
    required this.share,
    required this.lean,
    super.key,
  });

  final IconData icon;
  final String name;
  final int count;
  final double share;
  final String? lean;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(color: const Color(0xFFFAF5E9), borderRadius: BorderRadius.circular(16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: insightMuted),
            const SizedBox(width: 6),
            Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: insightSoft)),
          ],
        ),
        const SizedBox(height: 6),
        Text('$count', style: const TextStyle(fontSize: 24, height: 1.1, fontWeight: FontWeight.w800, color: insightInk)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 5,
            backgroundColor: const Color(0xFFEFE6D2),
            color: const Color(0xFFD9A441),
          ),
        ),
        SizedBox(
          height: 18,
          child: lean == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'reads ${lean!.toLowerCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: insightMuted),
                  ),
                ),
        ),
      ],
    ),
  );
}
