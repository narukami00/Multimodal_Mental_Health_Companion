import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/navigation/app_tab.dart';
import '../../core/theme/solace_palette.dart';

/// A floating pill of destinations that overlays the view stack.
///
/// It is not a bottom navigation bar: nothing reserves space for it and the
/// page runs edge to edge underneath. The selected destination grows to show
/// its name; the rest stay icon-only, and selection is carried by colour rather
/// than by a second capsule nested inside the first.
class SolaceNavCapsule extends StatelessWidget {
  const SolaceNavCapsule({
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  /// How far the pill floats above the bottom safe area.
  static const bottomInset = 14.0;

  /// Height of the pill itself.
  static const height = 62.0;

  /// Amber stays constant across palettes for brand contrast.
  static const _active = Color(0xFFC87F10);

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: bottomInset + MediaQuery.paddingOf(context).bottom,
      ),
      // A Row, not a Center: Center expands to fill whatever it is given, which
      // squeezed the page content out of the way entirely.
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Clip.none matters: the default clipping squared the shadow off
            // into a rectangular artifact behind the pill on Android.
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              clipBehavior: Clip.none,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: colors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: colors.ink.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tab in AppTab.values)
                      _NavItem(
                        tab: tab,
                        isSelected: selected == tab,
                        colors: colors,
                        onTap: () => onSelect(tab),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  final AppTab tab;
  final bool isSelected;
  final SolaceColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = isSelected
        ? SolaceNavCapsule._active
        : colors.mutedInk;

    return Semantics(
      label: tab.label,
      selected: isSelected,
      button: true,
      // GestureDetector rather than InkWell: an ink splash here draws a
      // capsule-shaped highlight on press, which read as a stray outline.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.none,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? 12 : 11,
              vertical: 9,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 21,
                  height: 21,
                  child: CustomPaint(
                    painter: _NavIconPainter(tab: tab, color: colour),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 7),
                  Text(
                    tab.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: SolaceNavCapsule._active,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws each destination's mark.
///
/// Simple silhouettes rather than a font's glyphs: a sun for Today, a page for
/// Journal, a rising line for Insights, and a person for You.
class _NavIconPainter extends CustomPainter {
  _NavIconPainter({required this.tab, required this.color});

  final AppTab tab;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;

    final w = size.width;
    final h = size.height;
    final centre = Offset(w / 2, h / 2);

    switch (tab) {
      case AppTab.today:
        canvas.drawCircle(centre, w * 0.20, stroke);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          canvas.drawLine(
            Offset(
              centre.dx + w * 0.30 * math.cos(angle),
              centre.dy + w * 0.30 * math.sin(angle),
            ),
            Offset(
              centre.dx + w * 0.42 * math.cos(angle),
              centre.dy + w * 0.42 * math.sin(angle),
            ),
            stroke,
          );
        }
      case AppTab.journal:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.20, h * 0.14, w * 0.60, h * 0.72),
            Radius.circular(w * 0.14),
          ),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.34, h * 0.40),
          Offset(w * 0.66, h * 0.40),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.34, h * 0.58),
          Offset(w * 0.56, h * 0.58),
          stroke,
        );
      case AppTab.insights:
        for (var i = 0; i < 3; i++) {
          final x = w * (0.24 + i * 0.26);
          canvas.drawLine(
            Offset(x, h * [0.34, 0.54, 0.74][i]),
            Offset(x, h * 0.80),
            stroke,
          );
        }
      case AppTab.you:
        canvas.drawCircle(Offset(centre.dx, h * 0.34), w * 0.16, fill);
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(centre.dx, h * 0.92),
            width: w * 0.62,
            height: h * 0.58,
          ),
          math.pi,
          math.pi,
          false,
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter oldDelegate) {
    return oldDelegate.tab != tab || oldDelegate.color != color;
  }
}
