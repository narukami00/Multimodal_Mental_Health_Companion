import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../../domain/capacity/capacity_estimator.dart';
import '../../domain/profile/behavioral_profile.dart';
import '../../domain/profile/decision_demo.dart';
import '../../domain/recommendations/recommendation_engine.dart';

/// Whether phone patterns are being read, for the page to describe truthfully.
enum PhoneSignal { off, needsAccess, on }

/// The optional parts that are switched on, so "How Solace decides" can say what
/// is true for this person right now.
class DecisionSignals {
  const DecisionSignals({
    this.phonePatterns = PhoneSignal.off,
    this.keptMoments = 0,
    this.snippetShared = false,
    this.momentsShared = false,
  });

  final PhoneSignal phonePatterns;
  final int keptMoments;
  final bool snippetShared;
  final bool momentsShared;
}

/// The behavioral profile: what the user chose, what they have been doing,
/// and how the app's suggestions currently reflect it.
///
/// Deliberately not clinical and not a scorecard. Every number on this page is
/// the same one the recommendation engine uses, so the page can say honestly
/// why the app is doing what it does — and small samples stay small: shares
/// come with counts, and types with no verdicts say so.
class ProfileInsightsPage extends StatelessWidget {
  const ProfileInsightsPage({
    required this.profile,
    this.signals = const DecisionSignals(),
    super.key,
  });

  final BehavioralProfile profile;

  /// Which optional parts are switched on, so the page can say what is true for
  /// this person right now rather than what could be.
  final DecisionSignals signals;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const PageHero(
              scene: HeroScene.decisions,
              title: 'How Solace decides',
              subtitle: 'Why this idea, and what moves it.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const KitLabel('TRY IT'),
                  const _TryIt(),
                  const KitLabel('WHAT YOU TOLD US'),
                  KitCard(child: _PreferenceChips(profile: profile)),
                  const KitLabel('WHAT YOU HAVE BEEN DOING'),
                  _doing(),
                  const KitLabel('HOW IDEAS ARE CHOSEN RIGHT NOW'),
                  KitCard(child: _engine()),
                  const KitLabel('QUIETLY OUT OF ROTATION'),
                  KitCard(child: _hidden()),
                  const KitLabel('WHAT ELSE SHAPES AN IDEA'),
                  KitCard(child: _shapes()),
                  const KitLabel('AFTER YOU TRY SOMETHING'),
                  const _AfterTrying(),
                  const KitLabel('YOUR PHONE PATTERNS'),
                  KitCard(child: _phone()),
                  const KitLabel('MOMENTS, AND WHAT SOL IS TOLD'),
                  KitCard(child: _moments()),
                  const KitLabel('NEVER USED'),
                  KitCard(child: _never()),
                  const SizedBox(height: 18),
                  const Text(
                    'Your choices and phone patterns stay on this device. '
                    'Sol is told only what you switch on in What Sol '
                    'remembers.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: kitMuted,
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

  Widget _doing() {
    final m = profile.momentum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.totalAnswered > 0)
          KitCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.totalAccepted} accepted of '
                  '${profile.totalAnswered} answered, and how each kind '
                  'has gone:',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: kitSoft,
                  ),
                ),
                const SizedBox(height: 14),
                for (final entry in profile.typeAcceptance.entries)
                  _TypeRow(
                    type: entry.key,
                    typeName: _typeLabel(entry.key),
                    acceptance: entry.value,
                  ),
              ],
            ),
          )
        else
          const KitCard(
            child: _InfoRow(
              icon: Icons.hourglass_empty_rounded,
              color: kitAmber,
              text:
                  'No ideas answered yet. Accept or turn down a few and '
                  'this fills in.',
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            StatTile(
              value: '${m.checkInsLast14Days}',
              label: 'check-ins in 14 days',
              color: kitAmber,
              icon: Icons.edit_note_rounded,
            ),
            const SizedBox(width: 10),
            StatTile(
              value: '${m.restDaysLast14Days}',
              label: 'rest days taken',
              color: _blue,
              icon: Icons.bedtime_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _engine() {
    final engine = profile.engineState;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (engine.daysLeftOfStarterTour > 0) ...[
          _Meter(
            value:
                1 -
                engine.daysLeftOfStarterTour /
                    RecommendationEngine.starterTourDays,
            color: _green,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.route_rounded,
            color: _green,
            text:
                'You are in the gentle starter tour: short, easy ideas '
                'while Solace learns what fits. '
                '${engine.daysLeftOfStarterTour} '
                '${engine.daysLeftOfStarterTour == 1 ? 'day remains' : 'days remain'}.',
          ),
        ] else ...[
          _Meter(
            value: engine.exploreShare,
            marker: engine.exploreTargetShare,
            color: _blue,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.explore_outlined,
            color: _blue,
            text:
                'Roughly ${(engine.exploreShare * 100).round()}% of recent '
                'ideas were new to you, against a target of about '
                '${(engine.exploreTargetShare * 100).round()}%.',
          ),
        ],
        const SizedBox(height: 12),
        if (engine.typesClearingGate.isNotEmpty) ...[
          const _InfoRow(
            icon: Icons.verified_outlined,
            color: kitAmber,
            text: 'Enough good days to offer from experience:',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in engine.typesClearingGate)
                _Chip(_typeLabelFromName(name), kitAmber),
            ],
          ),
        ] else
          const _InfoRow(
            icon: Icons.verified_outlined,
            color: kitMuted,
            text:
                'No type has enough history yet to be offered from '
                'experience. Ideas are still being explored.',
          ),
        if (engine.effortCapped) ...[
          const SizedBox(height: 12),
          const _InfoRow(
            icon: Icons.speed_rounded,
            color: kitCoral,
            text:
                'A recent "too hard" keeps ideas gentle for a couple of '
                'weeks.',
          ),
        ],
      ],
    );
  }

  Widget _hidden() {
    if (profile.engineState.hiddenCount == 0) {
      return const _InfoRow(
        icon: Icons.visibility_outlined,
        color: _green,
        text:
            'Nothing is hidden. Everything in the library can currently be '
            'offered.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profile.neverSuggestedTypes.isNotEmpty)
          _InfoRow(
            icon: Icons.visibility_off_outlined,
            color: kitCoral,
            text:
                'You asked not to see: '
                '${profile.neverSuggestedTypes.join(', ')}. '
                'Those stay out until you change your baseline.',
          ),
        if (profile.shelvedActivities.isNotEmpty) ...[
          if (profile.neverSuggestedTypes.isNotEmpty)
            const SizedBox(height: 12),
          const _InfoRow(
            icon: Icons.inventory_2_outlined,
            color: kitMuted,
            text: 'Turned down three times, so no longer offered:',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final activity in profile.shelvedActivities)
                _Chip(activity.title, kitMuted),
            ],
          ),
        ],
      ],
    );
  }

  Widget _shapes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoRow(
          icon: Icons.schedule_rounded,
          color: _blue,
          text:
              'Time of day and the sleep hours you gave. Late, or soon '
              'after waking, ideas get smaller and gentler.',
        ),
        const SizedBox(height: 12),
        const _InfoRow(
          icon: Icons.mood_outlined,
          color: kitAmber,
          text:
              'Your latest mood word and how the last few days felt. A '
              'lower stretch means shorter ideas first.',
        ),
        if (signals.phonePatterns == PhoneSignal.on) ...[
          const SizedBox(height: 12),
          const _InfoRow(
            icon: Icons.phone_android_rounded,
            color: _green,
            text:
                'A short night, estimated from phone use, can count too. '
                'It only ever makes ideas gentler.',
          ),
        ],
        const SizedBox(height: 12),
        const _InfoRow(
          icon: Icons.info_outline_rounded,
          color: kitMuted,
          text:
              'A rough reading and a nudge, never a diagnosis. With only '
              'the clock to go on, Solace says so.',
        ),
      ],
    );
  }

  Widget _phone() {
    final (label, color, text) = switch (signals.phonePatterns) {
      PhoneSignal.off => (
        'Off',
        kitMuted,
        'Off. Solace reads nothing from your phone.',
      ),
      PhoneSignal.needsAccess => (
        'Needs access',
        kitCoral,
        'You said yes, but Android usage access is off for Solace, so '
            'nothing is being read.',
      ),
      PhoneSignal.on => (
        'On',
        _green,
        'On. Solace reads screen time, when you are active, an estimated '
            'night and kinds of app. It stays on this phone.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusPill(label, color: color),
        const SizedBox(height: 10),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w700,
            color: kitSoft,
          ),
        ),
        const SizedBox(height: 14),
        const _InfoRow(
          icon: Icons.person_outline_rounded,
          color: _blue,
          text:
              'Compared only with your own last few weeks, never with '
              'anyone else.',
        ),
        const SizedBox(height: 10),
        const _InfoRow(
          icon: Icons.chat_bubble_outline_rounded,
          color: kitAmber,
          text:
              'If several patterns shift together, Solace may ask once '
              'whether anything is going on. At most weekly, and you can '
              'turn it off.',
        ),
        const SizedBox(height: 10),
        const _InfoRow(
          icon: Icons.apps_rounded,
          color: _green,
          text:
              'Only totals for kinds of app are kept, not app names, unless '
              'you choose that.',
        ),
      ],
    );
  }

  Widget _moments() {
    final kept = signals.keptMoments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoRow(
          icon: Icons.favorite_border_rounded,
          color: kitCoral,
          text:
              'Solace may ask whether to remember something good. Only '
              'your yes keeps it, and hard topics are never offered.',
        ),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.bookmark_border_rounded,
          color: kept == 0 ? kitMuted : kitAmber,
          text: kept == 0
              ? 'No moments are kept right now.'
              : '$kept ${kept == 1 ? 'moment is' : 'moments are'} kept, in '
                    'your own words.',
        ),
        const SizedBox(height: 12),
        _InfoRow(
          icon: signals.snippetShared
              ? Icons.send_rounded
              : Icons.do_not_disturb_on_outlined,
          color: signals.snippetShared ? _blue : kitMuted,
          text: signals.snippetShared
              ? 'Sol is told a short note about how you like things.'
              : 'Sol is not told anything about you beyond the conversation '
                    'itself.',
        ),
        const SizedBox(height: 12),
        _InfoRow(
          icon: signals.momentsShared
              ? Icons.send_rounded
              : Icons.do_not_disturb_on_outlined,
          color: signals.momentsShared ? _blue : kitMuted,
          text: signals.momentsShared
              ? 'Sol is told your few most recent kept moments.'
              : 'Sol is not told your moments.',
        ),
        const SizedBox(height: 12),
        const _InfoRow(
          icon: Icons.manage_search_rounded,
          color: kitMuted,
          text:
              'What Sol remembers shows exactly what would be sent, and is '
              'where you change or delete any of it.',
        ),
      ],
    );
  }

  Widget _never() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(
          icon: Icons.apps_outage_rounded,
          color: kitCoral,
          text:
              'What is inside your other apps or messages, and where you '
              'are.',
        ),
        SizedBox(height: 12),
        _InfoRow(
          icon: Icons.mic_off_outlined,
          color: kitCoral,
          text:
              'Your microphone or camera, except when you start a voice or '
              'video check-in, send a voice message, or make a call.',
        ),
        SizedBox(height: 12),
        _InfoRow(
          icon: Icons.quiz_outlined,
          color: kitCoral,
          text: 'Questionnaire answers or scores. They are never sent to Sol.',
        ),
        SizedBox(height: 12),
        _InfoRow(
          icon: Icons.groups_outlined,
          color: kitCoral,
          text: 'Anything that compares you with other people.',
        ),
        SizedBox(height: 12),
        _InfoRow(
          icon: Icons.sentiment_neutral_rounded,
          color: kitCoral,
          text:
              'Emotion read from your words or voice. Labels on an entry '
              'are placeholders and shape nothing. If that changes, it will '
              'be explained here and be yours to switch off first.',
        ),
      ],
    );
  }
}

const _green = Color(0xFF4F9D76);
const _blue = Color(0xFF6E73C8);

/// An icon tile with one short line beside it.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(icon: icon, color: color, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: kitSoft,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

/// A slim filled bar, with an optional tick for a target.
class _Meter extends StatelessWidget {
  const _Meter({required this.value, required this.color, this.marker});

  final double value;
  final double? marker;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 14,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                height: 8,
                width: w * value.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              if (marker != null)
                Positioned(
                  left: (w * marker!.clamp(0.0, 1.0) - 1.5).clamp(0.0, w - 3),
                  child: Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: kitInk,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Felt lighter, felt heavier, did not say: what each does to the next pick.
class _AfterTrying extends StatelessWidget {
  const _AfterTrying();

  @override
  Widget build(BuildContext context) {
    Widget cell(IconData icon, Color color, String title, String body) {
      return Expanded(
        child: KitCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              IconTile(icon: icon, color: color, size: 38),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kitInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: kitSoft,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cell(
                Icons.trending_up_rounded,
                _green,
                'Lighter',
                'Counts a little for that kind',
              ),
              const SizedBox(width: 8),
              cell(
                Icons.trending_down_rounded,
                kitCoral,
                'Heavier',
                'Counts a little against it',
              ),
              const SizedBox(width: 8),
              cell(
                Icons.remove_rounded,
                kitMuted,
                'Not said',
                'Nothing is assumed',
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'Skipping the question never counts as it not working.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: kitMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The interactive demo: change a pretend situation, watch the rules respond.
/// Built from the engine's own constants; it shows the rules, not a forecast.
class _TryIt extends StatefulWidget {
  const _TryIt();

  @override
  State<_TryIt> createState() => _TryItState();
}

class _TryItState extends State<_TryIt> {
  CapacityLevel _capacity = CapacityLevel.high;
  bool _tooHard = false;
  bool _noMovement = false;

  static const _levels = [
    (CapacityLevel.low, 'Low energy', Icons.battery_2_bar_rounded),
    (CapacityLevel.medium, 'Middling', Icons.battery_4_bar_rounded),
    (CapacityLevel.high, 'Plenty', Icons.battery_full_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final demo = DecisionDemo(
      capacity: _capacity,
      recentTooHard: _tooHard,
      avoidedMovement: _noMovement,
    );
    final max = demo.maxMinutes;
    return KitCard(
      color: const Color(0xFFFFFBF2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pretend today looks like this:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: kitInk,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (level, label, icon) in _levels)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: level == CapacityLevel.high ? 0 : 6,
                    ),
                    child: _Choice(
                      key: ValueKey('demo-${level.name}'),
                      icon: icon,
                      label: label,
                      selected: _capacity == level,
                      onTap: () => setState(() => _capacity = level),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Toggle(
                key: const ValueKey('demo-hard'),
                label: 'Marked one as Too hard',
                on: _tooHard,
                onTap: () => setState(() => _tooHard = !_tooHard),
              ),
              _Toggle(
                key: const ValueKey('demo-nomove'),
                label: 'Hide movement ideas',
                on: _noMovement,
                onTap: () => setState(() => _noMovement = !_noMovement),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: kitLine),
          const SizedBox(height: 14),
          const Text(
            'IDEAS SOLACE WOULD FAVOUR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: kitMuted,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18, color: kitAmber),
              const SizedBox(width: 8),
              Text(
                max == null ? 'Any length' : 'Up to $max min',
                key: const ValueKey('demo-length'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kitInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Meter(value: max == null ? 1 : max / 20, color: kitAmber),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.speed_rounded, size: 18, color: _blue),
              const SizedBox(width: 8),
              Text(
                demo.gentleEffortOnly ? 'Gentle effort only' : 'Any effort',
                key: const ValueKey('demo-effort'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kitInk,
                ),
              ),
              const Spacer(),
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(left: 4),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (demo.gentleEffortOnly ? i < 1 : true)
                        ? _blue
                        : _blue.withValues(alpha: 0.15),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in ActivityType.values)
                _KindDot(
                  type: type,
                  out: !demo.kindsInPlay.contains(type),
                  leaned: demo.leaned.contains(type),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            demo.leansGentleKinds
                ? 'Ringed kinds ask least, so they get a small lean.'
                : 'No kind is leaned towards.',
            key: const ValueKey('demo-kinds-note'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kitSoft,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'A picture of the rules, not your live data. Low energy comes '
            'from the hour, the sleep hours you gave, and your latest mood '
            'word.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: kitMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? kitAmber.withValues(alpha: 0.18) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? kitAmber : kitLine,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: selected ? kitAmber : kitMuted),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? kitInk : kitSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.on,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _blue.withValues(alpha: 0.16) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? _blue : kitLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: on ? _blue : kitMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: on ? kitInk : kitSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindDot extends StatelessWidget {
  const _KindDot({required this.type, required this.out, required this.leaned});

  final ActivityType type;
  final bool out;
  final bool leaned;

  @override
  Widget build(BuildContext context) {
    final color = out ? kitMuted : kitAmber;
    return Semantics(
      label:
          '${_typeLabel(type)}'
          '${out
              ? ', out'
              : leaned
              ? ', leaned towards'
              : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: out ? 0.08 : 0.16),
          border: Border.all(
            color: leaned ? kitAmber : Colors.transparent,
            width: 2.2,
          ),
        ),
        child: Icon(
          _typeIcon(type),
          size: 20,
          color: out ? kitMuted.withValues(alpha: 0.4) : kitAmber,
        ),
      ),
    );
  }
}

IconData _typeIcon(ActivityType type) => switch (type) {
  ActivityType.movement => Icons.directions_walk_rounded,
  ActivityType.social => Icons.people_outline_rounded,
  ActivityType.creative => Icons.brush_outlined,
  ActivityType.nature => Icons.park_outlined,
  ActivityType.mindfulness => Icons.self_improvement_rounded,
  ActivityType.learning => Icons.menu_book_outlined,
  ActivityType.productivity => Icons.checklist_rounded,
};

class _PreferenceChips extends StatelessWidget {
  const _PreferenceChips({required this.profile});

  final BehavioralProfile profile;

  @override
  Widget build(BuildContext context) {
    final preferences = profile.preferences;
    final rows = <(String, IconData, Color, List<String>)>[
      (
        'You like',
        Icons.favorite_border_rounded,
        kitCoral,
        preferences.preferredActivities,
      ),
      ('Within', Icons.timelapse_rounded, _blue, preferences.constraints),
      (
        'Tone',
        Icons.chat_bubble_outline_rounded,
        _green,
        preferences.interactionPreferences,
      ),
      (
        'Never suggest',
        Icons.block_rounded,
        kitMuted,
        preferences.neverSuggest,
      ),
    ];
    if (!rows.any((row) => row.$4.isNotEmpty)) {
      return const _InfoRow(
        icon: Icons.tune_rounded,
        color: kitMuted,
        text: 'No preferences recorded yet.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, icon, color, values) in rows)
          if (values.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(icon: icon, color: color, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$label:',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: kitInk,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final value in values) _Chip(value, color),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        if (!profile.preferences.completed)
          const _InfoRow(
            icon: Icons.pending_outlined,
            color: kitAmber,
            text:
                'Preferences are not finished yet, so the app is using '
                'editorial picks until then.',
          ),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.typeName,
    required this.acceptance,
  });

  final ActivityType type;
  final String typeName;
  final TypeAcceptance acceptance;

  @override
  Widget build(BuildContext context) {
    final decided = acceptance.completed + acceptance.declined > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          IconTile(icon: _typeIcon(type), color: kitAmber, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeName,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: kitInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  acceptance.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kitSoft,
                  ),
                ),
                if (decided) ...[
                  const SizedBox(height: 6),
                  _Meter(value: acceptance.completionShare, color: kitAmber),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _typeLabel(ActivityType type) => switch (type) {
  ActivityType.movement => 'Movement',
  ActivityType.social => 'Social',
  ActivityType.creative => 'Creative',
  ActivityType.nature => 'Nature',
  ActivityType.mindfulness => 'Mindfulness',
  ActivityType.learning => 'Learning',
  ActivityType.productivity => 'Productivity',
};

String _typeLabelFromName(String name) {
  for (final type in ActivityType.values) {
    if (type.name == name) return _typeLabel(type);
  }
  return name;
}
