import 'package:flutter/material.dart';

import '../../core/models/activity.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/page_back_button.dart';
import '../../domain/profile/behavioral_profile.dart';

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
      appBar: AppBar(
        leading: const PageBackButton(),
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
            ..._decisionSections(colors),
            const SizedBox(height: 8),
            Text(
              'Your choices and your phone patterns stay on this device. What '
              'Sol is told is only what you switch on in What Sol remembers. '
              'None of it describes your mental health.',
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

  /// The parts of the picture beyond the ideas themselves: how capacity, phone
  /// patterns, moments, and what Sol is told fit in, in the same plain words and
  /// with the same honesty about what is and is not used.
  List<Widget> _decisionSections(SolaceColors colors) {
    return [
      _Section(
        title: 'WHAT ELSE SHAPES AN IDEA',
        children: [
          const _Bullet(
            text: 'The time of day and the sleep hours you gave. Late at night, '
                'or soon after waking, Solace leans toward smaller, gentler '
                'ideas.',
          ),
          const _Bullet(
            text: 'Your latest mood word and how your last few days have felt. '
                'A lower stretch means shorter ideas first.',
          ),
          if (signals.phonePatterns == PhoneSignal.on)
            const _Bullet(
              text: 'A short night, estimated from when your phone was last '
                  'used and next picked up, can count too. It only ever makes '
                  'ideas gentler.',
            ),
          const _Bullet(
            text: 'This is a rough reading and a nudge, never a diagnosis. '
                'When Solace is only going on the clock, it says so.',
          ),
        ],
      ),
      _Section(
        title: 'AFTER YOU TRY SOMETHING',
        children: [
          Text(
            'If you say how you felt afterwards, a lift counts a little in '
            'favour of that kind of idea and a heavier word counts a little '
            'against it. If you do not say, nothing is assumed: skipping the '
            'question never counts as it not working.',
            style: _bodyStyle(colors),
          ),
        ],
      ),
      _Section(
        title: 'YOUR PHONE PATTERNS',
        children: [
          Text(
            switch (signals.phonePatterns) {
              PhoneSignal.off =>
                'Off. Solace reads nothing from your phone. Turning it on lets '
                    'Solace learn your own usual rhythm: screen time, when you '
                    'are active, an estimated night, and which kinds of app. '
                    'All of it stays on this phone.',
              PhoneSignal.needsAccess =>
                'You said yes, but Android usage access is off for Solace, so '
                    'nothing is being read.',
              PhoneSignal.on =>
                'On. Solace reads screen time, when you are active, when the '
                    'phone goes down overnight (an estimate), and which kind '
                    'of app was open. It stays on this phone.',
            },
            style: _bodyStyle(colors),
          ),
          const SizedBox(height: 10),
          const _Bullet(
            text: 'It compares you only with your own last few weeks, never '
                'with anyone else, and it never tells you what amount is right.',
          ),
          const _Bullet(
            text: 'When more than one kind of pattern shifts at once, Solace '
                'may ask once whether anything is going on. Never about a '
                'single odd day, and never more than once a week. You can '
                'turn the question off.',
          ),
          const _Bullet(
            text: 'Names of apps are not kept unless you choose that. '
                'Otherwise only totals for kinds of app, like social or video.',
          ),
        ],
      ),
      _Section(
        title: 'MOMENTS, AND WHAT SOL IS TOLD',
        children: [
          const _Bullet(
            text: 'When you write about something good, Solace may ask whether '
                'to remember it. Only your yes keeps it, and hard topics are '
                'never offered.',
          ),
          _Bullet(
            text: signals.keptMoments == 0
                ? 'No moments are kept right now.'
                : '${signals.keptMoments} '
                      '${signals.keptMoments == 1 ? 'moment is' : 'moments are'} '
                      'kept, in your own words.',
          ),
          _Bullet(
            text: signals.snippetShared
                ? 'Sol is told a short note about how you like things.'
                : 'Sol is not told anything about you beyond the conversation '
                      'itself.',
          ),
          _Bullet(
            text: signals.momentsShared
                ? 'Sol is told your few most recent kept moments.'
                : 'Sol is not told your moments.',
          ),
          const _Bullet(
            text: 'What Sol remembers shows exactly what would be sent, and is '
                'where you change or delete any of it.',
          ),
        ],
      ),
      _Section(
        title: 'NEVER USED',
        children: [
          const _Bullet(
            text: 'What is inside your other apps or messages, and where you '
                'are.',
          ),
          const _Bullet(
            text: 'Your microphone or camera, except when you start a voice or '
                'video check-in, send a voice message, or make a call.',
          ),
          const _Bullet(
            text: 'Questionnaire answers or scores. They are never sent to '
                'Sol.',
          ),
          const _Bullet(
            text: 'Anything that compares you with other people.',
          ),
          const _Bullet(
            text: 'Emotion read from your words or voice. Today your mood '
                'words are the ones you choose. Any labels shown on an entry '
                'are placeholders and shape nothing. If that changes, it will '
                'be explained here and be yours to switch off first.',
          ),
        ],
      ),
    ];
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
