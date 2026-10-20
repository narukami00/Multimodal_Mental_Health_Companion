import 'package:flutter/material.dart';

/// The single back button every pushed page uses: a cream tile with a small
/// amber chevron, the same size everywhere.
class PageBackButton extends StatelessWidget {
  const PageBackButton({super.key, this.onPressed, this.tooltip = 'Back'});

  final VoidCallback? onPressed;

  /// A page opened as its own screen is closed, not backed out of: it calls
  /// itself Close.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      tooltip: tooltip,
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFF8A6B33),
        minimumSize: const Size(40, 40),
        maximumSize: const Size(40, 40),
        backgroundColor: const Color(0xFFFFF6E0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
