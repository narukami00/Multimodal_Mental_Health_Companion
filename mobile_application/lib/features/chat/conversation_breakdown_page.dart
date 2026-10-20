import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/chat_conversation_record.dart';
import '../../core/models/memory_moment.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/widgets/page_back_button.dart';
import '../../domain/chat/conversation_breakdown.dart';
import '../checkin/check_in_mode_page.dart';
import '../consent/emotion_consent_sheets.dart';
import '../insights/mood_tab.dart' show moodColors;
import '../journal/emotion_reading_card.dart' show EmotionReadingCard;
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import 'chat_controller.dart';

/// How one conversation felt, drawn only from the readings kept on the person's own messages: the
/// overall mood, how it moved, which moments shifted it, what came up again and again, and what was
/// kept. Every sentence is hedged: these are guesses from words and voice, not a verdict.
class ConversationBreakdownPage extends StatelessWidget {
  const ConversationBreakdownPage({
    required this.chatController,
    required this.conversationId,
    required this.safetyController,
    this.profileController,
    this.keptMoments,
    super.key,
  });

  final ChatController chatController;
  final String conversationId;
  final SafetyController safetyController;
  final ProfileController? profileController;

  /// The moments the person chose to keep (confirmed). Those that came from this conversation are shown.
  final List<MemoryMoment> Function()? keptMoments;

  static const _ink = Color(0xFF3A3125);
  static const _soft = Color(0xFF8A7A61);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFCE8),
      appBar: AppBar(
        leading: const PageBackButton(),
        backgroundColor: const Color(0xFFFEFCE8),
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'How this felt',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('breakdown-support'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SupportResourcesPage(
                  safetyController: safetyController,
                  profileController: profileController,
                  assessment: const SafetyAssessment.clear(),
                ),
              ),
            ),
            icon: const Icon(Icons.health_and_safety_outlined, size: 18),
            label: const Text('Support'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD9674A),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: chatController,
        builder: (context, _) {
          final conv = chatController.conversationById(conversationId);
          if (conv == null) {
            return const Center(
              child: Text('This conversation is no longer here.'),
            );
          }
          final breakdown = ConversationBreakdown.from(conv);
          return Center(
            child: ListView(
              key: const ValueKey('breakdown-list'),
              // Same 22px inset as the main pages, so cards line up app-wide.
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
              children: [
                Text(
                  conv.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${conv.dateStr} · ${breakdown.userMessages} ${breakdown.userMessages == 1 ? 'message' : 'messages'} from you',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _soft,
                  ),
                ),
                const SizedBox(height: 14),
                if (breakdown.unreadMessages > 0)
                  _UnreadBanner(
                    chatController: chatController,
                    conversationId: conversationId,
                    count: breakdown.unreadMessages,
                  ),
                if (!breakdown.hasReadings)
                  const _Card(
                    key: ValueKey('breakdown-empty'),
                    child: Text(
                      'None of your messages here have been read for how they felt yet. Once they are, this page shows the '
                      'overall mood, how it moved, and what stood out.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: _soft,
                      ),
                    ),
                  )
                else ...[
                  _Overview(breakdown: breakdown),
                  _TrendCard(breakdown: breakdown),
                  if (breakdown.shifts.isNotEmpty)
                    _ShiftsCard(shifts: breakdown.shifts),
                  _TalkedAboutCard(conversation: conv, breakdown: breakdown),
                  _NoticingCard(notes: breakdown.notes),
                  if (breakdown.points.any((p) => p.reading.faceClasses != null))
                    _LooksCard(points: [for (final p in breakdown.points) if (p.reading.faceClasses != null) p]),
                ],
                _KeptCard(
                  conversation: conv,
                  kept: keptMoments?.call() ?? const [],
                ),
                const SizedBox(height: 6),
                const Text(
                  'These are guesses from your words and voice. They are never a diagnosis, and only you know how you felt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: _soft,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title, super.key});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x4DE2C185)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F96641E),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFF9C8B72),
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _UnreadBanner extends StatefulWidget {
  const _UnreadBanner({
    required this.chatController,
    required this.conversationId,
    required this.count,
  });

  final ChatController chatController;
  final String conversationId;
  final int count;

  @override
  State<_UnreadBanner> createState() => _UnreadBannerState();
}

class _UnreadBannerState extends State<_UnreadBanner> {
  bool _busy = false;
  int _done = 0;

  Future<void> _read() async {
    final consent = CheckInModePage.consent;
    if (consent != null && !await askEmotionConsent(context, consent)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _done = 0;
    });
    final total = widget.count;
    final read = await widget.chatController.readUnreadMessages(
      widget.conversationId,
      onProgress: (done, _) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            read == total
                ? 'Read $read ${read == 1 ? 'message' : 'messages'}.'
                : read == 0
                ? "Couldn't read them: the companion server isn't reachable, or reading isn't switched on."
                : 'Read $read of $total. The rest need the server again.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('breakdown-unread'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF6E4C8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _busy
                  ? 'Reading… $_done of ${widget.count}'
                  : '${widget.count} ${widget.count == 1 ? 'message hasn\'t' : 'messages haven\'t'} been read yet.',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A3125),
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('breakdown-read'),
            onPressed: _busy ? null : _read,
            child: const Text('Read them'),
          ),
        ],
      ),
    );
  }
}

Color _colorOf(String word) =>
    moodColors[Moods.values.firstWhere(
      (m) => Moods.display(m) == word,
      orElse: () => 'Quiet',
    )] ??
    const Color(0xFFFFB534);

class _Overview extends StatelessWidget {
  const _Overview({required this.breakdown});

  final ConversationBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final word = breakdown.dominantWord!;
    final total = breakdown.points.length;
    final counts = breakdown.moodCounts;
    final share = (counts[word] ?? 0) / total;
    final lead = share >= 0.6 ? 'Mostly' : 'Leaning';
    return _Card(
      title: 'Overall',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _colorOf(word),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$lead ${word.toLowerCase()}',
                key: const ValueKey('breakdown-dominant'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3A3125),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$total of ${breakdown.userMessages} of your messages were read.',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A7A61),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                for (final w in ConversationBreakdown.moodOrder)
                  if ((counts[w] ?? 0) > 0)
                    Expanded(
                      flex: counts[w]!,
                      child: Container(height: 12, color: _colorOf(w)),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final w in ConversationBreakdown.moodOrder)
                if ((counts[w] ?? 0) > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _colorOf(w),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$w ${counts[w]}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8A7A61),
                        ),
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.breakdown});

  final ConversationBreakdown breakdown;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  static const _maxPoints = 40;
  int? _selected;

  List<ReadMessage> get _points {
    final all = widget.breakdown.points;
    return all.length > _maxPoints ? all.sublist(all.length - _maxPoints) : all;
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final index = (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final p = points[index];
    return _Card(
      title: 'How it moved',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              Text(
                'Lighter ↑  ·  Heavier ↓',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A7A61),
                ),
              ),
              Text(
                '— mood   ┄ energy',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A7A61),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) => GestureDetector(
              key: const ValueKey('breakdown-chart'),
              onTapDown: (d) {
                if (points.length < 2) return;
                final x =
                    (d.localPosition.dx - _TrendPainter.pad) /
                    (box.maxWidth - 2 * _TrendPainter.pad);
                setState(
                  () => _selected = (x * (points.length - 1)).round().clamp(
                    0,
                    points.length - 1,
                  ),
                );
              },
              child: CustomPaint(
                size: Size(box.maxWidth, 150),
                painter: _TrendPainter(points: points, selected: index),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _colorOf(p.word),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                p.word,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3A3125),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'message ${index + 1} of ${points.length}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A7A61),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '“${_snippet(p.message.spokenText)}”',
            key: const ValueKey('breakdown-selected'),
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Color(0xFF483523),
            ),
          ),
        ],
      ),
    );
  }
}

String _snippet(String text, [int max = 110]) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.selected});

  final List<ReadMessage> points;
  final int selected;
  static const pad = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - 2 * pad;
    double xAt(int i) => points.length == 1
        ? size.width / 2
        : pad + i * (size.width - 2 * pad) / (points.length - 1);
    double yAt(double v) => pad + (1 - (v + 1) / 2) * h;

    final grid = Paint()
      ..color = const Color(0x33B4965A)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(pad, yAt(0)),
      Offset(size.width - pad, yAt(0)),
      grid,
    );
    final faint = Paint()
      ..color = const Color(0x14B4965A)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(pad, yAt(0.5)),
      Offset(size.width - pad, yAt(0.5)),
      faint,
    );
    canvas.drawLine(
      Offset(pad, yAt(-0.5)),
      Offset(size.width - pad, yAt(-0.5)),
      faint,
    );

    // energy: a thin dashed line
    final energy = Paint()
      ..color = const Color(0xFF9DB4C8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < points.length; i++) {
      final a = Offset(xAt(i - 1), yAt(points[i - 1].energy));
      final b = Offset(xAt(i), yAt(points[i].energy));
      final dx = b.dx - a.dx, dy = b.dy - a.dy;
      final len = (b - a).distance;
      if (len == 0) continue;
      const dash = 5.0, gap = 4.0;
      for (var d = 0.0; d < len; d += dash + gap) {
        final t0 = d / len, t1 = (d + dash).clamp(0, len) / len;
        canvas.drawLine(
          Offset(a.dx + dx * t0, a.dy + dy * t0),
          Offset(a.dx + dx * t1, a.dy + dy * t1),
          energy,
        );
      }
    }

    // mood: a solid line with a dot per message
    final line = Paint()
      ..color = const Color(0xFF8A6A32)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xAt(i), yAt(points[i].score));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xAt(i), yAt(points[i].score));
      final isSel = i == selected;
      canvas.drawCircle(o, isSel ? 8 : 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        o,
        isSel ? 6 : 3.6,
        Paint()..color = _colorOf(points[i].word),
      );
      if (isSel) {
        canvas.drawCircle(
          o,
          9,
          Paint()
            ..color = const Color(0xFF3A3125)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points || old.selected != selected;
}

class _ShiftsCard extends StatelessWidget {
  const _ShiftsCard({required this.shifts});

  final List<MoodShift> shifts;

  @override
  Widget build(BuildContext context) {
    return _Card(
      key: const ValueKey('breakdown-shifts'),
      title: 'Moments that moved',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in shifts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    s.lighter
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 18,
                    color: s.lighter
                        ? const Color(0xFF6E9560)
                        : const Color(0xFFC96F48),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s.lighter ? 'Lighter' : 'Heavier'}: ${s.from.word} → ${s.to.word}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF3A3125),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'at “${_snippet(s.to.message.spokenText, 90)}”',
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6E6252),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Text(
            'This points at what you were saying when the reading changed. It does not mean those words caused the feeling.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A7A61),
            ),
          ),
        ],
      ),
    );
  }
}

/// How the person's face read, message by message, when the camera was on. Hidden until they ask for it: the
/// face is the weakest signal here, so it is offered, never pushed, and every line is hedged.
class _LooksCard extends StatefulWidget {
  const _LooksCard({required this.points});

  final List<ReadMessage> points;

  @override
  State<_LooksCard> createState() => _LooksCardState();
}

class _LooksCardState extends State<_LooksCard> {
  bool _open = false;

  static (String, double) _top(Map<String, double> classes) {
    final best = classes.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (EmotionReadingCard.plainFeeling(best.key), best.value);
  }

  @override
  Widget build(BuildContext context) {
    const soft = Color(0xFF8A7A61);
    const ink = Color(0xFF3A3125);
    return _Card(
      key: const ValueKey('breakdown-looks'),
      title: 'How you looked',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('looks-toggle'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _open ? 'Hide how you looked' : 'Show how your face looked (optional, a rough guess)',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ink),
                    ),
                  ),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: soft),
                ],
              ),
            ),
          ),
          if (!_open)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Your camera was on for part of this. What your face seemed to show is tucked away until you ask.',
                key: ValueKey('looks-withheld'),
                style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: soft),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            const Text(
              'The face is the hardest thing to read, and it often looks different from how you feel. Take this lightly: '
              'it can easily be wrong.',
              key: ValueKey('looks-warning'),
              style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w700, color: Color(0xFFB4651F)),
            ),
            const SizedBox(height: 10),
            for (final p in widget.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  key: ValueKey('looks-${p.message.id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'While you said “${_snippet(p.message.spokenText, 80)}”',
                      style: const TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: Color(0xFF6E6252)),
                    ),
                    const SizedBox(height: 3),
                    Builder(builder: (context) {
                      final (word, share) = _top(p.reading.faceClasses!);
                      return Text(
                        'Your face looked roughly ${word.toLowerCase()} (${(share * 100).round()}%)',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ink),
                      );
                    }),
                  ],
                ),
              ),
            const Text(
              'Only you know how you felt.',
              style: TextStyle(fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w600, color: soft),
            ),
          ],
        ],
      ),
    );
  }
}

class _TalkedAboutCard extends StatelessWidget {
  const _TalkedAboutCard({required this.conversation, required this.breakdown});

  final ChatConversationRecord conversation;
  final ConversationBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'What came up',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conversation.hasSummary
                ? conversation.summary!.trim()
                : 'No summary yet. Sol writes one once a conversation gets long.',
            key: const ValueKey('breakdown-summary'),
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF483523),
            ),
          ),
          if (breakdown.keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Words you came back to',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8A7A61),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              key: const ValueKey('breakdown-keywords'),
              spacing: 7,
              runSpacing: 6,
              children: [
                for (final k in breakdown.keywords)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1D1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      k,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E4A22),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoticingCard extends StatelessWidget {
  const _NoticingCard({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Worth noticing',
      child: Column(
        key: const ValueKey('breakdown-notes'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 9),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: Color(0xFFD9A441),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      n,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF483523),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeptCard extends StatelessWidget {
  const _KeptCard({required this.conversation, required this.kept});

  final ChatConversationRecord conversation;
  final List<MemoryMoment> kept;

  @override
  Widget build(BuildContext context) {
    final ids = {for (final m in conversation.messages) 'chat:${m.id}'};
    final mine = [
      for (final m in kept)
        if (m.isConfirmed && m.sourceRef != null && ids.contains(m.sourceRef))
          m,
    ];
    return _Card(
      title: 'Kept from this conversation',
      child: mine.isEmpty
          ? const Text(
              'Nothing kept yet. When you choose to keep a good moment, it shows up here.',
              key: ValueKey('breakdown-kept-empty'),
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A7A61),
              ),
            )
          : Column(
              key: const ValueKey('breakdown-kept'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.bookmark_rounded,
                          size: 16,
                          color: Color(0xFFD9A441),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            m.text,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF483523),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
