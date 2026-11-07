import 'package:flutter/material.dart';

import '../../core/models/daily_features.dart';
import '../../domain/footprint/phone_noticings.dart';
import '../footprint/phone_patterns_controller.dart';
import '../goals/goals_controller.dart';
import '../profile/phone_patterns_page.dart';
import '../profile/profile_controller.dart';
import 'insight_widgets.dart';

/// The real, data-backed part of Insights: what the person's own phone use has
/// been, in plain statements, or an honest account of why there is nothing yet.
///
/// Three states and no filler. Not turned on: a quiet invitation. Turned on but
/// still learning: how many days have been read. Enough days: statements about
/// what is usual. It never shows a number it does not have.
class PhonePatternsSection extends StatefulWidget {
  const PhonePatternsSection({
    required this.phonePatterns,
    required this.profileController,
    this.clock,
    super.key,
  });

  final PhonePatternsController phonePatterns;
  final ProfileController profileController;
  final DateTime Function()? clock;

  @override
  State<PhonePatternsSection> createState() => _PhonePatternsSectionState();
}

class _PhonePatternsSectionState extends State<PhonePatternsSection> {
  List<DailyFeatures> _rows = const [];

  PhonePatternsController get _patterns => widget.phonePatterns;

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
    if (mounted) setState(() => _rows = rows);
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhonePatternsPage(
          phonePatterns: _patterns,
          profileController: widget.profileController,
        ),
      ),
    );
  }

  static (IconData, Color, Color) _look(NoticingKind kind) => switch (kind) {
    NoticingKind.screen => (
      Icons.smartphone_rounded,
      Color(0xFFDDE7FB),
      Color(0xFF415E8F),
    ),
    NoticingKind.rhythm => (
      Icons.bedtime_rounded,
      Color(0xFFECE4FA),
      Color(0xFF62518A),
    ),
    NoticingKind.apps => (
      Icons.donut_small_rounded,
      Color(0xFFF9E8CC),
      Color(0xFF865719),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final on = _patterns.status == PhonePatternsStatus.on;
    final result = phoneNoticings(_rows, (widget.clock ?? DateTime.now)());

    final Widget body;
    if (!on && result.isEmpty) {
      body = _invitation(
        'Phone patterns is off, so nothing is being read. Turn it on to see '
            'screen time, night patterns, and app categories.',
        'See what this would show',
      );
    } else if (result.isLearning) {
      body = _learning(result);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final noticing in result.noticings) ...[
            _row(noticing),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('phone-section-details'),
              onPressed: _open,
              child: const Text('See the details'),
            ),
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('phone-patterns-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InsightLabel('PHONE PATTERNS'),
        body,
        if (on && _patterns.goals != null) _goalsLine(_patterns.goals!),
      ],
    );
  }

  /// How the goals are going, in one quiet card: the last week as dots, and a way into the details.
  Widget _goalsLine(GoalsController goals) {
    return ListenableBuilder(
      listenable: goals,
      builder: (context, _) {
        final week = goals.lastWeek;
        final recent = goals.days.length <= 7 ? goals.days : goals.days.sublist(goals.days.length - 7);
        final text = !goals.hasGoals
            ? 'Want something gentle to aim for? A goal is looked at the morning after, and meeting one waters your tree.'
            : week.judged == 0
            ? 'Your goals are set. Yesterday\'s numbers arrive in the morning.'
            : 'You met a goal on ${week.met} of the last ${week.judged} ${week.judged == 1 ? 'day' : 'days'}.';
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: InkWell(
            key: const ValueKey('phone-section-goals'),
            borderRadius: BorderRadius.circular(24),
            onTap: _open,
            child: _shell(
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded, size: 20, color: Color(0xFF96620C)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.45, color: Color(0xFF5E513F)),
                    ),
                  ),
                  if (recent.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    for (final d in recent)
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(left: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: d.anyMet ? const Color(0xFFFFB534) : Colors.transparent,
                          border: Border.all(color: d.anyMet ? const Color(0xFFFFB534) : const Color(0x663B2F26), width: 1.2),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child}) => InsightCard(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE9EFFB), Colors.white],
    ),
    child: child,
  );

  Widget _invitation(String text, String action) => _shell(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          key: const ValueKey('phone-section-off'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: Color(0xFF5E513F),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('phone-section-open'),
          onPressed: _open,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF96620C),
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            action,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  Widget _learning(PhoneNoticings result) {
    final read = result.daysRead;
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Still getting to know your usual.',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3A3125),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$read of ${result.daysNeeded} days read',
            key: const ValueKey('phone-section-learning'),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: Color(0xFF6B5B43),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (read / result.daysNeeded).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFFDDE7FB),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF526DB6)),
            ),
          ),
        ],
      ),
    );
  }

  /// One line of "your usual": the label, the number that matters, what it is, and an optional aside.
  Widget _row(PhoneNoticing n) {
    final (icon, tint, accent) = _look(n.kind);
    return Semantics(
      container: true,
      label: '${n.meta}. ${n.text}',
      excludeSemantics: true,
      child: InsightCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(Colors.white, tint, 0.62)!, Colors.white],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.meta,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (n.value != null) ...[
                    Text(
                      n.value!,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3A3125),
                      ),
                    ),
                    if (n.caption != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          n.caption!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8A7B66),
                          ),
                        ),
                      ),
                    if (n.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F0E2),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            n.note!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7A6A52),
                            ),
                          ),
                        ),
                      ),
                  ] else
                    Text(
                      n.text,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                        color: Color(0xFF3A3125),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
