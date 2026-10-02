import 'package:flutter/material.dart';

const insightInk = Color(0xFF3A3125);
const insightSoft = Color(0xFF6C5E50);
const insightMuted = Color(0xFFA69883);
const insightLine = Color(0x143B2F26);

/// The white rounded card every Insights tab is made of.
class InsightCard extends StatelessWidget {
  const InsightCard({required this.child, this.padding = const EdgeInsets.all(16), super.key});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: insightLine),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14B0782A),
          blurRadius: 18,
          spreadRadius: -8,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

/// A small uppercase section label.
class InsightLabel extends StatelessWidget {
  const InsightLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.3,
        color: insightMuted,
      ),
    ),
  );
}

/// Plain body text used inside cards.
class InsightBody extends StatelessWidget {
  const InsightBody(this.text, {this.strong = false, super.key});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: strong ? 14 : 12.5,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
      height: 1.5,
      color: strong ? insightInk : insightSoft,
    ),
  );
}

/// A calm explanation of why a tab has nothing yet, and what would change that.
class InsightEmpty extends StatelessWidget {
  const InsightEmpty({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => InsightCard(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
    child: Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3DC),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 24, color: const Color(0xFFB57A12)),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: insightInk),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: insightSoft,
          ),
        ),
      ],
    ),
  );
}
