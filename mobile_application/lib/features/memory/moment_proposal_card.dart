import 'package:flutter/material.dart';

import 'moments_controller.dart';

/// "Want me to remember this?" A gentle question about one good moment the
/// person wrote about, with the exact words shown. Nothing is kept unless they
/// say yes, and saying no deletes it.
class MomentProposalCard extends StatefulWidget {
  const MomentProposalCard({
    required this.controller,
    this.suppressed = _never,
    this.onStopAsking,
    super.key,
  });

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

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final pending = widget.controller.pending;
        if (pending.isEmpty || widget.suppressed()) return const SizedBox.shrink();
        final moment = pending.first;
        final editing = _editingId == moment.id;

        return Container(
          key: const ValueKey('moment-proposal'),
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
                  Icon(Icons.bookmark_added_rounded, size: 15, color: Color(0xFFB5586A)),
                  SizedBox(width: 7),
                  Text(
                    'A MOMENT WORTH KEEPING?',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFFB5586A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Want me to remember this?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: Color(0xFF3A3125),
                ),
              ),
              const SizedBox(height: 8),
              if (editing)
                TextField(
                  key: const ValueKey('moment-edit-field'),
                  controller: _text,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 140,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A3125),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '“${moment.text}”',
                    key: const ValueKey('moment-text'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: Color(0xFF4A3F33),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'Your own words, only on this phone unless you let Sol know '
                'about it. You can change or delete it any time.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  color: Color(0xFF8A7B67),
                ),
              ),
              const SizedBox(height: 10),
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
                      setState(() => _editingId = null);
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
                    TextButton(
                      key: const ValueKey('moment-edit'),
                      onPressed: () => setState(() {
                        _editingId = moment.id;
                        _text.text = moment.text;
                      }),
                      child: const Text('Change it'),
                    ),
                  TextButton(
                    key: const ValueKey('moment-no'),
                    onPressed: () {
                      widget.controller.delete(moment.id);
                      setState(() => _editingId = null);
                    },
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF7B6A55)),
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
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
