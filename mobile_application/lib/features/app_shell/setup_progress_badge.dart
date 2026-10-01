import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
import '../../domain/home/baseline_progress.dart';

/// A tiny completion meter for the baseline reflections, pinned in the Home
/// masthead just under the date chip.
///
/// Deliberately smaller than the setup card it replaces: the design notes
/// (docs/design/home_layouts/round-two.html) demoted the standing meter to
/// "a thin rule" so it stops being a nag with a number. It only ever reports
/// genuinely unfinished reflections — a skipped block counts as done — and it
/// disappears entirely once setup is complete, which the shell enforces by
/// not building it at all.
class SetupProgressBadge extends StatelessWidget {
  const SetupProgressBadge({
    required this.progress,
    required this.onContinue,
    super.key,
  });

  final BaselineProgress progress;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Semantics(
      button: true,
      label: 'Setup ${progress.percent}% complete. Continue setup.',
      child: InkWell(
        onTap: onContinue,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          // Wide enough vertically to stay a honest tap target without
          // claiming more of the masthead than the date chip above it.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Setup · ${progress.percent}%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: colors.mutedInk,
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 46,
                height: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 5,
                    backgroundColor: colors.mutedInk.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(colors.amber),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
