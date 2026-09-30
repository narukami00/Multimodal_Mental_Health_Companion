import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/navigation/app_tab.dart';
import '../../core/theme/solace_palette.dart';

/// A floating navigation pill, inset from the edges so content visibly
/// continues behind and beneath it.
///
/// Deliberately not docked to the bottom of the screen: a full-width bar pinned
/// to the edge is the thing that made the app look dated, and it also forces the
/// content to stop dead above it. Icons are drawn rather than taken from an icon
/// font, so their weight matches the pill and nothing depends on a font being
/// present.
class SolaceNavPill extends StatelessWidget {
  const SolaceNavPill({
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  /// How far the pill floats above the bottom safe area.
  static const bottomInset = 14.0;

  /// Total space the pill occupies, so a scrolling page can reserve room.
  static const height = 64.0;

  static double reservedSpace(BuildContext context) {
    return height + bottomInset + MediaQuery.paddingOf(context).bottom;
  }

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        bottomInset + MediaQuery.paddingOf(context).bottom,
      ),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(6),
        // No surface at all: the page behind is the background. A filled or
        // bordered container on top of the page made the navigation look like
        // one more card stacked on the screen.
        child: Row(
          children: [
            for (final tab in AppTab.values)
              Expanded(
                child: _NavItem(
                  tab: tab,
                  isSelected: selected == tab,
                  colors: colors,
                  onTap: () => onSelect(tab),
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
    // Selected is expressed by colour alone: the icon and the label take the
    // accent, nothing gets a nested capsule behind it. A filled chip inside a
    // container inside the page was three surfaces to say one word.
    // Amber stays constant across palettes for brand contrast; only the
    // inactive ink follows the palette neutrals.
    final colour = isSelected
        ? const Color(0xFFC87F10)
        : colors.mutedInk;
    return Semantics(
      label: tab.label,
      selected: isSelected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CustomPaint(
                  painter: _NavIconPainter(tab: tab, color: colour),
                ),
              ),
              // The label appears only for the selected destination, so the
              // active item is identifiable without a background shape.
              if (isSelected) ...[
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    tab.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: colour,
                    ),
                  ),
                ),
              ],
            ],
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
        // A sun: one circle and eight short rays.
        canvas.drawCircle(centre, w * 0.20, stroke);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final from = Offset(
            centre.dx + w * 0.30 * math.cos(angle),
            centre.dy + w * 0.30 * math.sin(angle),
          );
          final to = Offset(
            centre.dx + w * 0.42 * math.cos(angle),
            centre.dy + w * 0.42 * math.sin(angle),
          );
          canvas.drawLine(from, to, stroke);
        }
      case AppTab.journal:
        // A page with two ruled lines.
        final page = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.20, h * 0.14, w * 0.60, h * 0.72),
          Radius.circular(w * 0.14),
        );
        canvas.drawRRect(page, stroke);
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
        // Bars rising to the right.
        final bars = [0.34, 0.54, 0.74];
        for (var i = 0; i < bars.length; i++) {
          final x = w * (0.24 + i * 0.26);
          canvas.drawLine(
            Offset(x, h * bars[i]),
            Offset(x, h * 0.80),
            stroke,
          );
        }
      case AppTab.you:
        // A person: head and shoulders.
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
