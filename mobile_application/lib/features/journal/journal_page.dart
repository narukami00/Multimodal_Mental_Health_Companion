import 'package:flutter/material.dart';
import '../../core/widgets/visual_kit.dart';

import '../../core/constants/moods.dart';

import '../../core/models/session_input.dart';
import '../../core/models/session_record.dart';
import '../../core/theme/solace_palette.dart';
import '../sessions/session_controller.dart';
import '../insights/mood_tab.dart' show moodColors;
import '../checkin/check_in_mode_page.dart';
import 'reading_status.dart';
import '../consent/emotion_consent_sheets.dart';
import 'session_detail_page.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({required this.sessionController, super.key});

  final SessionController sessionController;

  static const _ink = Color(0xFF3A3125);

  @override
  State<JournalPage> createState() => _JournalPageState();
}

/// What the journal is narrowed to. Empty sets mean "everything".
class JournalFilter {
  const JournalFilter({this.moods = const {}, this.modes = const {}});

  /// Display words (Upbeat, Calm, Even, Low, Tense) or [notRead].
  final Set<String> moods;
  final Set<CaptureMode> modes;

  static const notRead = 'Not read yet';
  static const moodWords = ['Upbeat', 'Calm', 'Even', 'Low', 'Tense'];

  bool get isActive => moods.isNotEmpty || modes.isNotEmpty;

  bool matches(SessionRecord s) {
    if (modes.isNotEmpty && !modes.contains(s.mode)) return false;
    if (moods.isEmpty) return true;
    final mood = s.effectiveMood;
    final word = mood == null ? notRead : Moods.display(mood);
    return moods.contains(word);
  }
}

class _JournalPageState extends State<JournalPage> {
  JournalFilter _filter = const JournalFilter();

  SessionController get sessionController => widget.sessionController;

  static const _ink = JournalPage._ink;

  Future<void> _openFilter() async {
    final next = await showModalBottomSheet<JournalFilter>(
      context: context,
      // Full height so the Drag handles swipe-down, but the sheet content
      // itself still sizes to fit what it holds.
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFDF6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) =>
          _FilterSheet(initial: _filter, sessions: sessionController.sessions),
    );
    if (next != null && mounted) setState(() => _filter = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    // The page colour itself, as Insights and You use. The gradient into the
    // surface colour is what made this page read whiter than its neighbours.
    return ColoredBox(
      color: colors.background,
      // No width cap and the same 22 px side inset as Today and Insights, so cards line up across the app's pages.
      child: AnimatedBuilder(
            animation: sessionController,
            builder: (context, _) {
              final all = sessionController.sessions;
              final sessions = all.where(_filter.matches).toList();
              return SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'YOUR DAYS, GENTLY KEPT',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      color: Color(0xFFD08018),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Journal',
                                    style: TextStyle(
                                      fontSize: 29,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: _ink,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('journal-filter'),
                              onPressed: _openFilter,
                              tooltip: 'Filter entries',
                              icon: Badge(
                                isLabelVisible: _filter.isActive,
                                smallSize: 9,
                                backgroundColor: const Color(0xFFD9825B),
                                child: const Icon(Icons.tune_rounded, size: 20),
                              ),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(40, 40),
                                maximumSize: const Size(40, 40),
                                backgroundColor: _filter.isActive
                                    ? const Color(0x55FFB534)
                                    : const Color(0xB8FFFFFF),
                                foregroundColor: const Color(0xFF6C5E50),
                                side: const BorderSide(
                                  color: Color(0x143B2F26),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _UnreadEntriesBanner(
                        sessionController: sessionController,
                      ),
                    ),
                    if (all.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyJournal(),
                      )
                    else if (sessions.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _NothingMatches(
                          onClear: () =>
                              setState(() => _filter = const JournalFilter()),
                        ),
                      )
                    else
                      SliverPadding(
                        // Room for the floating pill, which overlays the page.
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 120),
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
    );
  }

  void _openSession(BuildContext context, SessionRecord session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailPage(
          session: session,
          onDelete: (s) => sessionController.deleteSession(s.id),
          onReanalyze: sessionController.reanalyze,
        ),
      ),
    );
  }
}

class _NothingMatches extends StatelessWidget {
  const _NothingMatches({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('journal-nothing-matches'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No entries match this filter.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: JournalPage._ink,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const ValueKey('journal-clear-filter'),
              onPressed: onClear,
              child: const Text('Show everything'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick moods and/or kinds of entry. Counts beside each word are of ALL entries, so the person can see
/// what a filter would find before choosing it.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.sessions});

  final JournalFilter initial;
  final List<SessionRecord> sessions;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _moods = {...widget.initial.moods};
  late Set<CaptureMode> _modes = {...widget.initial.modes};

  int _countMood(String word) => widget.sessions.where((s) {
    final m = s.effectiveMood;
    return (m == null ? JournalFilter.notRead : Moods.display(m)) == word;
  }).length;

  int _countMode(CaptureMode mode) =>
      widget.sessions.where((s) => s.mode == mode).length;

  Widget _chip({
    required Key key,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    Color? dot,
  }) {
    return FilterChip(
      key: key,
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      avatar: dot == null
          ? null
          : Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
      label: Text('$label · $count'),
      backgroundColor: const Color(0xFFFFF8E8),
      selectedColor: const Color(0xFFFFE2B0),
      side: BorderSide(
        color: selected ? const Color(0xFFD9A441) : const Color(0x66D6AA50),
      ),
      labelStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF3A3125),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const heading = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
      color: Color(0xFF9C8B72),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Column(
          key: const ValueKey('journal-filter-sheet'),
          // The sheet's height is whatever the content needs — never a layout
          // fight between a scroll view and full-height constraints.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter your journal',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A3125),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Moods are how each entry read, not a label you chose.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A7A61),
              ),
            ),
            const SizedBox(height: 16),
            const Text('HOW IT READ', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final word in [
                  ...JournalFilter.moodWords,
                  JournalFilter.notRead,
                ])
                  _chip(
                    key: ValueKey('filter-mood-$word'),
                    label: word,
                    count: _countMood(word),
                    selected: _moods.contains(word),
                    dot: word == JournalFilter.notRead
                        ? null
                        : moodColors[Moods.values.firstWhere(
                            (m) => Moods.display(m) == word,
                          )],
                    onTap: () => setState(
                      () => _moods.contains(word)
                          ? _moods.remove(word)
                          : _moods.add(word),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('KIND OF ENTRY', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (mode, label) in [
                  (CaptureMode.text, 'Text'),
                  (CaptureMode.voice, 'Voice'),
                  (CaptureMode.video, 'Video'),
                ])
                  _chip(
                    key: ValueKey('filter-mode-${mode.name}'),
                    label: label,
                    count: _countMode(mode),
                    selected: _modes.contains(mode),
                    onTap: () => setState(
                      () => _modes.contains(mode)
                          ? _modes.remove(mode)
                          : _modes.add(mode),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('filter-reset'),
                  onPressed: () => setState(() {
                    _moods = {};
                    _modes = {};
                  }),
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('filter-apply'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(JournalFilter(moods: _moods, modes: _modes)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB534),
                      foregroundColor: const Color(0xFF3D2E14),
                      minimumSize: const Size.fromHeight(50),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
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
              const SizedBox(width: 11),
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

  @override
  Widget build(BuildContext context) {
    final beadColor = _beadColor();
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
        : session.awaitingRecording
        ? 'Waiting to be written down. Your recording is safe on this phone.'
        : session.effectiveMood != null
        ? 'It read as ${Moods.display(session.effectiveMood).toLowerCase()}.'
        : 'A gentle check-in, kept here.';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
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
                  width: 28,
                  height: 28,
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
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              // The shadow lives on a plain box outside the Material: painted by
              // an Ink inside it, the shadow was clipped to a rectangle and
              // showed as a square haze behind the rounded corners.
              child: Container(
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
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: onTap,
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(15, 15, 12, 14),
                        child: Stack(
                          children: [
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
                                    if (session.effectiveMood != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: beadColor.withValues(
                                            alpha: 0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: Text(
                                          Moods.display(session.effectiveMood),
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
          ),
        ],
      ),
    );
  }

  /// The bead takes the colour of how the entry READ (the model's mood), the same colours as the mood
  /// strip in Insights. Older entries use the word that was picked at the time; with neither, a neutral bead.
  Color _beadColor() {
    final mood = session.effectiveMood;
    return (mood == null ? null : moodColors[mood]) ?? _calm;
  }

  Color _moodInk(Color bead) =>
      HSLColor.fromColor(bead).withLightness(0.30).toColor();

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
        // Within a day the entries read in the order they were made: the newest sits at the bottom.
        sessions: List.unmodifiable(
          groups[key]!..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        ),
      ),
  ];
}

/// Offers to read earlier entries that have no emotion reading yet (made before readings existed, or
/// without the server). Asks for the person's OK first, then reads them one by one and says how many.
class _UnreadEntriesBanner extends StatefulWidget {
  const _UnreadEntriesBanner({required this.sessionController});

  final SessionController sessionController;

  @override
  State<_UnreadEntriesBanner> createState() => _UnreadEntriesBannerState();
}

class _UnreadEntriesBannerState extends State<_UnreadEntriesBanner> {
  bool _busy = false;

  Future<void> _read() async {
    final consent = CheckInModePage.consent;
    if (consent != null && !await askEmotionConsent(context, consent)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final total = widget.sessionController.unread.length;
    final read = await widget.sessionController.reanalyzeUnread();
    final why = read == 0 ? await explainNoReading() : null; // what is actually in the way, not a guess
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            read == total
                ? 'Read $read earlier ${read == 1 ? 'entry' : 'entries'}.'
                : read == 0
                ? why!
                : 'Read $read of $total. The rest will wait for the server.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.sessionController.unread.length;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('unread-banner'),
      margin: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF6E4C8)),
      ),
      child: Row(
        children: [
          const IconTile(
            icon: Icons.auto_awesome_outlined,
            color: kitAmber,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count earlier ${count == 1 ? 'entry is' : 'entries are'} not read yet',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A3125),
                  ),
                ),
                const Text(
                  'Read them to see how each felt.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A7A61),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const ValueKey('read-earlier'),
            onPressed: _busy ? null : _read,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFE2A6),
              foregroundColor: const Color(0xFF7A4E10),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(_busy ? 'Reading…' : 'Read now'),
          ),
        ],
      ),
    );
  }
}
