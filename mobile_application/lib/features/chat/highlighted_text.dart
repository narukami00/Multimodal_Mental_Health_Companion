import 'package:flutter/material.dart';

import '../../domain/chat/conversation_search.dart';

/// Builds a [Text.rich] with all case-insensitive matches of [query] highlighted
/// in Solace's warm amber pill accent.
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    required this.query,
    this.style,
    this.highlightColor = const Color(0xFFFFD978),
    this.highlightTextColor = const Color(0xFF3A3125),
    this.maxLines,
    this.overflow = TextOverflow.clip,
    super.key,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final Color highlightColor;
  final Color highlightTextColor;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final segments = splitHighlightSegments(text, query);
    if (segments.isEmpty ||
        (segments.length == 1 && !segments.first.highlighted)) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final seg in segments)
            TextSpan(
              text: seg.text,
              style: seg.highlighted
                  ? TextStyle(
                      backgroundColor: highlightColor,
                      color: highlightTextColor,
                      fontWeight: FontWeight.w800,
                    )
                  : null,
            ),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
