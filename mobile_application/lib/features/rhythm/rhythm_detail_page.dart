import 'package:flutter/material.dart';

import '../../core/day_key.dart';
import '../../core/models/activity.dart';
import '../../core/models/session_record.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../../data/contracts/activity_library_repository.dart';
import '../../data/repositories/asset_activity_library_repository.dart';
import '../../domain/rhythm/rhythm_summary.dart';
import '../../domain/rhythm/what_has_helped.dart';
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
    this.libraryRepository,
    super.key,
  });

  final SessionController sessionController;
  final ProfileController profileController;
  final SuggestionController suggestionController;

  /// Supplies activity titles for the ratings list.
  final ActivityLibraryRepository? libraryRepository;

  @override
  State<RhythmDetailPage> createState() => _RhythmDetailPageState();
}

class _RhythmDetailPageState extends State<RhythmDetailPage> {
  bool _showUsual = false;
  late final Future<List<Activity>> _library =
      (widget.libraryRepository ?? AssetActivityLibraryRepository()).load();

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
      body: AnimatedBuilder(
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
            padding: EdgeInsets.zero,
            children: [
              PageHero(
                scene: HeroScene.rhythm,
                title: 'Your rhythm',
                subtitle: summary.isEmpty ? 'A check-in or a rest day starts it off.' : 'The last four weeks, as they were.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (summary.isEmpty)
                      const KitCard(
                        child: Text(
                          'Nothing here yet. A check-in or a rest day will start this off.',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.5, color: kitSoft),
                        ),
                      )
                    else
                      _buildStats(summary),
                    const SizedBox(height: 14),
                    _buildGrid(summary),
                    const SizedBox(height: 12),
                    const RhythmLegend(),
                    if (!summary.isEmpty) ...[
                      const KitLabel('WHICH DAYS YOU SHOW UP'),
                      _buildWeekdays(summary),
                    ],
                    const SizedBox(height: 16),
                    _buildUsual(summary),
                    const SizedBox(height: 14),
                    _buildRestToday(restingToday),
                    const SizedBox(height: 8),
                    _buildWhatHasHelped(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStats(RhythmSummary summary) {
    final attended = summary.days.where((d) => d.attended).length;
    return Row(
      children: [
        StatTile(value: '${summary.checkInCount}', label: summary.checkInCount == 1 ? 'check-in' : 'check-ins', color: const Color(0xFFD98A12), icon: Icons.check_circle_outline_rounded),
        const SizedBox(width: 10),
        StatTile(value: '${summary.restCount}', label: summary.restCount == 1 ? 'rest day' : 'rest days', color: const Color(0xFFD9674A), icon: Icons.bedtime_outlined),
        const SizedBox(width: 10),
        StatTile(value: '$attended', label: 'days you showed up', color: const Color(0xFF4F8A52), icon: Icons.wb_sunny_outlined),
      ],
    );
  }

  Widget _buildGrid(RhythmSummary summary) {
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

    return KitCard(
      key: const ValueKey('rhythm-grid'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isNotEmpty)
            Row(
              children: [
                const SizedBox(width: 58),
                for (final day in rows.first)
                  Expanded(
                    child: Center(
                      child: Text(
                        'MTWTFSS'[day.date.weekday - 1],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kitMuted),
                      ),
                    ),
                  ),
              ],
            ),
          for (final row in rows) ...[
            if (row != rows.first) const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    _shortDate(row.first.date),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kitMuted),
                  ),
                ),
                for (final day in row)
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _openDay(day),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: _DayMark(day: day),
                        ),
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

  static const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _shortDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

  Widget _buildWeekdays(RhythmSummary summary) {
    final counts = List<double>.filled(7, 0);
    for (final d in summary.days) {
      if (d.attended) counts[d.date.weekday - 1] += 1;
    }
    final today = DateTime.now().weekday - 1;
    return KitCard(
      key: const ValueKey('rhythm-weekdays'),
      child: MiniBars(
        values: [for (final c in counts) c],
        labels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
        height: 70,
        color: const Color(0xFFFFB534),
        highlight: today,
      ),
    );
  }

  Widget _buildUsual(RhythmSummary summary) {
    final usual = summary.usual;

    return KitCard(
      key: const ValueKey('rhythm-usual'),
      onTap: () => setState(() => _showUsual = !_showUsual),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: Icons.insights_outlined, color: Color(0xFFB57A12)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _showUsual ? 'Hide my usual' : 'Show my usual',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF96620C)),
                ),
              ),
              Icon(_showUsual ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: kitMuted),
            ],
          ),
          if (_showUsual) ...[
            const SizedBox(height: 14),
            if (usual == null)
              Text(
                'Too early to call this a pattern. ${summary.checkInCount} check-ins so far.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.45, color: kitSoft),
              )
            else
              Row(
                children: [
                  RingGauge(value: usual.daysPerWeek.toDouble(), max: 7, centre: '${usual.daysPerWeek}', caption: 'days a week', size: 96, color: const Color(0xFFFFB534)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Your usual: about ${usual.daysPerWeek} days a week. Just a reference.',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.45, color: kitSoft),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  /// The user's own ratings, laid out as history rather than advice.
  ///
  /// Nothing appears below the outcome threshold, the copy always attributes
  /// the numbers to the user, and there are no verbs of effect — this is not a
  /// recommendation and must not read like one.
  Widget _buildWhatHasHelped() {
    final entries = whatHasHelped(widget.suggestionController.history);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KitLabel('WHAT YOU RATED'),
        if (entries.isEmpty)
          const KitCard(
            child: Text(
              'Nothing to show yet. Try a couple of things first.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.45, color: kitSoft),
            ),
          )
        else
          FutureBuilder<List<Activity>>(
            future: _library,
            builder: (context, snapshot) {
              final titles = <String, String>{
                for (final activity in snapshot.data ?? const <Activity>[])
                  activity.id: activity.title,
              };

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: KitCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                for (var s = 1; s <= 5; s++)
                                  Icon(
                                    s <= entry.meanRating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                                    size: 20,
                                    color: const Color(0xFFFFB534),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${titles[entry.activityId] ?? 'An activity'}: '
                              'you rated ${entry.meanRating.round()} of 5 '
                              'as helpful.',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.4, color: kitInk),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Based on ${entry.ratedCount} '
                              '${entry.ratedCount == 1 ? 'try' : 'tries'}. '
                              'Your ratings only.',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF93887A)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildRestToday(bool restingToday) {
    return SizedBox(
      width: double.infinity,
      height: 52,
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
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: _toggleRestToday,
        icon: Icon(
          restingToday ? Icons.check_circle_outline : Icons.bedtime_outlined,
          size: 19,
        ),
        label: Text(
          restingToday ? 'Resting today · undo' : 'Rest today',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// One day of the grid: a larger mark than the home dots, with a small glyph for what happened.
class _DayMark extends StatelessWidget {
  const _DayMark({required this.day});

  final RhythmDay day;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (day.isToday)
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFF7F50), width: 1.5)),
          ),
        RhythmDot(day: day, size: 20),
        if (day.hasCheckIn) const Icon(Icons.check_rounded, size: 12, color: Colors.white),
        if (day.isRestDay && !day.hasCheckIn) const Icon(Icons.bedtime_rounded, size: 11, color: Color(0xFFFFB534)),
      ],
    );
  }
}
