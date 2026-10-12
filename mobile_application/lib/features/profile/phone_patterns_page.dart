import 'package:flutter/material.dart';

import '../../core/models/daily_features.dart';
import '../../core/theme/solace_palette.dart';
import '../../domain/footprint/day_rhythm.dart';
import '../../domain/footprint/day_summary.dart';
import '../footprint/day_rhythm_card.dart';
import '../footprint/phone_patterns_controller.dart';
import 'permissions_page.dart';
import 'profile_controller.dart';

const _ink = Color(0xFF3A3125);
const _soft = Color(0xFF6C5E50);
const _muted = Color(0xFFA69883);
const _line = Color(0x143B2F26);
const _amber = Color(0xFFFFB534);
const _night = Color(0xFF7C8DB8);
const _categoryColors = [
  Color(0xFFFFB534),
  Color(0xFF8DBB9A),
  Color(0xFFB4ADD6),
  Color(0xFFEBA3A8),
];

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
      body: Stack(
        children: [
          const Positioned(
            top: -110,
            right: -70,
            child: _AmbientBlob(color: Color(0x30FFB534), size: 300),
          ),
          const Positioned(
            top: 220,
            left: -120,
            child: _AmbientBlob(color: Color(0x1F7C8DB8), size: 280),
          ),
          SafeArea(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _patterns,
                widget.profileController,
              ]),
              builder: (context, _) {
                // Loading state: the page renders fully populated once the
                // stored days have arrived, but rather than flashing a blank
                // frame in between, it shows placeholders in the same spots.
                if (!_loaded) {
                  return ListView(
                    // Same 22px inset as the main pages, so cards line up
                    // app-wide.
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                    children: [
                      _header(context, colors),
                      const SizedBox(height: 14),
                      _Reveal(index: 0, child: _statusCard(context)),
                      const SizedBox(height: 12),
                      _Reveal(
                        index: 1,
                        child: _card(
                          child: const SizedBox(
                            height: 120,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return ListView(
                  // Same 22px inset as the main pages, so cards line up
                  // app-wide.
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                  children: [
                    _header(context, colors),
                    const SizedBox(height: 14),
                    _Reveal(index: 0, child: _statusCard(context)),
                    const SizedBox(height: 12),
                    _Reveal(index: 1, child: _yesterdayCard(context)),
                    const SizedBox(height: 12),
                    _Reveal(index: 2, child: _weekCard()),
                    const SizedBox(height: 12),
                    _Reveal(index: 3, child: _controlsCard(context)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, SolaceColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          style: IconButton.styleFrom(
            foregroundColor: _ink,
            minimumSize: const Size(44, 44),
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'MY PHONE PATTERNS',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: Color(0xFFD08018),
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'What Solace has noticed',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.12,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Estimates from when your screen was on and which kind of app was '
            'open. They stay on this phone and are never shown to anyone else.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: _soft,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({
    required Widget child,
    Gradient? gradient,
    EdgeInsets? padding,
  }) {
    return Container(
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFDDF0DE) : const Color(0xFFFFEBC6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: on ? const Color(0xFF3F823B) : const Color(0xFFB57A12),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('STATUS', style: _label)),
              Container(
                key: const ValueKey('patterns-status'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFDDF0DE) : const Color(0xFFF4F1E7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chip,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: on
                        ? const Color(0xFF3F823B)
                        : const Color(0xFF7A6E5D),
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

    final stats = <({String value, String label})>[
      if (summary.screenOn != null)
        (value: _duration(summary.screenOn!), label: 'Screen on'),
      if (summary.pickups != null && summary.pickups! > 0)
        (
          value: '${summary.pickups}',
          label: summary.pickups == 1 ? 'Pickup' : 'Pickups',
        ),
      if (summary.longestStretch != null)
        (value: _duration(summary.longestStretch!), label: 'Longest stretch'),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (ring != null) ...[
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: Semantics(
                      label: 'Screen time through the day. ${ring.caption}',
                      child: DayRhythmRing(
                        rhythm: ring,
                        animate: !reduceMotion,
                        showTotal: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final stat in stats)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _Stat(value: stat.value, label: stat.label),
                        ),
                      if (busiest != null)
                        Text(
                          'Busiest around ${TimeOfDay(hour: busiest, minute: 0).format(context)}.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _soft,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          color: Color(0xFF4F5A7A),
                        ),
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

  Widget _weekCard() {
    final days = recentScreenMinutes(_rows, _now);
    final known = [
      for (final d in days)
        if (d.minutes != null) d.minutes!,
    ];
    final peak = known.isEmpty ? 0 : known.reduce((a, b) => a > b ? a : b);
    final low = known.isEmpty ? 0 : known.reduce((a, b) => a < b ? a : b);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SCREEN TIME, LAST 7 DAYS', style: _label),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
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
                          Container(
                            key: ValueKey('week-bar-${day.day.day}'),
                            width: 16,
                            height: day.minutes == null || peak == 0
                                ? 3
                                : 6 + 52 * (day.minutes! / peak),
                            decoration: BoxDecoration(
                              gradient: day.minutes == null
                                  ? null
                                  : const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFFFFC95E),
                                        Color(0xFFFFA726),
                                      ],
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
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _muted,
                            ),
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _soft,
              ),
            ),
          ] else if (known.length >= 2) ...[
            const SizedBox(height: 10),
            Text(
              'From ${_duration(Duration(minutes: low))} to '
              '${_duration(Duration(minutes: peak))} a day.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _soft,
              ),
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR CONTROLS', style: _label),
          const SizedBox(height: 6),
          _switchRow(
            switchKey: const ValueKey('patterns-keep-names'),
            icon: Icons.apps_rounded,
            title: 'Keep the names of the apps I use most',
            subtitle: active
                ? 'Off means only totals by kind of app are kept, such as '
                      'social or video. Names stay on this phone either way.'
                : 'Turn phone patterns on first.',
            value: _patterns.keepsAppNames,
            onChanged: active ? _patterns.setKeepAppNames : null,
          ),
          const Divider(height: 22, color: _line),
          _switchRow(
            switchKey: const ValueKey('patterns-ask-switch'),
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Ask me when my days look different',
            subtitle:
                'Now and then, when your patterns shift in more than one '
                'way, Solace may ask once whether anything is going on. Never '
                'about a single odd day, and never more than once a week.',
            value: !widget.profileController.profile.patternPromptsMuted,
            onChanged: (on) =>
                widget.profileController.setPatternPromptsMuted(!on),
          ),
          const Divider(height: 22, color: _line),
          const Row(
            children: [
              Icon(Icons.history_toggle_off_rounded, size: 19, color: _muted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Keep patterns for',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
            'Choosing a shorter time removes older days right away.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: _soft,
            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
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
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 19, color: _muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  color: _soft,
                ),
              ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          height: 1.1,
          color: _ink,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _muted,
        ),
      ),
    ],
  );
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
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
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
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4EEDF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: value.clamp(0.04, 1.0),
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color:
                                  _categoryColors[i % _categoryColors.length],
                              borderRadius: BorderRadius.circular(99),
                            ),
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _soft,
                    ),
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
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}
