import 'package:flutter/material.dart';

import '../../core/models/emotion_result.dart';

/// The emotional breakdown of one journal entry, drawn from what the model
/// actually returned: how heavy or light it read, how much energy, which
/// feelings it was closest to, and which signals it used. Plain words only
/// (never "valence"), always hedged: it is a weak guess, and only the person
/// knows how they felt.
class EmotionReadingCard extends StatelessWidget {
  const EmotionReadingCard({required this.reading, super.key});

  final EmotionResult reading;

  static const _ink = Color(0xFF3A3125);
  static const _soft = Color(0xFF8A7A61);
  static const _heavy = Color(0xFFD9825B);
  static const _even = Color(0xFFFFB534);
  static const _light = Color(0xFF8FB083);

  /// The one-line headline, hedged by how sure the model was.
  static String headline(EmotionResult r) {
    final feeling = switch (r.mood) {
      'low or tired' => 'a bit low or tired',
      'tense or upset' => 'a bit tense or upset',
      'upbeat' => 'upbeat',
      'calm or content' => 'calm',
      _ => null,
    };
    final verb = (r.pattern ?? '').contains('A') ? 'sounded' : 'read as';
    if (feeling == null || r.tier == null) {
      return 'Nothing strong stood out: mostly even';
    }
    return r.tier == 'clear' ? 'This entry $verb $feeling' : 'This entry might have $verb $feeling';
  }

  /// "your voice, your words and your face" from the signals the model used.
  static String basedOn(String? pattern) {
    final p = pattern ?? '';
    final parts = [
      if (p.contains('A')) 'your voice',
      if (p.contains('T')) 'your words',
      if (p.contains('V')) 'your face',
    ];
    if (parts.isEmpty) return 'what was available';
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  static String _plain(String cls) => switch (cls) {
        'neutral' => 'Neutral',
        'happy' => 'Happy',
        'sad' => 'Sad',
        'angry' => 'Angry',
        'fear' => 'Afraid',
        'disgust' => 'Disgusted',
        'surprise' => 'Surprised',
        _ => cls,
      };

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final classes = (r.classes ?? const <String, double>{}).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final lv = r.valenceProbs;
    final la = r.arousalProbs;
    return Container(
      key: const ValueKey('emotion-reading'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x4DE2C185)),
        boxShadow: const [BoxShadow(color: Color(0x1F96641E), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HOW THIS ENTRY READ',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Color(0xFF9C8B72))),
          const SizedBox(height: 7),
          Text(headline(r),
              key: const ValueKey('reading-headline'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink, height: 1.25)),
          const SizedBox(height: 6),
          Text('A guess from ${basedOn(r.pattern)}, not a verdict. Only you know how you felt.',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _soft, height: 1.45)),
          if (lv != null) ...[
            const SizedBox(height: 18),
            _Split(
              keyName: 'mood-split',
              title: 'Heavy or light',
              parts: [
                ('Heavy', lv['negative'] ?? 0, _heavy),
                ('Even', lv['neutral'] ?? 0, _even),
                ('Light', lv['positive'] ?? 0, _light),
              ],
            ),
          ],
          if (la != null) ...[
            const SizedBox(height: 16),
            _Split(
              keyName: 'energy-split',
              title: 'Energy',
              parts: [
                ('Low', la['low'] ?? 0, const Color(0xFF9DB4C8)),
                ('Medium', la['mid'] ?? 0, _even),
                ('High', la['high'] ?? 0, _heavy),
              ],
            ),
          ],
          if (classes.isNotEmpty) ...[
            const SizedBox(height: 14),
            FeelingsSection(classes: r.classes!, fromVoice: (r.pattern ?? '').contains('A'), startOpen: true),
          ],
        ],
      ),
    );
  }
}

/// The seven class probabilities as bars, with an honest warning. From a recording (voice) they are a
/// rough guess and shown straight away; from words alone they are very unreliable, so they sit behind a
/// button the person chooses to press, with a stronger warning. Never hidden outright.
class FeelingsSection extends StatefulWidget {
  const FeelingsSection({required this.classes, required this.fromVoice, this.startOpen = false, super.key});

  final Map<String, double> classes;
  final bool fromVoice;

  /// Whether a voice-based reading starts expanded (words-only readings always start collapsed).
  final bool startOpen;

  @override
  State<FeelingsSection> createState() => _FeelingsSectionState();
}

class _FeelingsSectionState extends State<FeelingsSection> {
  late bool _open = widget.fromVoice && widget.startOpen;

  @override
  Widget build(BuildContext context) {
    final entries = widget.classes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    const soft = Color(0xFF8A7A61);
    final warning = widget.fromVoice
        ? 'A rough guess. Spread across several feelings is normal: the model rarely picks just one.'
        : 'From words alone these are very unreliable. Take them with a huge grain of salt: they can be plain wrong.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('feelings-toggle'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _open
                        ? 'Closest feelings'
                        : widget.fromVoice
                            ? 'Show closest feelings (a rough guess)'
                            : 'Show specific feelings anyway (unreliable)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF3A3125)),
                  ),
                ),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: soft),
              ],
            ),
          ),
        ),
        if (!_open && !widget.fromVoice)
          const Text(
            'Specific feelings from words alone are unreliable, so they are tucked away until you ask.',
            key: ValueKey('feelings-withheld'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: soft, height: 1.4),
          ),
        if (_open) ...[
          const SizedBox(height: 6),
          Text(warning,
              key: const ValueKey('feelings-warning'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB4651F), height: 1.4)),
          const SizedBox(height: 8),
          for (final e in entries.take(4)) _Bar(label: EmotionReadingCard._plain(e.key), value: e.value),
        ],
      ],
    );
  }
}

class _Split extends StatelessWidget {
  const _Split({required this.keyName, required this.title, required this.parts});

  final String keyName;
  final String title;
  final List<(String, double, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (a, p) => a + p.$2);
    return Column(
      key: ValueKey(keyName),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF3A3125))),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              for (final p in parts)
                if (p.$2 > 0.001)
                  Expanded(
                    flex: (p.$2 / (total == 0 ? 1 : total) * 1000).round().clamp(1, 1000),
                    child: Container(height: 10, color: p.$3),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: p.$3, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('${p.$1} ${(p.$2 * 100).round()}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A7A61))),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF3A3125)))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 9,
                backgroundColor: const Color(0xFFF3EBDA),
                color: const Color(0xFFFFB534),
              ),
            ),
          ),
          SizedBox(width: 40, child: Text('${(value * 100).round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A7A61)))),
        ],
      ),
    );
  }
}

/// Shown when an entry has no model reading: the server was unreachable, the emotion model was off, or the
/// person had not agreed. Says so plainly instead of showing a made-up reading.
class NoReadingCard extends StatelessWidget {
  const NoReadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('no-reading'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF2ECDD)),
      ),
      child: const Text(
        'No emotion reading for this entry. A reading needs the companion server running and your OK '
        '(You tab → What Sol remembers → "Let Sol notice how I sound"). The entry itself is saved as it is.',
        style: TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF8A7A61)),
      ),
    );
  }
}
