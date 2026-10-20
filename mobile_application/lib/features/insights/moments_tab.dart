import 'package:flutter/material.dart';

import '../../core/models/memory_moment.dart';
import '../../domain/memory/moment_entry.dart';
import '../memory/moments_controller.dart';
import 'insight_widgets.dart';
import 'moments_sky_card.dart';
import 'mood_tab.dart' show moodColors;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

/// Where a first moment can begin, for someone staring at an empty box.
const momentStarters = [
  'A small win today:',
  'Someone who made me smile:',
  'Somewhere that felt calm:',
  "Something I'm looking forward to:",
];

/// The good things the person chose to keep, in their own words, newest first, under a sky where each is a star.
///
/// Only warm, confirmed moments appear here. Hard ones are kept private to Sol's
/// tone and never listed in analytics, and a moment that was set aside or is
/// still waiting for a yes is not shown at all.
class MomentsInsightsTab extends StatelessWidget {
  const MomentsInsightsTab({required this.moments, this.onManage, this.onTalk, super.key});

  final MomentsController moments;

  /// Opens "What Sol remembers", where moments are changed and deleted.
  final VoidCallback? onManage;

  /// Opens a chat, to talk about a moment. The button is hidden without it.
  final VoidCallback? onTalk;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: moments,
      builder: (context, _) {
        final list = [...moments.forInsights]
          ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
        final sky = MomentsSkyCard(
          count: list.length,
          onAdd: () => showAddMomentSheet(context, moments),
          onTalk: onTalk,
        );

        if (list.isEmpty) {
          return Column(
            key: const ValueKey('moments-empty'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sky,
              const SizedBox(height: 14),
              const InsightEmpty(
                icon: Icons.auto_awesome_rounded,
                title: 'Good moments will gather here',
                body:
                    'When you write about something good, Solace may ask whether to '
                    'remember it. The ones you say yes to are kept here, in your own '
                    'words, for the days you want a reminder. You can also add one yourself.',
              ),
              const InsightLabel('NEED A PLACE TO START?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final starter in momentStarters)
                    ActionChip(
                      key: ValueKey('moment-starter-$starter'),
                      label: Text(starter, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: insightSoft)),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x33FFB534)),
                      onPressed: () => showAddMomentSheet(context, moments, prefill: '$starter '),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _HowSolUsesThese(onManage: onManage),
            ],
          );
        }

        final children = <Widget>[sky];
        String? month;
        for (final m in list) {
          final date = DateTime.tryParse(m.occurredOn);
          final heading = date == null ? null : '${_months[date.month - 1]} ${date.year}';
          if (heading != null && heading != month) {
            month = heading;
            children.add(InsightLabel(heading.toUpperCase()));
          } else if (children.length == 1) {
            children.add(const SizedBox(height: 10));
          }
          children
            ..add(_MomentCard(moment: m, date: date, onTap: onManage))
            ..add(const SizedBox(height: 10));
        }
        children
          ..add(const SizedBox(height: 4))
          ..add(_HowSolUsesThese(onManage: onManage));
        return Column(
          key: const ValueKey('moments-list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

/// A plain account of what Sol does with moments, because it is otherwise a mystery.
class _HowSolUsesThese extends StatelessWidget {
  const _HowSolUsesThese({this.onManage});

  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      key: const ValueKey('moments-how'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_border_rounded, size: 18, color: Color(0xFFB57A12)),
              SizedBox(width: 8),
              Expanded(
                child: Text('How Sol uses these', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: insightInk)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Only if you allow it, Sol is told the moments you keep, so that it can mention one when it fits what you '
            'are talking about. It never brings up anything you have not raised yourself, and only you see this list.',
            style: TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600, color: insightSoft),
          ),
          if (onManage != null)
            TextButton(
              key: const ValueKey('manage-moments'),
              onPressed: onManage,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF96620C),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Manage what Sol remembers', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.moment, required this.date, this.onTap});

  final MemoryMoment moment;
  final DateTime? date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mood = moment.moodWord;
    final color = mood == null ? null : moodColors[mood];
    final accent = color ?? const Color(0xFFFFB534);
    final card = InsightCard(
      key: ValueKey('moment-card-${moment.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.18)),
            child: Icon(Icons.auto_awesome_rounded, size: 17, color: accent),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moment.text,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.45, color: insightInk),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (date != null) '${date!.day} ${_months[date!.month - 1].substring(0, 3)}',
                    if (mood != null) 'you checked in as $mood',
                  ].join('  ·  '),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: insightMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }
}

/// A sheet for writing a moment of your own: one sentence, in your own words, kept at once. With an [entry] (one of
/// their journal entries or chat messages) it offers the person's own best sentence from it to keep, to trim or
/// change first, and keeps the moment tied to that entry together with how the model read it.
Future<void> showAddMomentSheet(BuildContext context, MomentsController moments, {String? prefill, MomentEntry? entry}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFFFDF7),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (sheetContext) => _AddMomentSheet(moments: moments, prefill: prefill, entry: entry),
  );
}

class _AddMomentSheet extends StatefulWidget {
  const _AddMomentSheet({required this.moments, this.prefill, this.entry});

  final MomentsController moments;
  final String? prefill;
  final MomentEntry? entry;

  @override
  State<_AddMomentSheet> createState() => _AddMomentSheetState();
}

class _AddMomentSheetState extends State<_AddMomentSheet> {
  late final _controller = TextEditingController(
    text: widget.entry != null ? suggestMomentText(widget.entry!.text) : widget.prefill ?? '',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _keep() async {
    if (_saving || _controller.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final entry = widget.entry;
    if (entry == null) {
      await widget.moments.addManual(_controller.text);
    } else {
      await widget.moments.keepFromEntry(
        text: _controller.text,
        source: entry.source,
        sourceRef: entry.sourceRef,
        at: entry.at,
        moodWord: entry.moodWord,
        reading: entry.reading,
        edited: _controller.text.trim() != entry.text.trim(),
      );
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Kept. A new star.'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _controller.text.trim().isNotEmpty && !_saving;
    return Padding(
      key: const ValueKey('moment-sheet'),
      padding: EdgeInsets.fromLTRB(22, 16, 22, 22 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(color: const Color(0x293B2F26), borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.entry == null ? 'Add a moment' : 'Keep this as a moment',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: insightInk),
            ),
            const SizedBox(height: 4),
            Text(
              widget.entry == null
                  ? 'Something good, however small. One sentence, in your own words.'
                  : 'Trim it to the part you want to keep. It stays in your own words, and only you decide.',
              style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: insightSoft),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('moment-field'),
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: MemoryMoment.maxLength,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: insightInk),
              decoration: InputDecoration(
                hintText: 'Today I…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0x33FFB534))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0x33FFB534))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFFFB534), width: 2)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                key: const ValueKey('moment-keep'),
                onPressed: enabled ? _keep : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB534),
                  foregroundColor: const Color(0xFF3A2A0C),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Keep this moment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
