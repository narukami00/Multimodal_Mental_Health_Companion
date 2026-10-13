import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/daily_features.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../../domain/footprint/day_rhythm.dart';
import '../../domain/footprint/day_summary.dart';
import '../footprint/day_rhythm_card.dart';
import '../footprint/phone_patterns_controller.dart';
import 'permissions_page.dart';
import 'profile_controller.dart';

const _ink = kitInk;
const _soft = Color(0xFF6C5E50);
const _muted = kitMuted;
const _line = kitLine;
const _amber = kitAmber;
const _night = Color(0xFF7C8DB8);
const _categoryColors = [
  Color(0xFFFFB534),
  Color(0xFF8DBB9A),
  Color(0xFFB4ADD6),
  Color(0xFFEBA3A8),
];

bool get _inTest {
  try {
    return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// "My phone patterns": exactly what Solace has noticed about phone use, with
/// every control over it in one place.
///
/// It describes and never judges: no good or bad, no targets, no comparison with
/// anyone. Sleep is labelled an estimate wherever it appears.
class PhonePatternsPage extends StatefulWidget {
  const PhonePatternsPage({
    required this.phonePatterns,
    required this.profileController,
    this.clock,
    super.key,
  });

  final PhonePatternsController phonePatterns;
  final ProfileController profileController;

  /// Injectable so tests can fix what "today" is.
  final DateTime Function()? clock;

  @override
  State<PhonePatternsPage> createState() => _PhonePatternsPageState();
}

class _PhonePatternsPageState extends State<PhonePatternsPage> {
  List<DailyFeatures> _rows = const [];
  bool _loaded = false;

  PhonePatternsController get _patterns => widget.phonePatterns;
  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _patterns.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _patterns.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final rows = await _patterns.storedDays();
    if (mounted) {
      setState(() {
        _rows = rows;
        _loaded = true;
      });
    }
  }

  Future<void> _setRetention(int days) async {
    await widget.profileController.setFeatureRetentionDays(days);
    await _patterns.pruneTo(days, now: _now);
    await _reload();
  }

  int get _usageDays => _rows.where((row) => row.hasUsage).length;

  Future<void> _confirmDelete() async {
    final days = _usageDays;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all stored patterns?'),
        content: Text(
          'This removes $days ${days == 1 ? 'day' : 'days'} of patterns from '
          'this phone. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('patterns-confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _patterns.deleteStored();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: ListenableBuilder(
        listenable: Listenable.merge([_patterns, widget.profileController]),
        builder: (context, _) {
          // Loading state: the page renders fully populated once the stored days have arrived, but
          // rather than flashing a blank frame in between, it shows placeholders in the same spots.
          final children = <Widget>[
            const PageHero(
              scene: HeroScene.noticed,
              title: 'What Solace has noticed',
              subtitle: 'Estimates from your phone. They stay on this phone.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Reveal(index: 0, child: _statusCard(context)),
                  const SizedBox(height: 12),
                  if (!_loaded)
                    _Reveal(
                      index: 1,
                      child: _card(
                        child: const SizedBox(
                          height: 120,
                          child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        ),
                      ),
                    )
                  else ...[
                    _Reveal(index: 1, child: _yesterdayCard(context)),
                    const SizedBox(height: 12),
                    if (_sleepCardShown) ...[
                      _Reveal(index: 2, child: _sleepCard(context)),
                      const SizedBox(height: 12),
                    ],
                    _Reveal(index: 3, child: _weekCard()),
                    const SizedBox(height: 12),
                    _Reveal(index: 4, child: _controlsCard(context)),
                  ],
                ],
              ),
            ),
          ];
          return ListView(padding: EdgeInsets.zero, children: children);
        },
      ),
    );
  }

  Widget _card({
    required Widget child,
    Gradient? gradient,
    EdgeInsets? padding,
    Key? key,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: gradient == null ? Colors.white : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
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

  static const _label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
    color: _muted,
  );

  static const _body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: Color(0xFF5E513F),
  );

  Widget _statusCard(BuildContext context) {
    final (chip, text, icon) = switch (_patterns.status) {
      PhonePatternsStatus.on => (
        'On',
        'Reading on this phone while you use it. Turn it off any time.',
        Icons.check_rounded,
      ),
      PhonePatternsStatus.needsAndroidAccess => (
        'Needs access',
        "You said yes, but Android's usage access is off for Solace, so "
            'nothing is being read.',
        Icons.lock_open_rounded,
      ),
      PhonePatternsStatus.off => (
        'Off',
        'Nothing is being read. You can turn this on if you would like Solace '
            'to learn your own rhythm.',
        Icons.pause_rounded,
      ),
    };
    final on = _patterns.status == PhonePatternsStatus.on;
    final tone = on ? const Color(0xFF3F823B) : const Color(0xFFB57A12);

    return _card(
      gradient: LinearGradient(
        colors: on
            ? const [Color(0xFFEFF8EF), Color(0xFFFFFFFF)]
            : const [Color(0xFFFFF6E6), Color(0xFFFFFFFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulseDot(color: tone, active: on, icon: icon),
              const SizedBox(width: 14),
              const Expanded(child: Text('STATUS', style: _label)),
              Container(
                key: const ValueKey('patterns-status'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFDDF0DE) : const Color(0xFFF4F1E7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chip,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: on ? const Color(0xFF3F823B) : const Color(0xFF7A6E5D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(text, style: _body),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('patterns-manage'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PermissionsPage(phonePatterns: _patterns),
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF96620C),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Manage in Permissions & privacy',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yesterdayCard(BuildContext context) {
    final row = latestFinishedDay(_rows, _now);
    if (row == null) {
      return _card(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MOST RECENT FULL DAY', style: _label),
            SizedBox(height: 8),
            Text(
              'Nothing yet. A day shows up here once it has finished and Solace '
              'has read it.',
              key: ValueKey('patterns-empty'),
              style: _body,
            ),
          ],
        ),
      );
    }

    final summary = DaySummary.of(row, categoryLimit: 4);
    final rhythm = dayRhythm(_rows, _now);
    final ring = rhythm != null && rhythm.dayKey == row.dayKey ? rhythm : null;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final busiest = summary.busiestHour;

    final stats = <({String value, String label, IconData icon, Color color})>[
      if (summary.screenOn != null)
        (value: _duration(summary.screenOn!), label: 'Screen on', icon: Icons.smartphone_rounded, color: const Color(0xFFD98A12)),
      if (summary.pickups != null && summary.pickups! > 0)
        (
          value: '${summary.pickups}',
          label: summary.pickups == 1 ? 'Pickup' : 'Pickups',
          icon: Icons.touch_app_rounded,
          color: const Color(0xFF6E73C8),
        ),
      if (summary.longestStretch != null)
        (value: _duration(summary.longestStretch!), label: 'Longest stretch', icon: Icons.hourglass_bottom_rounded, color: const Color(0xFF4F8A52)),
    ];
    final night = _nightLine(context, summary);
    final categories = summary.topCategories;
    final nothing = stats.isEmpty && night == null && categories.isEmpty;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dayName(row.date).toUpperCase(),
            key: const ValueKey('patterns-day'),
            style: _label,
          ),
          const SizedBox(height: 14),
          if (nothing)
            const Text(
              'Solace read this day but could not make out anything to say '
              'about it.',
              style: _body,
            )
          else ...[
            if (ring != null)
              Center(
                child: SizedBox(
                  width: 168,
                  height: 168,
                  child: Semantics(
                    label: 'Screen time through the day. ${ring.caption}',
                    child: DayRhythmRing(rhythm: ring, animate: !reduceMotion, showTotal: false),
                  ),
                ),
              ),
            if (ring != null) const SizedBox(height: 14),
            if (stats.isNotEmpty)
              Row(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _StatBlock(value: stats[i].value, label: stats[i].label, icon: stats[i].icon, color: stats[i].color),
                  ],
                ],
              ),
            if (busiest != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: _muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Busiest around ${TimeOfDay(hour: busiest, minute: 0).format(context)}.',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _soft),
                    ),
                  ),
                ],
              ),
            ],
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('WHERE THE TIME WENT', style: _label),
              const SizedBox(height: 10),
              _CategoryBars(categories: categories),
            ],
            if (night != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF1F9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.bedtime_rounded, size: 18, color: _night),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        night,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5, color: Color(0xFF4F5A7A)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String? _nightLine(BuildContext context, DaySummary summary) {
    final start = summary.sleepStartMinute;
    final end = summary.sleepEndMinute;
    final sleep = summary.sleepMinutes;
    if (start == null || end == null || sleep == null) return null;
    return 'Phone down around ${_clock(context, start)} and next picked up around '
        '${_clock(context, end)}, roughly ${_duration(Duration(minutes: sleep))}. '
        'That is an estimate and can run longer than real sleep.';
  }

  /// The last seven finished nights with a sleep estimate, oldest first (day = the date the night ended).
  List<({DateTime day, DaySummary summary})> get _nights {
    final byDay = {for (final r in _rows) r.dayKey: r};
    final out = <({DateTime day, DaySummary summary})>[];
    for (var back = 6; back >= 0; back--) {
      final day = DateTime(_now.year, _now.month, _now.day - back);
      final key = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final row = byDay[key];
      if (row == null) continue;
      final s = DaySummary.of(row);
      if (s.sleepMinutes != null && s.sleepStartMinute != null && s.sleepEndMinute != null) out.add((day: day, summary: s));
    }
    return out;
  }

  bool get _sleepCardShown => _nights.isNotEmpty;

  /// Sleep as a picture: the latest night laid along the evening-to-noon clock, then the recent nights as bars.
  Widget _sleepCard(BuildContext context) {
    final nights = _nights;
    final last = nights.last;
    final start = last.summary.sleepStartMinute!;
    final end = last.summary.sleepEndMinute!;
    final minutes = last.summary.sleepMinutes!;
    final starts = [for (final n in nights) _sinceSix(n.summary.sleepStartMinute!)]..sort();
    final ends = [for (final n in nights) _sinceSix(n.summary.sleepEndMinute!)]..sort();
    final midStart = starts[starts.length ~/ 2];
    final midEnd = ends[ends.length ~/ 2];

    return _card(
      key: const ValueKey('patterns-sleep'),
      gradient: const LinearGradient(colors: [Color(0xFFEEF1FB), Color(0xFFFFFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SLEEP ESTIMATE, LAST NIGHTS', style: _label),
          const SizedBox(height: 14),
          Row(
            children: [
              RingGauge(
                value: minutes.toDouble(),
                max: 720,
                centre: '${(minutes / 60).toStringAsFixed(1)}h',
                caption: 'last night',
                size: 104,
                color: _night,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SleepStamp(icon: Icons.bedtime_rounded, color: _night, text: 'Down ${_clock(context, start)}'),
                    const SizedBox(height: 8),
                    _SleepStamp(icon: Icons.wb_sunny_rounded, color: const Color(0xFFE09A2B), text: 'Up ${_clock(context, end)}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _NightTimeline(
            start: _sinceSix(start),
            end: _sinceSix(end),
            usualStart: nights.length >= 3 ? midStart : null,
            usualEnd: nights.length >= 3 ? midEnd : null,
          ),
          if (nights.length >= 2) ...[
            const SizedBox(height: 18),
            MiniBars(
              values: [for (final n in nights) n.summary.sleepMinutes!.toDouble()],
              labels: [for (final n in nights) _initial(n.day)],
              height: 64,
              color: _night,
              highlight: nights.length - 1,
              valueLabel: (v) => (v / 60).toStringAsFixed(1),
            ),
          ],
          if (nights.length >= 3) ...[
            const SizedBox(height: 8),
            Text(
              'Your usual: down around ${_clock(context, (midStart + 18 * 60) % 1440)}, up around ${_clock(context, (midEnd + 18 * 60) % 1440)}.',
              key: const ValueKey('patterns-sleep-usual'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _soft),
            ),
          ],
        ],
      ),
    );
  }

  /// Minutes after 6 PM, so a night that crosses midnight is one run of numbers.
  static int _sinceSix(int minuteOfDay) => (minuteOfDay - 18 * 60 + 1440) % 1440;

  Widget _weekCard() {
    final days = recentScreenMinutes(_rows, _now);
    final known = [
      for (final d in days)
        if (d.minutes != null) d.minutes!,
    ];
    final peak = known.isEmpty ? 0 : known.reduce((a, b) => a > b ? a : b);
    final low = known.isEmpty ? 0 : known.reduce((a, b) => a < b ? a : b);
    final total = known.fold<int>(0, (a, b) => a + b);
    final sorted = [...known]..sort();
    final usual = sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2];
    final busiestDay = known.isEmpty ? null : days.firstWhere((d) => d.minutes == peak).day;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SCREEN TIME, LAST 7 DAYS', style: _label),
          if (known.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _StatBlock(value: _hours(total), label: 'Week total', icon: Icons.stacked_bar_chart_rounded, color: const Color(0xFFD98A12)),
                const SizedBox(width: 8),
                _StatBlock(value: _hours(usual), label: 'Usual day', icon: Icons.today_rounded, color: const Color(0xFF6E73C8)),
                const SizedBox(width: 8),
                _StatBlock(value: _weekdays[busiestDay!.weekday - 1].substring(0, 3), label: 'Busiest day', icon: Icons.trending_up_rounded, color: const Color(0xFF4F8A52)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 112 + (MediaQuery.textScalerOf(context).scale(1.0) > 1 ? (MediaQuery.textScalerOf(context).scale(1.0) - 1) * 50 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Semantics(
                      label: day.minutes == null
                          ? '${_dayName(day.day)}: not read'
                          : '${_dayName(day.day)}: '
                                '${_duration(Duration(minutes: day.minutes!))}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (day.minutes != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(_hoursShort(day.minutes!), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _soft)),
                            ),
                          Container(
                            key: ValueKey('week-bar-${day.day.day}'),
                            width: 16,
                            height: day.minutes == null || peak == 0
                                ? 3
                                : 6 + 52 * (day.minutes! / peak),
                            decoration: BoxDecoration(
                              gradient: day.minutes == null
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: day.minutes == peak
                                          ? const [Color(0xFFFFB534), Color(0xFFE8814A)]
                                          : const [Color(0xFFFFC95E), Color(0xFFFFA726)],
                                    ),
                              color: day.minutes == null
                                  ? const Color(0xFFEFE8D8)
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _initial(day.day),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (known.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'No days read yet.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _soft),
            ),
          ] else if (known.length >= 2) ...[
            const SizedBox(height: 10),
            Text(
              'From ${_duration(Duration(minutes: low))} to '
              '${_duration(Duration(minutes: peak))} a day.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _soft),
            ),
          ],
        ],
      ),
    );
  }

  Widget _controlsCard(BuildContext context) {
    final retention = widget.profileController.profile.featureRetentionDays;
    final active = _patterns.status != PhonePatternsStatus.off;

    return _card(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR CONTROLS', style: _label),
          const SizedBox(height: 8),
          _switchRow(
            switchKey: const ValueKey('patterns-keep-names'),
            icon: Icons.apps_rounded,
            color: const Color(0xFF6E73C8),
            title: 'Keep the names of the apps I use most',
            subtitle: active
                ? 'Off keeps only totals by kind of app.'
                : 'Turn phone patterns on first.',
            value: _patterns.keepsAppNames,
            onChanged: active ? _patterns.setKeepAppNames : null,
          ),
          const Divider(height: 18, color: _line),
          _switchRow(
            switchKey: const ValueKey('patterns-ask-switch'),
            icon: Icons.chat_bubble_outline_rounded,
            color: const Color(0xFFD9674A),
            title: 'Ask me when my days look different',
            subtitle: 'At most once a week, never for one odd day.',
            value: !widget.profileController.profile.patternPromptsMuted,
            onChanged: (on) =>
                widget.profileController.setPatternPromptsMuted(!on),
          ),
          const Divider(height: 18, color: _line),
          Row(
            children: [
              const IconTile(icon: Icons.history_toggle_off_rounded, color: Color(0xFF4F8A52)),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Keep patterns for', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
              ),
              if (_usageDays > 0) StatusPill('$_usageDays kept', color: const Color(0xFF4F8A52)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final days in const [30, 90, 180, 365])
                ChoiceChip(
                  key: ValueKey('retention-$days'),
                  label: Text('$days days'),
                  selected: retention == days,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _setRetention(days),
                  selectedColor: const Color(0xFFFFE2A8),
                  side: BorderSide(
                    color: retention == days ? const Color(0xFFFFB534) : _line,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: retention == days ? const Color(0xFF5A3E08) : _soft,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'A shorter time removes older days right away.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.45, color: _soft),
          ),
          if (_usageDays > 0) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              key: const ValueKey('patterns-delete-all'),
              onPressed: _confirmDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB5503C),
                side: const BorderSide(color: Color(0xFFF0CFC6)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              // A Row with a Flexible label, so the long label wraps at large
              // text sizes instead of running off the screen.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.delete_outline_rounded, size: 17),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Delete all stored patterns ($_usageDays '
                      '${_usageDays == 1 ? 'day' : 'days'})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _switchRow({
    required Key switchKey,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      children: [
        IconTile(icon: icon, color: color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink, height: 1.25)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4, color: _soft)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Switch(
          key: switchKey,
          value: value,
          onChanged: onChanged,
          activeTrackColor: _amber,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
        ),
      ],
    );
  }

  static String _clock(BuildContext context, int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  static String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours h';
    return '$hours h $minutes min';
  }

  /// Hours with one decimal ("3.4 h"), for the week at a glance.
  static String _hours(int minutes) => '${(minutes / 60).toStringAsFixed(1)} h';

  /// A whole-hour label above a bar ("3h").
  static String _hoursShort(int minutes) => '${(minutes / 60).round()}h';

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _dayName(DateTime day) =>
      '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

  static String _initial(DateTime day) => _weekdays[day.weekday - 1][0];
}

/// A rounded tile with an icon, a big value and a label.
class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label, required this.icon, required this.color});

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 19, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: color)),
              ),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _soft)),
            ],
          ),
        ),
      );
}

class _SleepStamp extends StatelessWidget {
  const _SleepStamp({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconTile(icon: icon, color: color, size: 32),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink))),
        ],
      );
}

/// The evening-to-noon clock as a bar, with the night laid on it (and the person's usual night as a faint
/// ghost). No scale of good and bad: just where the night sat.
class _NightTimeline extends StatelessWidget {
  const _NightTimeline({required this.start, required this.end, this.usualStart, this.usualEnd});

  final int start;
  final int end;
  final int? usualStart;
  final int? usualEnd;

  static const _span = 18 * 60; // 6 PM to noon

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 36,
          width: double.infinity,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(painter: _TimelinePainter(start, end, usualStart, usualEnd, t)),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final (i, label) in const ['6 PM', '12 AM', '6 AM', '12 PM'].indexed)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: i == 0 ? Alignment.centerLeft : (i == 3 ? Alignment.centerRight : Alignment.center),
                  child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _muted)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.start, this.end, this.usualStart, this.usualEnd, this.t);

  final int start;
  final int end;
  final int? usualStart;
  final int? usualEnd;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const span = _NightTimeline._span;
    double x(int m) => 7 + (size.width - 14) * (m.clamp(0, span) / span);
    final y = size.height / 2;
    Paint bar(Color color) => Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14
      ..color = color;
    canvas.drawLine(Offset(7, y), Offset(size.width - 7, y), bar(const Color(0xFFE6E9F5)));
    if (usualStart != null && usualEnd != null && usualEnd! > usualStart!) {
      canvas.drawLine(Offset(x(usualStart!), y), Offset(x(usualEnd!), y), bar(const Color(0xFFB9BFE4).withValues(alpha: 0.55)));
    }
    if (end > start) {
      final a = x(start);
      final b = a + (x(end) - a) * t;
      canvas.drawLine(
        Offset(a, y),
        Offset(b, y),
        bar(Colors.white)
          ..shader = const LinearGradient(colors: [Color(0xFF6E73C8), Color(0xFFE09A2B)]).createShader(Rect.fromLTRB(a, 0, math.max(b, a + 1), 1)),
      );
      canvas.drawCircle(Offset(a, y), 9, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(a, y), 5.5, Paint()..color = const Color(0xFF6E73C8));
      canvas.drawCircle(Offset(b, y), 9, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(b, y), 5.5, Paint()..color = const Color(0xFFE09A2B));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.t != t || old.start != start || old.end != end;
}

/// A status light that gently pulses while reading is on.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active, required this.icon});

  final Color color;
  final bool active;
  final IconData icon;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.active && !_inTest) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              Container(
                width: 46 * (0.7 + 0.3 * _c.value),
                height: 46 * (0.7 + 0.3 * _c.value),
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.2 * (1 - _c.value))),
              ),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: Icon(widget.icon, size: 21, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the day's time went, one soft bar per kind of app. Widths are shares of
/// the busiest kind, so the picture is of proportions and says nothing about
/// whether any of it is a lot.
class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.categories});

  final List<({String name, int minutes})> categories;

  @override
  Widget build(BuildContext context) {
    final top = categories.first.minutes <= 0 ? 1 : categories.first.minutes;
    return Column(
      children: [
        for (var i = 0; i < categories.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    _title(categories[i].name),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: categories[i].minutes / top),
                    duration: Duration(milliseconds: 600 + i * 120),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Stack(
                      children: [
                        Container(
                          height: 10,
                          decoration: BoxDecoration(color: const Color(0xFFF4EEDF), borderRadius: BorderRadius.circular(99)),
                        ),
                        FractionallySizedBox(
                          widthFactor: value.clamp(0.04, 1.0),
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(color: _categoryColors[i % _categoryColors.length], borderRadius: BorderRadius.circular(99)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 62,
                  child: Text(
                    _minutes(categories[i].minutes),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _soft),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _title(String name) =>
      name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';

  static String _minutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }
}

/// Fades and lifts each card in, one after another, so the page settles rather
/// than arriving all at once.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 110),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
