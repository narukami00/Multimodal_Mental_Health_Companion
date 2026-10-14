import 'package:flutter/material.dart';

import '../../domain/footprint/pattern_features.dart';
import 'break_prompt_controller.dart';

/// The Today card that asks, once and gently, whether anything is going on when
/// the person's phone patterns have shifted.
///
/// It says what looked different in general terms (never a time, an app or a
/// number), claims no cause, and is complete either way: a theme, "nothing in
/// particular", or "not now" all end it.
class BreakPromptCard extends StatelessWidget {
  const BreakPromptCard({required this.controller, super.key});

  final BreakPromptController controller;

  /// What each family of features is, in plain words that fit a sentence.
  static String _phrase(PatternFamily family) => switch (family) {
    PatternFamily.screen => 'how much you have been on your phone',
    PatternFamily.rhythm => 'when your days start and end',
    PatternFamily.apps => 'how your time is spread across apps',
    PatternFamily.mood => 'how you have been feeling',
  };

  /// The themes as a person would say them.
  static String themeLabel(String theme) => switch (theme) {
    'work' => 'Work',
    'relationships' => 'People',
    'sleep' => 'Sleep',
    'health' => 'Health',
    'home' => 'Home',
    'money' => 'Money',
    _ => theme.isEmpty ? theme : theme[0].toUpperCase() + theme.substring(1),
  };

  /// "a", "a and b", or "a, b and c", in a stable order.
  static String _join(List<String> parts) {
    if (parts.length <= 1) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    final prompt = controller.current;
    if (prompt == null) return const SizedBox.shrink();

    final families = prompt.context.shift.families.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final what = _join([for (final f in families) _phrase(f)]);

    return Container(
      key: const ValueKey('break-prompt'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF4DE), Color(0xFFFFE9DC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x1F3B2F26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFFB57A12)),
              SizedBox(width: 7),
              Text(
                'A GENTLE NOTICING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Color(0xFFB57A12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Your days looked a little different lately.',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: Color(0xFF3A3125),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Over the last few days, $what looked different from your usual. '
            'Anything going on?',
            key: const ValueKey('break-prompt-body'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF6B5B43),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final theme in prompt.context.promptThemes)
                ActionChip(
                  key: ValueKey('break-theme-$theme'),
                  label: Text(themeLabel(theme)),
                  onPressed: () => controller.answer(theme),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFEBDCC0)),
                  labelStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5A3E08),
                  ),
                ),
              ActionChip(
                key: const ValueKey('break-nothing'),
                label: const Text('Nothing in particular'),
                onPressed: () => controller.answer(null),
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Color(0xFFD9C9A8)),
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7B6A55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                key: const ValueKey('break-not-now'),
                onPressed: controller.dismiss,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7B6A55),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Not now',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
            ],
          ),
          const Text(
            'You can turn these questions off in My phone patterns.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA2988A),
            ),
          ),
        ],
      ),
    );
  }
}
