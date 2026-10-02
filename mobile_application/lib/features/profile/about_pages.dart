import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';

/// The About group: what this app is, the legal pages, and the FAQ.
///
/// Three separate pages rather than one, because they have genuinely different
/// jobs and different audiences: [AboutSolacePage] is orientation, the other two
/// are reference material someone arrives at deliberately.
///
/// ## Status
///
/// [TermsAndPrivacyPage] and [FaqPage] are **drafts**. They carry placeholder
/// copy and a visible marker saying so. They are not legal text, they have not
/// been reviewed by anyone, and they must not ship as-is. The structure is here
/// so the real writing has somewhere to land.
///
/// Deliberately restrained about claims. Every statement in [AboutSolacePage] is
/// something the code actually does today — local storage, no account, no
/// clinical claims. No encryption-at-rest claims, no compliance claims, and
/// nothing about what the companion server does, because those are not settled
/// and a settings page is the last place to overstate them.

/// Shared chrome for the three About pages.
///
/// A real navigation bar rather than a sheet: these are documents you read and
/// scroll, and the settings sheet is a fixed-height `Column` that overflows with
/// anything longer than a few controls.
class _AboutScaffold extends StatelessWidget {
  const _AboutScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SolaceColors.from(context).background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF4A3728),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Color(0xFF332C21),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section heading inside an About page.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 10, left: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: Color(0xFFBCAC8E),
        ),
      ),
    );
  }
}

/// Body copy inside an About page.
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.55,
          fontWeight: FontWeight.w600,
          color: Color(0xFF5C4A38),
        ),
      ),
    );
  }
}

/// The banner that says a page is not finished.
///
/// Visible rather than a code comment. A draft legal page that looks finished is
/// worse than no page at all, because someone will rely on it.
class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.what});

  final String what;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF6E2BC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.edit_note_rounded,
            size: 19,
            color: Color(0xFFB57A12),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Draft. $what This has not been reviewed and is not legal text.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A6A20),
              ),
            ),
          ),
        ],
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
    return const _AboutScaffold(
      title: 'About Solace',
      children: [
        _DraftBanner(
          what: 'This description will be rewritten once the app is finished.',
        ),
        _SectionHeading('WHAT THIS IS'),
        _Body(
          'Solace is a private place to notice how you are doing. It holds '
          'brief reflections, tracks what you tell it, and offers small things '
          'to try.',
        ),
        _Body(
          'It is a reflection tool. It is not a therapist, a doctor, or an '
          'emergency service, and it does not diagnose anything.',
        ),
        _SectionHeading('WHERE YOUR DATA IS'),
        _Body(
          'Your reflections, check-ins and settings are stored on this device. '
          'There is no account to create and no password.',
        ),
        _Body(
          'Conversations with Sol are the exception: they go to the companion '
          'service you connect to, which writes the replies. Anything more '
          'about you is sent only if you switch it on in What Sol remembers.',
        ),
        _Body(
          'You can export what you have written at any time, delete journal '
          'entries and conversations one by one, and see everything Solace '
          'keeps on one page.',
        ),
        _SectionHeading('HOW SUGGESTIONS ARE CHOSEN'),
        _Body(
          'Solace suggests small activities from a reviewed set. Early on it '
          'shows a general starter set. What you accept, skip or rate shapes '
          'what it offers afterwards, and things you have said you do not want '
          'are not offered again for a while.',
        ),
        _Body(
          'The How Solace decides page in settings shows this in detail, '
          'including anything currently hidden from you.',
        ),
        _SectionHeading('VERSION'),
        _Body('Solace $version · Local-first and private'),
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
    return const _AboutScaffold(
      title: 'Terms & privacy',
      children: [
        _DraftBanner(
          what: 'This describes what the app does today, in plain words. The '
              'final terms and privacy policy are written once the app is '
              'finished.',
        ),
        _SectionHeading('WHAT IS STORED'),
        _Body(
          'On this device: your check-ins and journal entries with the mood '
          'word you chose, your conversations with Sol and any short notes '
          'Sol keeps on long ones, the moments you chose to keep, your answers '
          'to suggestions, your settings and sleep hours, and emergency '
          'contacts. If you turn phone patterns on: daily totals of screen '
          'time, when you are active, an estimated night, and time by kind of '
          'app. App names are kept only if you choose that.',
        ),
        _SectionHeading('WHERE IT GOES'),
        _Body(
          'Messages you send in a conversation, and voice you send in a chat or '
          'call, go to the companion service to be answered. When a '
          'conversation gets long, older messages are sent to it once more to '
          'write a short note.',
        ),
        _Body(
          'Two more things are sent only if you switch them on in What Sol '
          'remembers: a short note about how you like things, and your few most '
          'recent kept moments. What would be sent is shown there, word for '
          'word. Phone patterns, journal entries and check-ins stay on this '
          'device.',
        ),
        _SectionHeading('WHAT IS NOT COLLECTED'),
        _Body(
          'What is inside your other apps or messages, where you are, your '
          'phone contact list, and anything that compares you with other '
          'people. The microphone and camera are used only when you start a voice or video '
          'check-in, send a voice message, or make a call. The Permissions page '
          'and How Solace decides say the same.',
        ),
        _SectionHeading('YOUR RIGHTS'),
        _Body(
          'You can export your reflections, delete a journal entry or a '
          'conversation, forget any moment or note, delete stored phone '
          'patterns, and turn each optional thing off. Everything Solace keeps '
          'lists each kind and where to manage it.',
        ),
        _SectionHeading('CHILDREN'),
        _Body('Placeholder.'),
        _SectionHeading('CHANGES'),
        _Body('Placeholder.'),
        _SectionHeading('CONTACT'),
        _Body('Placeholder. No address exists yet.'),
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
    return const _AboutScaffold(
      title: 'Frequently asked',
      children: [
        _DraftBanner(
          what: 'These questions are placeholders. The real set has not been '
              'written.',
        ),
        _Faq(
          question: 'Is Solace a replacement for therapy?',
          answer: 'No. It is a reflection tool and cannot diagnose or treat '
              'anything. If you are in crisis, please use the support page.',
        ),
        _Faq(
          question: 'Where are my reflections stored?',
          answer: 'On this device. Solace has no account system. Conversations '
              'with Sol are sent to the companion service to be answered.',
        ),
        _Faq(
          question: 'Can I take my data somewhere else?',
          answer: 'Yes. Export gives you a formatted journal or a complete '
              'backup.',
        ),
        _Faq(
          question: 'Why am I seeing this suggestion?',
          answer: 'The How Solace decides page explains the reasoning, and '
              'lists anything currently withheld from you.',
        ),
        _Faq(
          question: 'I said I did not want something. Why is it still here?',
          answer: 'Declines are remembered for a set period and then the '
              'suggestion is allowed to return.',
        ),
        _Faq(
          question: 'Does Solace work offline?',
          answer: 'Reflection, check-in and the journal work offline. A live '
              'conversation needs a connection.',
        ),
      ],
    );
  }
}

/// One question and its answer.
class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5EFE1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              height: 1.3,
              letterSpacing: -0.15,
              color: Color(0xFF3B3327),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            answer,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B5A45),
            ),
          ),
        ],
      ),
    );
  }
}