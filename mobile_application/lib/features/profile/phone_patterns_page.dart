import 'package:flutter/material.dart';

import '../../core/models/daily_features.dart';
import '../../core/theme/solace_palette.dart';
import '../../domain/footprint/day_summary.dart';
import '../footprint/phone_patterns_controller.dart';
import 'permissions_page.dart';
import 'profile_controller.dart';

/// "My phone patterns": exactly what Solace has noticed about phone use, in
/// plain words, with every control over it in one place.
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

  Future<void> _confirmDelete() async {
    final days = _rows.length;
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ListenableBuilder(
              listenable: Listenable.merge([_patterns, widget.profileController]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _header(context, colors),
                  const SizedBox(height: 16),
                  const Text(
                    'What Solace has noticed',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Color(0xFF3A3125),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Estimates from when your screen was on and which kind of '
                    'app was open. They stay on this phone and are never shown '
                    'to anyone else.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: Color(0xFF7B6A55),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _statusCard(context),
                  const SizedBox(height: 12),
                  if (_loaded) _yesterdayCard(context),
                  const SizedBox(height: 12),
                  if (_loaded) _weekCard(),
                  const SizedBox(height: 12),
                  _controlsCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, SolaceColors colors) {
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
        const SizedBox(width: 8),
        const Text(
          'MY PHONE PATTERNS',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: Color(0xFFB9A98C),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2ECDD)),
      ),
      child: child,
    );
  }

  static const _label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
    color: Color(0xFFBCAC8E),
  );

  static const _body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: Color(0xFF5E513F),
  );

  Widget _statusCard(BuildContext context) {
    final (chip, text) = switch (_patterns.status) {
      PhonePatternsStatus.on => (
        'On',
        'Reading on this phone while you use it. Turn it off any time.',
      ),
      PhonePatternsStatus.needsAndroidAccess => (
        'Needs access',
        'You said yes, but Android\'s usage access is off for Solace, so '
            'nothing is being read.',
      ),
      PhonePatternsStatus.off => (
        'Off',
        'Nothing is being read. You can turn this on if you would like Solace '
            'to learn your own rhythm.',
      ),
    };
    final on = _patterns.status == PhonePatternsStatus.on;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('STATUS', style: _label)),
              Container(
                key: const ValueKey('patterns-status'),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFEBF7EB) : const Color(0xFFF4F1E7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chip,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: on
                        ? const Color(0xFF3F823B)
                        : const Color(0xFF7A6E5D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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

    final summary = DaySummary.of(row);
    final lines = _lines(context, summary);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dayName(row.date).toUpperCase(),
            key: const ValueKey('patterns-day'),
            style: _label,
          ),
          const SizedBox(height: 8),
          if (lines.isEmpty)
            const Text(
              'Solace read this day but could not make out anything to say '
              'about it.',
              style: _body,
            )
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line, style: _body),
              ),
        ],
      ),
    );
  }

  List<String> _lines(BuildContext context, DaySummary summary) {
    final lines = <String>[];
    final screen = summary.screenOn;
    if (screen != null) {
      lines.add('Screen on for about ${_duration(screen)}.');
    }
    final pickups = summary.pickups;
    final longest = summary.longestStretch;
    if (pickups != null && pickups > 0) {
      lines.add(
        'Picked up $pickups ${pickups == 1 ? 'time' : 'times'}'
        '${longest == null ? '' : '; the longest stretch was ${_duration(longest)}'}.',
      );
    }
    final busiest = summary.busiestHour;
    if (busiest != null) {
      lines.add(
        'Busiest around ${TimeOfDay(hour: busiest, minute: 0).format(context)}.',
      );
    }
    final categories = summary.topCategories;
    if (categories.isNotEmpty) {
      final first = categories.first;
      final text = StringBuffer(
        'Most time in ${first.name} (${_duration(Duration(minutes: first.minutes))})',
      );
      if (categories.length > 1) {
        final second = categories[1];
        text.write(
          ', then ${second.name} '
          '(${_duration(Duration(minutes: second.minutes))})',
        );
      }
      lines.add('$text.');
    }
    final start = summary.sleepStartMinute;
    final end = summary.sleepEndMinute;
    final sleep = summary.sleepMinutes;
    if (start != null && end != null && sleep != null) {
      lines.add(
        'Phone down around ${_clock(context, start)} and next picked up around '
        '${_clock(context, end)}, roughly ${_duration(Duration(minutes: sleep))}. '
        'That is an estimate and can run longer than real sleep.',
      );
    }
    return lines;
  }

  Widget _weekCard() {
    final days = recentScreenMinutes(_rows, _now);
    final known = [for (final d in days) if (d.minutes != null) d.minutes!];
    final peak = known.isEmpty ? 0 : known.reduce((a, b) => a > b ? a : b);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SCREEN TIME, LAST 7 DAYS', style: _label),
          const SizedBox(height: 12),
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
                              color: day.minutes == null
                                  ? const Color(0xFFEFE8D8)
                                  : const Color(0xFFFFB534),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _initial(day.day),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFA2988A),
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
                color: Color(0xFF7B6A55),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR CONTROLS', style: _label),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Keep the names of the apps I use most',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B3327),
                  ),
                ),
              ),
              Switch(
                key: const ValueKey('patterns-keep-names'),
                value: _patterns.keepsAppNames,
                onChanged: active ? _patterns.setKeepAppNames : null,
              ),
            ],
          ),
          Text(
            active
                ? 'Off means only totals by kind of app are kept, such as '
                      'social or video. Names stay on this phone either way.'
                : 'Turn phone patterns on first.',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF7B6A55),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Keep patterns for',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3B3327),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final days in const [30, 90, 180, 365])
                ChoiceChip(
                  key: ValueKey('retention-$days'),
                  label: Text('$days days'),
                  selected: retention == days,
                  onSelected: (_) => _setRetention(days),
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
              color: Color(0xFF7B6A55),
            ),
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              key: const ValueKey('patterns-delete-all'),
              onPressed: _confirmDelete,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF96620C),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: Text(
                'Delete all stored patterns (${_rows.length} '
                '${_rows.length == 1 ? 'day' : 'days'})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
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
