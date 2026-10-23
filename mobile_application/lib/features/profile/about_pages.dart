import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';

/// The About group: what this app is, the legal pages, and the FAQ.
///
/// Three separate pages because they have different jobs: [AboutSolacePage] is
/// orientation, the other two are reference material someone arrives at
/// deliberately.
///
/// ## Status
///
/// [TermsAndPrivacyPage] and [FaqPage] are **drafts**. They describe what the
/// app does today in plain words, carry a visible marker saying so, and are not
/// legal text. Nothing here has been reviewed by anyone.
///
/// Deliberately restrained about claims. Every statement is something the code
/// does today: local storage, no account, no clinical claims. No encryption
/// claims and no compliance claims, because those are not settled and a
/// settings page is the last place to overstate them.

const _green = Color(0xFF4F9D76);
const _blue = Color(0xFF6E73C8);

/// Shared chrome: a painted hero and a scrolling body.
class _AboutScaffold extends StatelessWidget {
  const _AboutScaffold({
    required this.scene,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final HeroScene scene;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SolaceColors.from(context).background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          PageHero(scene: scene, title: title, subtitle: subtitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// The small banner that says a page is not finished.
class _DraftBanner extends StatelessWidget {
  const _DraftBanner(this.what);

  final String what;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: KitCard(
        color: const Color(0xFFFFF6E4),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const IconTile(
              icon: Icons.edit_note_rounded,
              color: kitAmber,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Draft. $what Not reviewed, not legal text.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A6A20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An icon tile with one short line, optionally with a bold lead word.
class _Line extends StatelessWidget {
  const _Line(this.icon, this.color, this.text, {this.lead});

  final IconData icon;
  final Color color;
  final String text;
  final String? lead;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(icon: icon, color: color, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  if (lead != null)
                    TextSpan(
                      text: '$lead\n',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kitInk,
                      ),
                    ),
                  TextSpan(
                    text: text,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: kitSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stack extends StatelessWidget {
  const _Stack(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => KitCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          children[i],
        ],
      ],
    ),
  );
}

/// A tile in a two-column grid: icon beside a short label.
class _GridTile extends StatelessWidget {
  const _GridTile(this.icon, this.color, this.label);

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: kitInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid(this.tiles);

  final List<_GridTile> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: 8));
    }
    return KitCard(child: Column(children: rows));
  }
}

/// One of the two people who built the app.
class _Developer extends StatelessWidget {
  const _Developer({
    required this.initials,
    required this.name,
    required this.roll,
    required this.color,
  });

  final String initials;
  final String name;
  final String roll;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: KitCard(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.55), color],
                ),
              ),
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: kitInk,
              ),
            ),
            const SizedBox(height: 6),
            StatusPill(roll, color: color),
          ],
        ),
      ),
    );
  }
}

/// What this app is, and what it is not.
///
/// Everything here is verifiable in the code today. No capability is described
/// that the app does not currently have.
class AboutSolacePage extends StatelessWidget {
  const AboutSolacePage({super.key});

  /// Shown as the trailing value on the settings row. There is no build-info
  /// package in the dependency list, so this is a constant rather than a value
  /// read from the bundle, and it has to be kept in step with pubspec.yaml by
  /// hand. Noted here because that is the kind of thing that silently rots.
  static const version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    return _AboutScaffold(
      scene: HeroScene.about,
      title: 'About Solace',
      subtitle: 'A quiet place to notice how you are.',
      children: [
        const KitLabel('WHAT IT DOES'),
        const _Stack([
          _Line(
            Icons.edit_note_rounded,
            kitAmber,
            'Brief check-ins and a journal of how you are.',
            lead: 'Reflect',
          ),
          _Line(
            Icons.spa_outlined,
            _green,
            'Small things to try, from a reviewed set.',
            lead: 'Try',
          ),
          _Line(
            Icons.chat_bubble_outline_rounded,
            _blue,
            'Talk with Sol, by text, voice or a call.',
            lead: 'Talk',
          ),
        ]),
        const KitLabel('WHAT IT IS NOT'),
        const _Grid([
          _GridTile(Icons.psychology_alt_outlined, kitCoral, 'Not a therapist'),
          _GridTile(Icons.medical_services_outlined, kitCoral, 'Not a doctor'),
          _GridTile(
            Icons.emergency_outlined,
            kitCoral,
            'Not an emergency service',
          ),
          _GridTile(Icons.fact_check_outlined, kitCoral, 'Does not diagnose'),
        ]),
        const KitLabel('WHERE YOUR DATA LIVES'),
        const _Stack([
          _Line(
            Icons.phone_android_rounded,
            _green,
            'Reflections, check-ins and settings. No account, no password.',
            lead: 'On this phone',
          ),
          _Line(
            Icons.cloud_queue_rounded,
            _blue,
            'Conversations with Sol go to the companion service you connect '
            'to. More about you goes only if you switch it on.',
            lead: 'Sent to answer you',
          ),
          _Line(
            Icons.delete_outline_rounded,
            kitCoral,
            'Delete entries and conversations one by one.',
            lead: 'Yours to remove',
          ),
        ]),
        const KitLabel('MADE BY'),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Developer(
              initials: 'RR',
              name: 'Rafsan Riasat',
              roll: '2207006',
              color: kitAmber,
            ),
            SizedBox(width: 10),
            _Developer(
              initials: 'DS',
              name: 'Dadhichi Sarker',
              roll: '2207118',
              color: _blue,
            ),
          ],
        ),
        const SizedBox(height: 10),
        KitCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const IconTile(
                icon: Icons.school_outlined,
                color: _green,
                size: 38,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'KUET\n',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: kitInk,
                        ),
                      ),
                      TextSpan(
                        text: 'CSE · Batch 2K22',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: kitSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StatusPill('v$version', color: kitAmber),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Local-first and private',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: kitMuted,
          ),
        ),
      ],
    );
  }
}

/// Terms and privacy.
///
/// **Draft.** The structure is final enough to be written into, the words are
/// not. Nothing here should be relied on.
class TermsAndPrivacyPage extends StatelessWidget {
  const TermsAndPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _AboutScaffold(
      scene: HeroScene.terms,
      title: 'Terms & privacy',
      subtitle: 'What is kept, where it goes, what you control.',
      children: [
        const _DraftBanner(
          'This describes what the app does today. The final terms are '
          'written once the app is finished.',
        ),
        const KitLabel('STAYS ON THIS PHONE'),
        const _Grid([
          _GridTile(Icons.edit_note_rounded, kitAmber, 'Check-ins and journal'),
          _GridTile(Icons.forum_outlined, _blue, 'Chats and short notes'),
          _GridTile(
            Icons.bookmark_border_rounded,
            kitCoral,
            'Moments you kept',
          ),
          _GridTile(Icons.thumbs_up_down_outlined, _green, 'Answers to ideas'),
          _GridTile(Icons.settings_outlined, kitMuted, 'Settings, sleep hours'),
          _GridTile(Icons.contacts_outlined, kitAmber, 'Emergency contacts'),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'With phone patterns on: daily totals of screen time, activity, an '
            'estimated night and kinds of app. App names only if you choose.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: kitMuted,
            ),
          ),
        ),
        const KitLabel('GOES TO THE COMPANION SERVICE'),
        const _Stack([
          _Line(
            Icons.chat_bubble_outline_rounded,
            _blue,
            'Messages, and voice you send in a chat or call, so it can answer.',
            lead: 'To be answered',
          ),
          _Line(
            Icons.summarize_outlined,
            _blue,
            'When a chat gets long, older messages go once more to write a '
            'short note.',
            lead: 'To summarise',
          ),
        ]),
        const KitLabel('ONLY IF YOU SWITCH IT ON'),
        const _Stack([
          _Line(
            Icons.notes_rounded,
            _green,
            'A short note about how you like things.',
            lead: 'Your note',
          ),
          _Line(
            Icons.favorite_border_rounded,
            _green,
            'Your few most recent kept moments. What Sol remembers shows them '
            'word for word.',
            lead: 'Kept moments',
          ),
        ]),
        const KitLabel('NEVER COLLECTED'),
        const _Grid([
          _GridTile(
            Icons.apps_outage_rounded,
            kitCoral,
            'Other apps, messages',
          ),
          _GridTile(Icons.location_off_outlined, kitCoral, 'Where you are'),
          _GridTile(
            Icons.contact_phone_outlined,
            kitCoral,
            'Your contact list',
          ),
          _GridTile(Icons.groups_outlined, kitCoral, 'Comparisons with others'),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'The microphone and camera run only when you start a voice or '
            'video check-in, send a voice message, or make a call.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: kitMuted,
            ),
          ),
        ),
        const KitLabel('YOUR CONTROLS'),
        const _Stack([
          _Line(
            Icons.delete_outline_rounded,
            kitCoral,
            'Delete a journal entry or a conversation.',
          ),
          _Line(
            Icons.auto_delete_outlined,
            kitCoral,
            'Forget any moment or note, or delete stored phone patterns.',
          ),
          _Line(
            Icons.toggle_off_outlined,
            kitAmber,
            'Turn each optional thing off. Everything Solace keeps lists each '
            'kind and where to manage it.',
          ),
        ]),
        const KitLabel('STILL TO WRITE'),
        const KitCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill('Children', color: kitMuted),
              StatusPill('Changes', color: kitMuted),
              StatusPill('Contact', color: kitMuted),
            ],
          ),
        ),
      ],
    );
  }
}

/// Frequently asked questions.
///
/// **Draft.** Written against what the app does today, so it is not empty, but
/// it is not the final set and the questions have not been chosen from anything
/// real — there is no support inbox to draw them from yet.
class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _AboutScaffold(
      scene: HeroScene.faq,
      title: 'Frequently asked',
      subtitle: 'Tap a question.',
      children: const [
        _DraftBanner('These questions are placeholders.'),
        SizedBox(height: 12),
        _Faq(
          icon: Icons.psychology_alt_outlined,
          color: kitCoral,
          question: 'Is Solace a replacement for therapy?',
          answer:
              'No. It is a reflection tool and cannot diagnose or treat '
              'anything. If you are in crisis, please use the support page.',
        ),
        _Faq(
          icon: Icons.phone_android_rounded,
          color: _green,
          question: 'Where are my reflections stored?',
          answer:
              'On this device. Solace has no account system. Conversations '
              'with Sol are sent to the companion service to be answered.',
        ),
        _Faq(
          icon: Icons.ios_share_rounded,
          color: _blue,
          question: 'Can I take my data somewhere else?',
          answer:
              'Yes. Export gives you a formatted journal or a complete '
              'backup.',
        ),
        _Faq(
          icon: Icons.lightbulb_outline_rounded,
          color: kitAmber,
          question: 'Why am I seeing this suggestion?',
          answer:
              'The How Solace decides page explains the reasoning, and '
              'lists anything currently withheld from you.',
        ),
        _Faq(
          icon: Icons.replay_rounded,
          color: kitCoral,
          question: 'I said I did not want something. Why is it still here?',
          answer:
              'Declines are remembered for a set period and then the '
              'suggestion is allowed to return.',
        ),
        _Faq(
          icon: Icons.wifi_off_rounded,
          color: _blue,
          question: 'Does Solace work offline?',
          answer:
              'Reflection, check-in and written journals work offline. Voice and '
              'video journals do too, once you have downloaded the offline '
              'models (Permissions & privacy): they are kept on your phone '
              'and read when your companion server is back. A live '
              'conversation needs a connection.',
        ),
      ],
    );
  }
}

/// One question that opens to its answer.
class _Faq extends StatefulWidget {
  const _Faq({
    required this.icon,
    required this.color,
    required this.question,
    required this.answer,
  });

  final IconData icon;
  final Color color;
  final String question;
  final String answer;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KitCard(
        padding: const EdgeInsets.all(14),
        onTap: () => setState(() => _open = !_open),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(icon: widget.icon, color: widget.color, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.question,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: kitInk,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: kitMuted,
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10, left: 50),
                      child: Text(
                        widget.answer,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: kitSoft,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
