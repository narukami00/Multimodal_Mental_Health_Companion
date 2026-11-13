import 'package:flutter/material.dart';

import 'life_pulse_controller.dart';

/// Gentle periodic check-in card on Home: asks "Is everything alright? Anything
/// on your mind?" even when no extreme usage anomaly occurred, gathering light
/// consented context for Sol's chats and recommendations.
class LifePulseCard extends StatefulWidget {
  const LifePulseCard({
    required this.controller,
    this.displayName,
    this.onStartChatWithContext,
    super.key,
  });

  final LifePulseController controller;
  final String? displayName;
  final VoidCallback? onStartChatWithContext;

  @override
  State<LifePulseCard> createState() => _LifePulseCardState();
}

class _LifePulseCardState extends State<LifePulseCard> {
  bool _writingNote = false;
  String? _selectedTag;
  final _noteController = TextEditingController();

  static const _ink = Color(0xFF3A3125);
  static const _soft = Color(0xFF6B5B43);
  static const _sage = Color(0xFF3F9A7C);

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  static const _quickOptions = [
    ('all_good', 'All good', Icons.wb_sunny_outlined, true),
    ('stressed', 'Busy or stressed', Icons.bolt_rounded, false),
    ('tired', 'Tired', Icons.bedtime_outlined, false),
    ('low', 'A bit heavy', Icons.cloud_outlined, false),
    ('relationships', 'People', Icons.people_outline_rounded, false),
    ('sleep', 'Sleep', Icons.nights_stay_outlined, false),
  ];

  Future<void> _submitQuick(String tag) async {
    await widget.controller.answer(moodTag: tag);
  }

  Future<void> _submitWithNote({bool openChat = false}) async {
    final tag = _selectedTag ?? 'custom';
    final note = _noteController.text.trim();
    await widget.controller.answer(
      moodTag: tag,
      note: note.isEmpty ? null : note,
    );
    if (openChat) {
      widget.onStartChatWithContext?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.controller.current;
    if (prompt == null) return const SizedBox.shrink();

    final cleanName = widget.displayName?.trim();
    final headline = (cleanName != null && cleanName.isNotEmpty)
        ? 'Hey $cleanName, everything alright?'
        : 'Everything alright today?';

    return Container(
      key: const ValueKey('life-pulse-card'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFAEB), Color(0xFFF6FBF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x223F9A7C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_border_rounded, size: 15, color: _sage),
              const SizedBox(width: 7),
              const Text(
                'CHECKING IN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: _sage,
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                key: const ValueKey('life-pulse-menu'),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz_rounded, size: 18, color: _soft),
                onSelected: (value) {
                  if (value == 'pause') {
                    widget.controller.setEnabled(false);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'pause',
                    child: Text('Pause these check-ins'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: const TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: _ink,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Anything on your mind right now? Only Sol sees this if you allow profile context.',
            style: TextStyle(
              fontSize: 12.8,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: _soft,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final (tag, label, icon, positive) in _quickOptions)
                ActionChip(
                  key: ValueKey('life-pulse-$tag'),
                  avatar: Icon(
                    icon,
                    size: 15,
                    color: _selectedTag == tag
                        ? Colors.white
                        : positive
                        ? _sage
                        : const Color(0xFF7D5007),
                  ),
                  label: Text(label),
                  onPressed: () {
                    if (_writingNote) {
                      setState(() => _selectedTag = tag);
                    } else {
                      _submitQuick(tag);
                    }
                  },
                  backgroundColor: _selectedTag == tag
                      ? const Color(0xFF4A3728)
                      : positive
                      ? const Color(0xFFEDF7F2)
                      : Colors.white,
                  side: BorderSide(
                    color: _selectedTag == tag
                        ? const Color(0xFF4A3728)
                        : positive
                        ? const Color(0x553F9A7C)
                        : const Color(0xFFEBDCC0),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: _selectedTag == tag
                        ? Colors.white
                        : positive
                        ? const Color(0xFF1F5E48)
                        : _ink,
                  ),
                ),
              ActionChip(
                key: const ValueKey('life-pulse-note-toggle'),
                avatar: Icon(
                  _writingNote ? Icons.close_rounded : Icons.edit_note_rounded,
                  size: 16,
                  color: _soft,
                ),
                label: Text(_writingNote ? 'Hide note' : 'Add a short note'),
                onPressed: () => setState(() => _writingNote = !_writingNote),
                backgroundColor: const Color(0xFFFFF8E8),
                side: const BorderSide(color: Color(0xFFE7DBC0)),
                labelStyle: const TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: _soft,
                ),
              ),
            ],
          ),
          if (_writingNote) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('life-pulse-note-input'),
              controller: _noteController,
              maxLength: 72,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'e.g., busy week with exams, or just tired…',
                hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFFA2988A)),
                filled: true,
                fillColor: Colors.white,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE7DBC0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE7DBC0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _sage, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton(
                  key: const ValueKey('life-pulse-save-note'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4A3728),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _submitWithNote(),
                  child: const Text(
                    'Save context',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.onStartChatWithContext != null)
                  OutlinedButton.icon(
                    key: const ValueKey('life-pulse-chat'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: Color(0xFFE7DBC0)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _submitWithNote(openChat: true),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text(
                      'Share & chat with Sol',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                key: const ValueKey('life-pulse-not-now'),
                onPressed: widget.controller.dismiss,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7B6A55),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Not now',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              const Text(
                'Gentle check-in every ~36h',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA2988A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
