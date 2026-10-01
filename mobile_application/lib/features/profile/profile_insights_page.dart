import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/theme/solace_palette.dart';
import '../../domain/profile/behavioral_profile.dart';

/// The behavioral profile: what the user chose, what they have been doing,
/// and how the app's suggestions currently reflect it.
///
/// Deliberately not clinical and not a scorecard. Every number on this page is
/// the same one the recommendation engine uses, so the page can say honestly
/// why the app is doing what it does — and small samples stay small: shares
/// come with counts, and types with no verdicts say so.
class ProfileInsightsPage extends StatelessWidget {
  const ProfileInsightsPage({required this.profile, super.key});

  final BehavioralProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('How Solace decides'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            _Section(
              title: 'WHAT YOU TOLD US',
              children: [
                Text(
                  'Your choices from the first-run reflections. '
                  'Change them anytime from your baseline.',
                  style: _bodyStyle(colors),
                ),
                const SizedBox(height: 12),
                _PreferenceChips(profile: profile),
                if (!profile.preferences.completed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Preferences step not finished yet — the app is '
                      'running on editorial picks until then.',
                      style: _bodyStyle(colors),
                    ),
                  ),
              ],
            ),
            _Section(
              title: 'WHAT YOU HAVE BEEN DOING',
              children: [
                if (profile.totalAnswered == 0)
                  Text(
                    'No ideas answered yet. Once you accept or turn down a '
                    'few, this section shows what tends to work for you.',
                    style: _bodyStyle(colors),
                  )
                else ...[
                  Text(
                    '${profile.totalAccepted} accepted of '
                    '${profile.totalAnswered} answered, and how each kind '
                    'has gone:',
                    style: _bodyStyle(colors),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in profile.typeAcceptance.entries)
                    _TypeRow(
                      typeName: _typeLabel(entry.key),
                      acceptance: entry.value,
                    ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat(
                      value: '${profile.momentum.checkInsLast14Days}',
                      label: 'check-ins\nin 14 days',
                    ),
                    const SizedBox(width: 12),
                    _Stat(
                      value: '${profile.momentum.restDaysLast14Days}',
                      label: 'rest days\ntaken',
                    ),
                  ],
                ),
              ],
            ),
            _Section(
              title: 'HOW IDEAS ARE CHOSEN RIGHT NOW',
              children: [
                ..._engineLines(profile, colors),
              ],
            ),
            _Section(
              title: 'QUIETLY OUT OF ROTATION',
              children: [
                if (profile.engineState.hiddenCount == 0)
                  Text(
                    'Nothing is hidden. Everything in the library can '
                    'currently be offered.',
                    style: _bodyStyle(colors),
                  )
                else ...[
                  if (profile.neverSuggestedTypes.isNotEmpty)
                    Text(
                      'You asked not to see: '
                      '${profile.neverSuggestedTypes.join(', ')}. '
                      'Those stay out until you change your baseline.',
                      style: _bodyStyle(colors),
                    ),
                  if (profile.shelvedActivities.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Turned down three times, so no longer offered:',
                      style: _bodyStyle(colors),
                    ),
                    const SizedBox(height: 6),
                    for (final activity in profile.shelvedActivities)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('· ${activity.title}', style: _bodyStyle(colors)),
                      ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Everything here stays on this device. It describes your '
              'choices, not your mental health.',
              style: _bodyStyle(colors).copyWith(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _bodyStyle(SolaceColors colors) {
    return TextStyle(
      fontSize: 13,
      height: 1.5,
      color: colors.mutedInk,
      fontWeight: FontWeight.w600,
    );
  }

  List<Widget> _engineLines(BehavioralProfile profile, SolaceColors colors) {
    final engine = profile.engineState;
    final lines = <Widget>[];

    if (engine.daysLeftOfStarterTour > 0) {
      lines.add(
        _Bullet(
          text: engine.profileAgeDays == 0
              ? 'You are in the gentle starter tour — short, easy ideas '
                  'while Solace learns what fits you. '
                  '${engine.daysLeftOfStarterTour} days remain.'
              : '${engine.daysLeftOfStarterTour} days left of the starter '
                  'tour, then ideas start drawing on what has worked before.',
        ),
      );
    } else {
      final sharePercent = (engine.exploreShare * 100).round();
      final targetPercent = (engine.exploreTargetShare * 100).round();
      lines.add(
        _Bullet(
          text: 'Roughly $sharePercent% of recent ideas were new-to-you, '
              'against a target of about $targetPercent%. The rest are '
              'drawn from what has gone well before.',
        ),
      );
    }

    if (engine.typesClearingGate.isNotEmpty) {
      lines.add(
        _Bullet(
          text: 'Enough good days so far to offer, from experience: '
              '${engine.typesClearingGate.map(_typeLabelFromName).join(', ')}.',
        ),
      );
    } else {
      lines.add(
        const _Bullet(
          text: 'No type has enough history yet to be offered from '
              'experience — ideas are still being explored.',
        ),
      );
    }

    if (engine.effortCapped) {
      lines.add(
        const _Bullet(
          text: 'A recent "too hard" has ideas capped at gentle options '
              'for a couple of weeks.',
        ),
      );
    }

    return lines;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: Color(0xFFBCAC8E),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFF7F2E6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceChips extends StatelessWidget {
  const _PreferenceChips({required this.profile});

  final BehavioralProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    final preferences = profile.preferences;
    final rows = <(String, List<String>)>[
      ('You like', preferences.preferredActivities),
      ('Within', preferences.constraints),
      ('Tone', preferences.interactionPreferences),
      ('Never suggest', preferences.neverSuggest),
    ];
    final any = rows.any((row) => row.$2.isNotEmpty);
    if (!any) {
      return Text(
        'No preferences recorded yet.',
        style: TextStyle(fontSize: 13, color: colors.mutedInk),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, values) in rows)
          if (values.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  Text(
                    '$label:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: colors.ink,
                    ),
                  ),
                  for (final value in values)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3DC),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8A6A1C),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.typeName, required this.acceptance});

  final String typeName;
  final TypeAcceptance acceptance;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  typeName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
              ),
              Text(
                acceptance.subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.mutedInk,
                ),
              ),
            ],
          ),
          if (acceptance.completed + acceptance.declined > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: acceptance.completionShare,
                minHeight: 5,
                backgroundColor: colors.mutedInk.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(colors.amber),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9EE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF7EBCE)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB57A12),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.mutedInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('·  ', style: TextStyle(color: colors.amber, height: 1.5)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: colors.mutedInk,
              ),
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
