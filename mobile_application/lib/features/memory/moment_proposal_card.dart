import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/models/memory_moment.dart';
import '../../core/widgets/visual_kit.dart';
import '../consent/consent_controller.dart';
import 'moments_controller.dart';

/// "Want me to remember this?" A gentle question about one good moment the
/// person wrote about, with the exact words shown. Nothing is kept unless they
/// say yes, and saying no deletes it.
class MomentProposalCard extends StatefulWidget {
  const MomentProposalCard({
    required this.controller,
    this.suppressed = _never,
    this.onStopAsking,
    this.consent,
    super.key,
  });

  /// When given, the first time someone keeps a moment they are asked, right
  /// there, whether Sol may be told about the moments they keep. Asked once:
  /// either answer is recorded and the question does not come back.
  final ConsentController? consent;

  final MomentsController controller;

  /// True when the question must not be asked right now, such as while safety
  /// support is active or when the person turned these questions off.
  final bool Function() suppressed;

  /// Turns the questions off. Offered on the card so declining never needs a
  /// trip through settings.
  final VoidCallback? onStopAsking;

  static bool _never() => false;

  @override
  State<MomentProposalCard> createState() => _MomentProposalCardState();
}

class _MomentProposalCardState extends State<MomentProposalCard> {
  final _text = TextEditingController();
  String? _editingId;

  /// Set after a first moment is kept, until the question is answered.
  bool _askingConsent = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Widget _consentStep() {
    Future<void> answer(bool yes) async {
      final ledger = widget.consent!;
      if (yes) {
        await ledger.grant(ConsentKey.memoryMoments);
      } else {
        await ledger.decline(ConsentKey.memoryMoments);
      }
      if (mounted) setState(() => _askingConsent = false);
    }

    return Container(
      key: const ValueKey('moment-consent'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF6E6), Color(0xFFFCE9EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x1F3B2F26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: Color(0xFF3F823B),
              ),
              SizedBox(width: 7),
              Text(
                'KEPT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Color(0xFF3F823B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Should Sol know about moments you keep?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: Color(0xFF3A3125),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sol would be told your few most recent kept moments, word for word, '
            'so it can gently bring up the good things. Otherwise they stay only '
            'on this phone. You can change this any time in What Sol remembers.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF6B5B43),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('moment-consent-yes'),
                onPressed: () => answer(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB534),
                  foregroundColor: const Color(0xFF3A2A06),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: const Text(
                  'Yes, let Sol know',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                key: const ValueKey('moment-consent-no'),
                onPressed: () => answer(false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7B6A55),
                ),
                child: const Text('Keep them private'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (_askingConsent && !widget.suppressed()) return _consentStep();
        final pending = widget.controller.pending;
        if (pending.isEmpty || widget.suppressed()) {
          return const SizedBox.shrink();
        }
        final moment = pending.first;
        final editing = _editingId == moment.id;

        return Container(
          key: const ValueKey('moment-proposal'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF6E6), Color(0xFFFCE9EA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0x1F3B2F26)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14B0782A),
                blurRadius: 18,
                spreadRadius: -8,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconTile(
                    icon: Icons.bookmark_added_rounded,
                    color: Color(0xFFB5586A),
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A MOMENT WORTH KEEPING?',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Color(0xFFB5586A),
                          ),
                        ),
                        Text(
                          'Want me to remember this?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            color: Color(0xFF3A3125),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (editing)
                TextField(
                  key: const ValueKey('moment-edit-field'),
                  controller: _text,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 140,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A3125),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(18),
                    border: const Border(
                      left: BorderSide(color: Color(0xFFFFB534), width: 4),
                    ),
                  ),
                  child: Text(
                    '\u201c${moment.text}\u201d',
                    key: const ValueKey('moment-text'),
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: Color(0xFF3A3125),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusPill(_sourceLabel(moment), color: const Color(0xFF8A6A1C)),
                  const StatusPill('Only on this phone', color: Color(0xFF4F9D76)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    key: const ValueKey('moment-yes'),
                    onPressed: () {
                      widget.controller.confirm(
                        moment.id,
                        text: editing ? _text.text : null,
                      );
                      final ledger = widget.consent;
                      setState(() {
                        _editingId = null;
                        // First moment kept and nothing decided yet: ask, in
                        // context, whether Sol may be told about them.
                        _askingConsent =
                            ledger != null &&
                            ledger.statusOf(ConsentKey.memoryMoments) ==
                                ConsentStatus.notAsked;
                      });
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB534),
                      foregroundColor: const Color(0xFF3A2A06),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text(
                      editing ? 'Save it' : 'Yes, remember it',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (!editing)
                    TextButton.icon(
                      key: const ValueKey('moment-edit'),
                      onPressed: () => setState(() {
                        _editingId = moment.id;
                        _text.text = moment.text;
                      }),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Change it'),
                    ),
                  TextButton(
                    key: const ValueKey('moment-no'),
                    onPressed: () {
                      widget.controller.delete(moment.id);
                      setState(() => _editingId = null);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7B6A55),
                    ),
                    child: const Text('Not this'),
                  ),
                ],
              ),
              if (widget.onStopAsking != null)
                TextButton(
                  key: const ValueKey('moment-stop'),
                  onPressed: widget.onStopAsking,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFA2988A),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Stop asking me this',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _sourceLabel(MemoryMoment m) => switch (m.source) {
    MomentSource.chat => 'From your chat',
    MomentSource.journal => 'From your journal',
    MomentSource.checkIn => 'From a check-in',
    MomentSource.review => 'From a review',
    MomentSource.manual => 'Added by you',
  };
}
