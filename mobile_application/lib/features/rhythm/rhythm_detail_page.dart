import 'package:flutter/material.dart';

import '../../core/day_key.dart';
import '../../core/models/session_record.dart';
import '../../core/theme/solace_palette.dart';
import '../../domain/rhythm/rhythm_summary.dart';
import '../journal/session_detail_page.dart';
import '../profile/profile_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'rhythm_card.dart';

/// The full four week rhythm view.
///
/// Blanks are neutral and never alarm-styled. There is no target to fall short
/// of, and the user's own usual is shown only when they ask for it.
class RhythmDetailPage extends StatefulWidget {
  const RhythmDetailPage({
    required this.sessionController,
    required this.profileController,
    required this.suggestionController,
    super.key,
  });

  final SessionController sessionController;
  final ProfileController profileController;
  final SuggestionController suggestionController;

  @override
  State<RhythmDetailPage> createState() => _RhythmDetailPageState();
}

class _RhythmDetailPageState extends State<RhythmDetailPage> {
  bool _showUsual = false;

  RhythmSummary get _summary => summariseRhythm(
        sessions: widget.sessionController.sessions,
        restDays: widget.profileController.restDays,
        suggestions: widget.suggestionController.history,
      );

  List<SessionRecord> _sessionsOn(DateTime date) {
    final key = dayKey(date);
    return widget.sessionController.sessions
        .where((session) => dayKey(session.createdAt) == key)
        .toList();
  }

  Future<void> _openDay(RhythmDay day) async {
    final sessions = _sessionsOn(day.date);
    if (sessions.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailPage(session: sessions.first),
        ),
      );
      return;
    }

    if (!mounted) return;
    final label = MaterialLocalizations.of(context).formatMediumDate(day.date);
    final state = day.isRestDay
        ? 'rested'
        : day.hasSuggestionOutcome
            ? 'something you answered'
            : 'nothing logged';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$label · $state'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _toggleRestToday() async {
    final today = dateOnly(DateTime.now());
    final resting = widget.profileController.restDays.contains(dayKey(today));

    if (resting) {
      await widget.profileController.removeRestDay(today);
    } else {
      await widget.profileController.declareRestDay(today);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            resting ? 'Rest day removed.' : 'Rest noted. That counts.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AnimatedBuilder(
              animation: Listenable.merge([
                widget.sessionController,
                widget.profileController,
                widget.suggestionController,
              ]),
              builder: (context, _) {
                final summary = _summary;
                final restingToday = widget.profileController.restDays.contains(
                  dayKey(dateOnly(DateTime.now())),
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    _buildHeader(context, colors),
                    const SizedBox(height: 18),
                    _buildCounts(summary),
                    const SizedBox(height: 16),
                    _buildGrid(summary, colors),
                    const SizedBox(height: 16),
                    const RhythmLegend(),
                    const SizedBox(height: 18),
                    _buildUsual(summary),
                    const SizedBox(height: 14),
                    _buildRestToday(restingToday),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SolaceColors colors) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF3A3125),
            minimumSize: const Size(44, 44),
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Your rhythm',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: Color(0xFF3A3125),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCounts(RhythmSummary summary) {
    if (summary.isEmpty) {
      return const Text(
        'Nothing here yet. A check-in or a rest day will start this off.',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.5,
          color: Color(0xFF7B6A55),
        ),
      );
    }

    return Text(
      'Last 4 weeks · ${rhythmCountsLabel(summary)}',
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF7B6A55),
      ),
    );
  }

  Widget _buildGrid(RhythmSummary summary, SolaceColors colors) {
    // Four rows of seven, oldest first. Rows are consecutive weeks, not
    // calendar weeks, so each row is labelled by its start date instead of a
    // weekday header that would be misleading.
    const perRow = 7;
    final rows = <List<RhythmDay>>[
      for (var start = 0; start < summary.days.length; start += perRow)
        summary.days.sublist(
          start,
          (start + perRow).clamp(0, summary.days.length),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF2ECDD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows) ...[
            if (row != rows.first) const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(
                    MaterialLocalizations.of(context).formatShortDate(
                      row.first.date,
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB0A291),
                    ),
                  ),
                ),
                for (final day in row) ...[
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _openDay(day),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: RhythmDot(day: day, size: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUsual(RhythmSummary summary) {
    final usual = summary.usual;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showUsual = !_showUsual),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              const Icon(
                Icons.insights_outlined,
                size: 16,
                color: Color(0xFF9A8B74),
              ),
              const SizedBox(width: 8),
              Text(
                _showUsual ? 'Hide my usual' : 'Show my usual',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF96620C),
                ),
              ),
            ],
          ),
        ),
        if (_showUsual) ...[
          const SizedBox(height: 8),
          Text(
            usual == null
                ? 'Too early to call this a pattern. '
                    '${summary.checkInCount} check-ins so far.'
                : 'Your usual: about ${usual.daysPerWeek} days a week. '
                    'Just a reference.',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF7B6A55),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRestToday(bool restingToday) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        key: const ValueKey('rest-today'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF96620C),
          backgroundColor: restingToday
              ? const Color(0xFFFFF3DC)
              : const Color(0xFFFFFDF6),
          side: BorderSide(
            color: restingToday
                ? const Color(0xFFFFB534)
                : const Color(0xFFE2D6C0),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _toggleRestToday,
        icon: Icon(
          restingToday ? Icons.check_circle_outline : Icons.bedtime_outlined,
          size: 18,
        ),
        label: Text(
          restingToday ? 'Resting today · undo' : 'Rest today',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
