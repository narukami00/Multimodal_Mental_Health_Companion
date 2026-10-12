import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/chat_message_record.dart';
import '../../core/models/emotion_result.dart';
import '../insights/mood_tab.dart' show moodColors;
import '../journal/emotion_reading_card.dart';

/// Pops a small card above one of the person's messages saying how that message read: the most likely
/// mood in plain words, hedged, with the heavy/even/light split and the energy. Closes on any tap outside.
///
/// [read] is called when the message has no reading yet (older messages): while it runs the card says
/// so, and if it comes back empty the card says why, instead of showing anything made up.
OverlayEntry showMessageReading({
  required BuildContext context,
  required Rect anchor,
  required ChatMessageRecord message,
  required Future<EmotionResult?> Function()? read,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  void close() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      const width = 268.0;
      const cardHeight = 200.0;
      final left = (anchor.right - width).clamp(12.0, media.size.width - width - 12);
      final above = anchor.top - cardHeight - 10 > media.padding.top + 8;
      final top = above ? anchor.top - cardHeight - 10 : anchor.bottom + 10;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('message-reading-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: const ColoredBox(color: Color(0x14000000)),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: MessageReadingCard(message: message, read: read),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
  return entry;
}

class MessageReadingCard extends StatefulWidget {
  const MessageReadingCard({required this.message, required this.read, super.key});

  final ChatMessageRecord message;
  final Future<EmotionResult?> Function()? read;

  @override
  State<MessageReadingCard> createState() => _MessageReadingCardState();
}

class _MessageReadingCardState extends State<MessageReadingCard> {
  EmotionResult? _reading;
  bool _working = false;
  bool _failed = false;

  static const _ink = Color(0xFF3A3125);
  static const _soft = Color(0xFF8A7A61);

  @override
  void initState() {
    super.initState();
    _reading = widget.message.reading;
    if (_reading == null) _run();
  }

  Future<void> _run() async {
    final read = widget.read;
    if (read == null) {
      _failed = true;
      return;
    }
    _working = true;
    final result = await read();
    if (!mounted) return;
    setState(() {
      _working = false;
      _reading = result;
      _failed = result == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('message-reading'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x66E2C185)),
          boxShadow: const [BoxShadow(color: Color(0x3396641E), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: _working ? _busy() : (_reading == null ? _none() : _card(_reading!)),
      ),
    );
  }

  Widget _busy() => const Row(
        key: ValueKey('message-reading-busy'),
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Expanded(
            child: Text('Reading this message…',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _soft)),
          ),
        ],
      );

  Widget _none() => Text(
        _failed
            ? 'No reading for this message. It needs the companion server running and your OK '
                '(You tab → What Sol remembers).'
            : '',
        key: const ValueKey('message-reading-none'),
        style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: _soft),
      );

  Widget _card(EmotionResult r) {
    final internal = Moods.fromReadingMood(r.mood);
    final color = moodColors[internal] ?? const Color(0xFFFFB534);
    final lv = r.valenceProbs;
    final la = r.arousalProbs;
    final heavy = lv?['negative'] ?? 0;
    final even = lv?['neutral'] ?? 0;
    final light = lv?['positive'] ?? 0;
    final energy = la == null ? null : _energyWord(la);
    final basis = EmotionReadingCard.basedOn(r.pattern);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(Moods.display(internal),
                key: const ValueKey('message-reading-word'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
            if (energy != null) ...[
              const SizedBox(width: 10),
              Text('$energy energy', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _soft)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          EmotionReadingCard.headline(r).replaceFirst('This entry', 'This message'),
          key: const ValueKey('message-reading-headline'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink, height: 1.3),
        ),
        if (lv != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Row(
              children: [
                for (final p in [(heavy, const Color(0xFFD9825B)), (even, const Color(0xFFFFB534)), (light, const Color(0xFF8FB083))])
                  if (p.$1 > 0.001) Expanded(flex: (p.$1 * 1000).round().clamp(1, 1000), child: Container(height: 8, color: p.$2)),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Heavy ${(heavy * 100).round()}% · Even ${(even * 100).round()}% · Light ${(light * 100).round()}%',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _soft),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'A guess from $basis${r.inContext ? ', with your earlier messages in mind' : ''}. Only you know how you felt.',
          style: const TextStyle(fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w600, color: _soft),
        ),
      ],
    );
  }

  static String _energyWord(Map<String, double> la) {
    final low = la['low'] ?? 0;
    final mid = la['mid'] ?? 0;
    final high = la['high'] ?? 0;
    if (low >= mid && low >= high) return 'Low';
    if (high >= mid && high >= low) return 'High';
    return 'Medium';
  }
}
