import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../core/theme/solace_palette.dart';
import '../sessions/session_controller.dart';
import 'session_detail_page.dart';

class JournalPage extends StatelessWidget {
  const JournalPage({required this.sessionController, super.key});

  final SessionController sessionController;

  static const _ink = Color(0xFF3A3125);
  static const _faint = Color(0xFFA68F68);

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.background, colors.surface],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AnimatedBuilder(
            animation: sessionController,
            builder: (context, _) {
              final sessions = sessionController.sessions;
              return SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Journal',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  const Text(
                                    'YOUR DAYS, GENTLY KEPT',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      color: _faint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _showFilterNote(context),
                              tooltip: 'Filter entries',
                              icon: const Icon(Icons.tune_rounded, size: 20),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(42, 42),
                                maximumSize: const Size(42, 42),
                                backgroundColor: const Color(0x21FFB534),
                                foregroundColor: const Color(0xFF8A7458),
                                side: BorderSide(
                                  color: const Color(0x66D6AA50),
                                ),
                                shape: const CircleBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (sessions.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyJournal(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 20, 30),
                        sliver: SliverList.builder(
                          itemCount: _groupSessions(sessions).length,
                          itemBuilder: (context, index) {
                            final group = _groupSessions(sessions)[index];
                            return _JournalDayGroup(
                              date: group.date,
                              sessions: group.sessions,
                              onOpen: (session) =>
                                  _openSession(context, session),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openSession(BuildContext context, SessionRecord session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailPage(session: session),
      ),
    );
  }

  void _showFilterNote(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Filters will arrive as more ways to check in become available.',
        ),
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x24FFB534),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(19),
                child: Icon(
                  Icons.auto_stories_outlined,
                  size: 34,
                  color: Color(0xFFB26E0F),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'A blank page is a beginning.',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: JournalPage._ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your check-ins and reflections will gather here, one moment at a time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7B6A55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalDayGroup extends StatelessWidget {
  const _JournalDayGroup({
    required this.date,
    required this.sessions,
    required this.onOpen,
  });

  final DateTime date;
  final List<SessionRecord> sessions;
  final ValueChanged<SessionRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 14),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFD9BE7F),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _dateLabel(context, date),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3A3125),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < sessions.length; index++)
            _StitchedEntry(
              session: sessions[index],
              isLast: index == sessions.length - 1,
              onTap: () => onOpen(sessions[index]),
            ),
        ],
      ),
    );
  }

  String _dateLabel(BuildContext context, DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(value.year, value.month, value.day);
    if (dateOnly == today) return 'Today';
    if (dateOnly == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
  }
}

class _StitchedEntry extends StatelessWidget {
  const _StitchedEntry({
    required this.session,
    required this.isLast,
    required this.onTap,
  });

  final SessionRecord session;
  final bool isLast;
  final VoidCallback onTap;

  static const _calm = Color(0xFF8FB083);
  static const _warm = Color(0xFFFFB534);
  static const _tense = Color(0xFFFF7F50);

  @override
  Widget build(BuildContext context) {
    final beadColor = _beadColor();
    final isVideo = session.mode == CaptureMode.video;
    final tapeColor = isVideo
        ? const Color(0x59FF7F50)
        : const Color(0x59FFB534);
    final modeLabel = switch (session.mode) {
      CaptureMode.text => 'TEXT CHECK-IN',
      CaptureMode.voice => 'VOICE CHECK-IN',
      CaptureMode.video => 'VIDEO CHECK-IN',
    };
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(session.createdAt));
    final snippet = session.text?.trim().isNotEmpty == true
        ? session.text!.trim()
        : session.mood != null
        ? 'You felt ${session.mood}.'
        : 'A gentle check-in, kept here.';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!isLast)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    child: CustomPaint(
                      painter: _DashedThreadPainter(
                        color: const Color(0xFFE7D4A4),
                      ),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: beadColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF96641E).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _modeIcon(session.mode),
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onTap,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFDF6),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x60E2C185)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x3396641E),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: const Color(0x1F96641E),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(15, 15, 12, 14),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -6,
                            right: 14,
                            child: Transform.rotate(
                              angle: 3 * 3.1415926535 / 180,
                              child: Container(
                                width: 60,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: tapeColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      modeLabel,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.3,
                                        color: Color(0xFFAC9770),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    time,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF8A7458),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF483523),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (session.mood != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: beadColor.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        session.mood!,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: _moodInk(beadColor),
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: Color(0xFFC6B28C),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _beadColor() {
    final mood = session.mood ?? '';
    if (const {'calm', 'steady', 'quiet'}.contains(mood)) return _calm;
    if (const {'bright', 'warm', 'sunny', 'tender'}.contains(mood)) {
      return _warm;
    }
    if (const {'tense', 'wobbly'}.contains(mood)) return _tense;
    return switch (session.mode) {
      CaptureMode.text => _calm,
      CaptureMode.voice => _warm,
      CaptureMode.video => _tense,
    };
  }

  Color _moodInk(Color bead) {
    if (bead == _calm) return const Color(0xFF5F7A55);
    if (bead == _warm) return const Color(0xFFA96A0D);
    return const Color(0xFFC05B33);
  }

  IconData _modeIcon(CaptureMode mode) {
    return switch (mode) {
      CaptureMode.text => Icons.edit_outlined,
      CaptureMode.voice => Icons.graphic_eq_rounded,
      CaptureMode.video => Icons.videocam_outlined,
    };
  }
}

class _DashedThreadPainter extends CustomPainter {
  const _DashedThreadPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 6.0;
    const gap = 5.0;
    final x = size.width / 2;
    for (double y = 0; y < size.height; y += dash + gap) {
      final end = y + dash < size.height ? y + dash : size.height;
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedThreadPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SessionDayGroup {
  const _SessionDayGroup({required this.date, required this.sessions});

  final DateTime date;
  final List<SessionRecord> sessions;
}

List<_SessionDayGroup> _groupSessions(List<SessionRecord> sessions) {
  final groups = <String, List<SessionRecord>>{};
  final dates = <String, DateTime>{};
  for (final session in sessions) {
    final date = DateTime(
      session.createdAt.year,
      session.createdAt.month,
      session.createdAt.day,
    );
    final key = date.toIso8601String();
    groups.putIfAbsent(key, () => []).add(session);
    dates[key] = date;
  }

  final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final key in keys)
      _SessionDayGroup(
        date: dates[key]!,
        sessions: List.unmodifiable(groups[key]!),
      ),
  ];
}
