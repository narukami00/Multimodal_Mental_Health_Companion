import 'package:flutter/material.dart';

/// Journal and conversations, side by side.
///
/// Replaces the "last four weeks" strip and the "talk it through" card, both of
/// which are now said better and once: the week as the marks under the greeting,
/// and the companion as the shape above the check-in card.
class HomeRail extends StatelessWidget {
  const HomeRail({
    required this.journalCount,
    this.conversationSubtitle,
    this.onJournal,
    this.onConversations,
    super.key,
  });

  final int journalCount;

  /// When the last conversation happened, once the history is wired in. Null
  /// shows the plain label rather than inventing a time.
  final String? conversationSubtitle;

  final VoidCallback? onJournal;
  final VoidCallback? onConversations;

  @override
  Widget build(BuildContext context) {
    // No CrossAxisAlignment.stretch here: a Row cannot stretch its children
    // vertically when it is inside a scrolling list, where the height is
    // unbounded. The tiles carry their own height instead.
    return Row(
      children: [
        Expanded(
          child: _Tile(
            key: const ValueKey('rail-journal'),
            count: journalCount,
            label: 'Journal',
            onTap: onJournal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Tile(
            key: const ValueKey('rail-conversations'),
            icon: Icons.forum_outlined,
            label: 'Conversations',
            subtitle: conversationSubtitle ?? 'Open your chat history',
            tinted: true,
            onTap: onConversations,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    this.count,
    this.icon,
    this.subtitle,
    this.tinted = false,
    this.onTap,
    super.key,
  });

  final String label;
  final int? count;
  final IconData? icon;
  final String? subtitle;
  final bool tinted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tinted ? const Color(0xFFF3F0FB) : const Color(0xFFFFFDF8),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 78,
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: tinted
                  ? const Color(0x336A63A8)
                  : const Color(0x144A3728),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (count != null)
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: Color(0xFF4A3728),
                  ),
                )
              else
                Icon(
                  icon,
                  size: 20,
                  color: const Color(0xFF6A63A8),
                ),
              Text(
                subtitle ?? label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: subtitle != null ? 11.5 : 12.5,
                  height: 1.3,
                  fontWeight: subtitle != null
                      ? FontWeight.w600
                      : FontWeight.w800,
                  color: subtitle != null
                      ? const Color(0xFF5F5878)
                      : const Color(0xFF5F4E3A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
