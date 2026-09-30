import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
import '../../domain/home/baseline_progress.dart';

/// A quiet standing nudge that setup is unfinished.
///
/// Lives below the companion hub rather than in the top slot, so it never
/// competes with the day's check-in. The You page has shown this percentage all
/// along, but only to someone who went looking for it.
class BaselineSetupCard extends StatelessWidget {
  const BaselineSetupCard({
    required this.progress,
    required this.onContinue,
    super.key,
  });

  final BaselineProgress progress;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    final hairline = colors.mutedInk.withValues(alpha: 0.18);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: colors.surface,
        border: Border.all(color: hairline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onContinue,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      size: 18,
                      color: colors.coral,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Setup ${progress.percent}% done',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: colors.mutedInk,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 6,
                    backgroundColor: hairline,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.amber),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'A few short reflections, whenever you feel like it. '
                  'Nothing here is required.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: colors.mutedInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
