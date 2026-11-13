import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/emotion_result.dart';
import '../../core/models/session_record.dart';

/// The emotional breakdown of one journal entry, drawn from what the model
/// actually returned: how heavy or light it read, how much energy, which
/// feelings it was closest to, and which signals it used. Plain words only
/// (never "valence"), always hedged: it is a weak guess, and only the person
/// knows how they felt.
class EmotionReadingCard extends StatelessWidget {
  const EmotionReadingCard({
    required this.reading,
    this.review,
    this.provenance,
    this.userPickedMood,
    this.onReview,
    super.key,
  });

  final EmotionResult reading;
  final MoodReview? review;
  final MoodProvenance? provenance;
  final String? userPickedMood;
  final ValueChanged<({MoodReviewStatus status, String? correctedMood})>? onReview;

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

  /// A class name in plain words ('fear' becomes 'Afraid').
  static String plainFeeling(String cls) => _plain(cls);

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
          if (provenance != null || onReview != null) ...[
            const SizedBox(height: 14),
            _ReadingReviewSection(
              reading: r,
              review: review,
              provenance: provenance,
              userPickedMood: userPickedMood,
              onReview: onReview,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadingReviewSection extends StatefulWidget {
  const _ReadingReviewSection({
    required this.reading,
    this.review,
    this.provenance,
    this.userPickedMood,
    this.onReview,
  });

  final EmotionResult reading;
  final MoodReview? review;
  final MoodProvenance? provenance;
  final String? userPickedMood;
  final ValueChanged<({MoodReviewStatus status, String? correctedMood})>? onReview;

  @override
  State<_ReadingReviewSection> createState() => _ReadingReviewSectionState();
}

class _ReadingReviewSectionState extends State<_ReadingReviewSection> {
  bool _pickingCorrection = false;

  String _provenanceLabel() {
    final r = widget.review;
    final matchesCurrent = r != null && r.matchesReading(widget.reading);
    if (r != null && r.status == MoodReviewStatus.corrected) {
      final word = Moods.display(r.mood);
      return 'You corrected this to ${word.isEmpty ? 'your own word' : word}';
    }
    if (r != null && r.status == MoodReviewStatus.noneFits) {
      return 'You marked that none of these fit';
    }
    if (r != null && r.status == MoodReviewStatus.accepted && matchesCurrent) {
      return 'You confirmed this reading';
    }
    if (r != null && r.status == MoodReviewStatus.accepted && !matchesCurrent) {
      return 'Newer model estimate (previous confirmation was for an earlier reading)';
    }
    if (r != null && r.status == MoodReviewStatus.skipped && matchesCurrent) {
      return 'Review skipped — model estimate';
    }
    final picked = Moods.normalize(widget.userPickedMood);
    if (picked != null) {
      return 'Your check-in mood: ${Moods.display(picked)}';
    }
    return switch (widget.provenance) {
      MoodProvenance.userCorrected => 'Your correction',
      MoodProvenance.userReported => 'Your check-in mood',
      MoodProvenance.userConfirmedModel => 'You confirmed this reading',
      MoodProvenance.noneFits => 'None of the mood words fit',
      MoodProvenance.modelEstimate => 'Model estimate (not yet reviewed)',
      _ => 'Model estimate',
    };
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final matchesCurrent = r != null && r.matchesReading(widget.reading);
    final alreadyReviewed =
        matchesCurrent ||
        r?.status == MoodReviewStatus.corrected ||
        r?.status == MoodReviewStatus.noneFits;
    final isConfirmedOrCorrected =
        alreadyReviewed && r?.status != MoodReviewStatus.skipped;

    const sage = Color(0xFF3F9A7C);
    const ink = Color(0xFF3A3125);
    const soft = Color(0xFF7B6A55);

    return AnimatedContainer(
      key: const ValueKey('reading-review-section'),
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isConfirmedOrCorrected
            ? const Color(0xFFF3FAF6)
            : const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConfirmedOrCorrected
              ? sage.withValues(alpha: 0.28)
              : const Color(0x45C7A977),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConfirmedOrCorrected
                      ? sage.withValues(alpha: 0.16)
                      : const Color(0x28FFB534),
                ),
                child: Icon(
                  isConfirmedOrCorrected
                      ? Icons.check_rounded
                      : Icons.tune_rounded,
                  size: 16,
                  color: isConfirmedOrCorrected ? sage : const Color(0xFF9C6615),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _provenanceLabel(),
                  key: const ValueKey('reading-provenance'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isConfirmedOrCorrected ? const Color(0xFF235342) : ink,
                  ),
                ),
              ),
              if (widget.onReview != null && alreadyReviewed && !_pickingCorrection)
                TextButton(
                  key: const ValueKey('reading-fit-change'),
                  onPressed: () => setState(() => _pickingCorrection = true),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.white.withValues(alpha: 0.85),
                    foregroundColor: soft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          if (widget.onReview != null && (!alreadyReviewed || _pickingCorrection)) ...[
            const SizedBox(height: 12),
            if (!_pickingCorrection) ...[
              const Text(
                'Does this fit?',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EAD6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: const ValueKey('reading-fit-yes'),
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => widget.onReview!((
                          status: MoodReviewStatus.accepted,
                          correctedMood: null,
                        )),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1278501E),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 15, color: sage),
                              SizedBox(width: 4),
                              Text(
                                'Yes',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF235342),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: InkWell(
                        key: const ValueKey('reading-fit-not-quite'),
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => setState(() => _pickingCorrection = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Text(
                            'Not quite',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      key: const ValueKey('reading-fit-skip'),
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => widget.onReview!((
                        status: MoodReviewStatus.skipped,
                        correctedMood: null,
                      )),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: soft,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'How did you feel then?',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _pickingCorrection = false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: soft),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final word in Moods.values)
                    InkWell(
                      key: ValueKey('reading-mood-${word.toLowerCase()}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() => _pickingCorrection = false);
                        widget.onReview!((
                          status: MoodReviewStatus.corrected,
                          correctedMood: word,
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x52C7A977)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D78501E),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          Moods.display(word),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                  InkWell(
                    key: const ValueKey('reading-fit-none'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _pickingCorrection = false);
                      widget.onReview!((
                        status: MoodReviewStatus.noneFits,
                        correctedMood: null,
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6EFE0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x38C7A977)),
                      ),
                      child: const Text(
                        'None fits',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: soft,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
