import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/models/memory_moment.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../chat/chat_controller.dart';
import '../consent/consent_controller.dart';
import '../profile/profile_controller.dart';
import 'companion_memory_context.dart';
import 'moments_controller.dart';

const _ink = kitInk;
const _soft = Color(0xFF6C5E50);
const _muted = kitMuted;
const _line = kitLine;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Everything Sol remembers about the person and everything it is told, in one
/// place: what is shared and exactly how it reads, every moment with edit, set
/// aside and delete, and the switch for being asked at all.
class WhatSolRemembersPage extends StatelessWidget {
  const WhatSolRemembersPage({
    required this.moments,
    required this.memory,
    required this.consent,
    required this.profileController,
    this.chat,
    super.key,
  });

  /// With it, the notes Sol keeps on long conversations are listed here too.
  final ChatController? chat;
  final MomentsController moments;
  final CompanionMemoryContext memory;
  final ConsentController consent;
  final ProfileController profileController;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          moments,
          consent,
          profileController,
          ?chat,
        ]),
        builder: (context, _) => ListView(
          padding: EdgeInsets.zero,
          children: [
            const PageHero(
              scene: HeroScene.memory,
              title: 'What Sol remembers',
              subtitle: 'Nothing is kept or shared unless you say so.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _glance(),
                  const KitLabel('WHAT SOL IS TOLD'),
                  _snippetCard(context),
                  const SizedBox(height: 10),
                  _momentsToldCard(context),
                  const KitLabel('HOW YOU SOUND'),
                  _emotionCard(context),
                  const SizedBox(height: 10),
                  _faceCard(context),
                  const KitLabel('YOUR MOMENTS'),
                  _momentList(context),
                  const SizedBox(height: 10),
                  _addButton(context),
                  if (chat != null) ..._notes(context),
                  const KitLabel('ASKING'),
                  _askingCard(),
                  const SizedBox(height: 18),
                  if (moments.all.isNotEmpty)
                    Center(
                      child: TextButton(
                        key: const ValueKey('forget-all-moments'),
                        onPressed: () => _confirmForgetAll(context),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFB5503C)),
                        child: const Text('Forget all my moments', style: TextStyle(fontWeight: FontWeight.w800)),
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

  /// Four numbers at a glance: what is kept, waiting, set aside and noted.
  Widget _glance() {
    final all = moments.all;
    final kept = all.where((m) => m.state == MomentState.confirmed).length;
    final waiting = all.where((m) => m.state == MomentState.pending).length;
    final aside = all.where((m) => m.state == MomentState.hidden).length;
    final notes = chat == null ? 0 : chat!.conversations.where((c) => c.hasSummary).length;
    return Row(
      key: const ValueKey('memory-glance'),
      children: [
        StatTile(value: '$kept', label: 'kept', color: const Color(0xFF4F8A52), icon: Icons.bookmark_rounded),
        const SizedBox(width: 8),
        StatTile(value: '$waiting', label: 'waiting for you', color: const Color(0xFFD98A12), icon: Icons.hourglass_empty_rounded),
        const SizedBox(width: 8),
        StatTile(value: '$aside', label: 'set aside', color: const Color(0xFF8A7B67), icon: Icons.visibility_off_outlined),
        if (chat != null) ...[
          const SizedBox(width: 8),
          StatTile(value: '$notes', label: 'chat notes', color: const Color(0xFF6E73C8), icon: Icons.sticky_note_2_outlined),
        ],
      ],
    );
  }

  /// Short summaries of long conversations, kept so a chat can be picked up
  /// again. Shown with the conversation they belong to, each one deletable.
  List<Widget> _notes(BuildContext context) {
    final noted = [
      for (final c in chat!.conversations)
        if (c.hasSummary) c,
    ];
    if (noted.isEmpty) return const [];
    return [
      const KitLabel('NOTES ON LONG CONVERSATIONS'),
      KitCard(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Column(
          key: const ValueKey('conversation-notes'),
          children: [
            for (var i = 0; i < noted.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconTile(icon: Icons.sticky_note_2_outlined, color: Color(0xFF6E73C8), size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(noted[i].title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _muted)),
                          const SizedBox(height: 4),
                          Text(noted[i].summary!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.45, color: _ink)),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('forget-note-${noted[i].id}'),
                      tooltip: 'Forget this note',
                      onPressed: () => chat!.clearSummary(noted[i].id),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
          'Forgetting a note never removes the messages themselves.',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.5, color: _muted),
        ),
      ),
    ];
  }

  Widget _snippetCard(BuildContext context) {
    final on = memory.snippetOn;
    final snippet = on ? memory.snippet() : memory.previewSnippet();
    return KitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            key: const ValueKey('snippet-switch'),
            icon: Icons.person_outline_rounded,
            color: const Color(0xFF4F8A52),
            title: 'A short note about how you like things',
            subtitle: 'Your tone and what has felt heavy or light lately. Never numbers or app names.',
            value: on,
            onChanged: (v) => v ? consent.grant(ConsentKey.profileSnippet) : consent.revoke(ConsentKey.profileSnippet),
          ),
          const SizedBox(height: 12),
          _bubble(
            key: const ValueKey('snippet-preview'),
            heading: on ? 'Sol is told:' : 'If you turn this on, Sol would be told:',
            text: snippet.isEmpty ? 'Nothing yet. There is not enough to say.' : snippet.text,
            dim: !on,
          ),
        ],
      ),
    );
  }

  Widget _emotionCard(BuildContext context) {
    final on = consent.isGranted(ConsentKey.emotionEstimate);
    return KitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            key: const ValueKey('emotion-switch'),
            icon: Icons.graphic_eq_rounded,
            color: const Color(0xFFD9674A),
            title: 'Let Sol notice how I sound',
            subtitle: 'A weak guess from your voice and words, never a diagnosis. Your voice is never kept.',
            value: on,
            onChanged: (v) => v ? consent.grant(ConsentKey.emotionEstimate) : consent.revoke(ConsentKey.emotionEstimate),
          ),
          const SizedBox(height: 12),
          _bubble(
            key: const ValueKey('emotion-preview'),
            heading: on ? 'Sol is told, at most:' : 'If you turn this on, Sol would be told, at most:',
            text: 'One private line such as "they may sound a bit low, this is a weak guess". '
                'Never your voice, never a label like "depressed", and nothing when it is unsure.',
            dim: !on,
          ),
        ],
      ),
    );
  }

  Widget _faceCard(BuildContext context) {
    final on = consent.isGranted(ConsentKey.faceFeatures);
    return KitCard(
      child: _switchRow(
        key: const ValueKey('face-switch'),
        icon: Icons.face_retouching_natural_rounded,
        color: const Color(0xFF6E73C8),
        title: 'Let Sol read my face on video calls',
        subtitle: 'Only with the camera on, read live and never saved. Also turns on noticing how you sound.',
        value: on,
        onChanged: (v) async {
          if (v) {
            if (!consent.isGranted(ConsentKey.emotionEstimate)) {
              await consent.grant(ConsentKey.emotionEstimate);
            }
            await consent.grant(ConsentKey.faceFeatures);
          } else {
            await consent.revoke(ConsentKey.faceFeatures);
          }
        },
      ),
    );
  }

  Widget _momentsToldCard(BuildContext context) {
    final on = memory.momentsOn;
    final lines = memory.previewMomentLines();
    return KitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            key: const ValueKey('moments-switch'),
            icon: Icons.bookmark_border_rounded,
            color: const Color(0xFFB57A12),
            title: 'Let Sol remember my moments',
            subtitle: 'Your few most recent kept moments, word for word.',
            value: on,
            onChanged: (v) => v ? consent.grant(ConsentKey.memoryMoments) : consent.revoke(ConsentKey.memoryMoments),
          ),
          const SizedBox(height: 12),
          _bubble(
            key: const ValueKey('moments-preview'),
            heading: on ? 'Sol is told:' : 'If you turn this on, Sol would be told:',
            text: lines.isEmpty ? 'Nothing yet. Moments you keep will appear here.' : [for (final l in lines) '• $l'].join('\n'),
            dim: !on,
          ),
        ],
      ),
    );
  }

  /// What Sol would be told, as a speech bubble from a small sun, so it reads as a message and not a setting.
  Widget _bubble({
    required Key key,
    required String heading,
    required String text,
    required bool dim,
  }) => Row(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [const Color(0xFFFFD27A).withValues(alpha: dim ? 0.5 : 1), const Color(0xFFFFA23A).withValues(alpha: dim ? 0.5 : 1)]),
        ),
        child: const Icon(Icons.wb_sunny_rounded, size: 15, color: Colors.white),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8EA),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: const Color(0xFFF6E7C4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heading, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _muted)),
              const SizedBox(height: 4),
              Text(
                text,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.5, color: dim ? _soft.withValues(alpha: 0.75) : _ink),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _switchRow({
    required Key key,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconTile(icon: icon, color: color),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink, height: 1.25)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4, color: _soft)),
          ],
        ),
      ),
      const SizedBox(width: 6),
      Switch(
        key: key,
        value: value,
        onChanged: onChanged,
        activeTrackColor: kitAmber,
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
    ],
  );

  Widget _momentList(BuildContext context) {
    final all = moments.all;
    if (all.isEmpty) {
      return const KitCard(
        child: Row(
          children: [
            IconTile(icon: Icons.bookmark_add_outlined, color: Color(0xFFB57A12)),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'No moments yet. When you write about something good, Sol may ask '
                'whether to remember it. Only what you say yes to is kept.',
                key: ValueKey('moments-empty'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.5, color: _soft),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [for (final m in all) Padding(padding: const EdgeInsets.only(bottom: 10), child: _momentRow(context, m))],
    );
  }

  Widget _momentRow(BuildContext context, MemoryMoment m) {
    final (label, color) = switch (m.state) {
      MomentState.pending => ('Waiting for your yes', const Color(0xFFB57A12)),
      MomentState.confirmed => ('Kept', const Color(0xFF3F823B)),
      MomentState.hidden => ('Set aside', const Color(0xFF8A7B67)),
    };
    final date = DateTime.tryParse(m.occurredOn);
    return Container(
      key: ValueKey('moment-row-${m.id}'),
      decoration: BoxDecoration(
        color: m.state == MomentState.hidden ? const Color(0xFFF7F3EA) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.45, color: _ink)),
                    const SizedBox(height: 6),
                    Text(
                      '$label${date == null ? '' : '  ·  ${date.day} ${_months[date.month - 1]}'}'
                      '${m.editedByUser ? '  ·  edited' : ''}',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('moment-menu-${m.id}'),
              icon: const Icon(Icons.more_horiz_rounded, color: _muted),
              onSelected: (action) => _act(context, m, action),
              itemBuilder: (_) => [
                if (m.state == MomentState.pending) const PopupMenuItem(value: 'keep', child: Text('Keep it')),
                const PopupMenuItem(value: 'edit', child: Text('Change the words')),
                if (m.state == MomentState.confirmed) const PopupMenuItem(value: 'hide', child: Text('Set aside')),
                if (m.state == MomentState.hidden) const PopupMenuItem(value: 'unhide', child: Text('Bring it back')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, MemoryMoment m, String action) async {
    switch (action) {
      case 'keep':
        await moments.confirm(m.id);
      case 'hide':
        await moments.hide(m.id);
      case 'unhide':
        await moments.unhide(m.id);
      case 'delete':
        await moments.delete(m.id);
      case 'edit':
        final text = await _askText(
          context,
          initial: m.text,
          title: 'Change the words',
        );
        if (text != null) await moments.edit(m.id, text);
    }
  }

  Widget _addButton(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      key: const ValueKey('add-moment'),
      onPressed: () async {
        final text = await _askText(
          context,
          initial: '',
          title: 'Add a moment',
        );
        if (text != null) await moments.addManual(text);
      },
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Add a moment myself'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF8A5A0A),
        side: const BorderSide(color: Color(0xFFE9D8B4)),
        shape: const StadiumBorder(),
      ),
    ),
  );

  Widget _askingCard() => KitCard(
    child: _switchRow(
      key: const ValueKey('asking-switch'),
      icon: Icons.chat_bubble_outline_rounded,
      color: const Color(0xFFD9674A),
      title: 'Ask me whether to remember things',
      subtitle: 'Sol may ask about a good moment. Nothing is kept without your yes.',
      value: !profileController.profile.momentPromptsMuted,
      onChanged: (asking) => profileController.setMomentPromptsMuted(!asking),
    ),
  );

  Future<String?> _askText(
    BuildContext context, {
    required String initial,
    required String title,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('moment-dialog-field'),
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          maxLength: MemoryMoment.maxLength,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('moment-dialog-save'),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForgetAll(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget all your moments?'),
        content: const Text(
          'This removes every moment on this phone. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            key: const ValueKey('forget-all-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget all'),
          ),
        ],
      ),
    );
    if (sure == true) await moments.deleteAll();
  }
}
