import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/models/memory_moment.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/page_back_button.dart';
import '../chat/chat_controller.dart';
import '../consent/consent_controller.dart';
import '../profile/profile_controller.dart';
import 'companion_memory_context.dart';
import 'moments_controller.dart';

const _ink = Color(0xFF3A3125);
const _soft = Color(0xFF6C5E50);
const _muted = Color(0xFFA69883);
const _line = Color(0x143B2F26);

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
      appBar: AppBar(
        leading: const PageBackButton(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'What Sol remembers',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            moments,
            consent,
            profileController,
            ?chat,
          ]),
          builder: (context, _) => ListView(
            // Same 22px inset as the main pages, so cards line up app-wide.
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Text(
                  'Nothing here is kept or shared unless you say so. This is '
                  'all of it, and all of it is yours to change.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: _soft,
                  ),
                ),
              ),
              _label('WHAT SOL IS TOLD'),
              _snippetCard(context),
              const SizedBox(height: 10),
              _momentsToldCard(context),
              _label('HOW YOU SOUND'),
              _emotionCard(context),
              const SizedBox(height: 10),
              _faceCard(context),
              _label('YOUR MOMENTS'),
              _momentList(context),
              const SizedBox(height: 10),
              _addButton(context),
              if (chat != null) ..._notes(context),
              _label('ASKING'),
              _askingCard(),
              const SizedBox(height: 18),
              if (moments.all.isNotEmpty)
                Center(
                  child: TextButton(
                    key: const ValueKey('forget-all-moments'),
                    onPressed: () => _confirmForgetAll(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB5503C),
                    ),
                    child: const Text(
                      'Forget all my moments',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
      _label('NOTES ON LONG CONVERSATIONS'),
      _card(
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            noted[i].title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            noted[i].summary!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('forget-note-${noted[i].id}'),
                      tooltip: 'Forget this note',
                      onPressed: () => chat!.clearSummary(noted[i].id),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: _muted,
                      ),
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
          'When a conversation gets long, Sol writes itself a short note so it '
          'can pick the thread up again. The messages themselves stay as they '
          'are, and forgetting a note never removes them.',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: _muted,
          ),
        ),
      ),
    ];
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.3,
        color: _muted,
      ),
    ),
  );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _line),
    ),
    child: child,
  );

  Widget _snippetCard(BuildContext context) {
    final on = memory.snippetOn;
    final snippet = on ? memory.snippet() : memory.previewSnippet();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            key: const ValueKey('snippet-switch'),
            title: 'A short note about how you like things',
            subtitle:
                'Your tone, what has felt heavy or light lately, and '
                'whether energy seems low. Never numbers, times, or app names.',
            value: on,
            onChanged: (v) => v
                ? consent.grant(ConsentKey.profileSnippet)
                : consent.revoke(ConsentKey.profileSnippet),
          ),
          const SizedBox(height: 10),
          _quote(
            key: const ValueKey('snippet-preview'),
            heading: on
                ? 'Sol is told:'
                : 'If you turn this on, Sol would be told:',
            text: snippet.isEmpty
                ? 'Nothing yet. There is not enough to say.'
                : snippet.text,
            dim: !on,
          ),
        ],
      ),
    );
  }

  Widget _emotionCard(BuildContext context) {
    final on = consent.isGranted(ConsentKey.emotionEstimate);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            key: const ValueKey('emotion-switch'),
            title: 'Let Sol notice how I sound',
            subtitle:
                'From your voice and words, Sol can guess whether you '
                'sound low, tense or upbeat, and soften its tone to match. '
                'It is a weak guess, never a diagnosis. Your voice is '
                'analysed on the spot and never kept.',
            value: on,
            onChanged: (v) => v
                ? consent.grant(ConsentKey.emotionEstimate)
                : consent.revoke(ConsentKey.emotionEstimate),
          ),
          const SizedBox(height: 10),
          _quote(
            key: const ValueKey('emotion-preview'),
            heading: on
                ? 'Sol is told, at most:'
                : 'If you turn this on, Sol would be told, at most:',
            text:
                'One private line such as "they may sound a bit low, '
                'this is a weak guess" for a turn. Never your voice, '
                'never a label like "depressed", and nothing at all when '
                'it is unsure.',
            dim: !on,
          ),
        ],
      ),
    );
  }

  Widget _faceCard(BuildContext context) {
    final on = consent.isGranted(ConsentKey.faceFeatures);
    return _card(
      child: _switchRow(
        key: const ValueKey('face-switch'),
        title: 'Let Sol read my face on video calls',
        subtitle:
            'Only while the camera is on in a call. Frames are analysed '
            'live on the companion server to help judge how you sound, and '
            'are never saved. Turning this on also turns on noticing how you sound.',
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
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchRow(
            key: const ValueKey('moments-switch'),
            title: 'Let Sol remember my moments',
            subtitle:
                'Your few most recent kept moments, word for word, so '
                'Sol can gently bring up the good things.',
            value: on,
            onChanged: (v) => v
                ? consent.grant(ConsentKey.memoryMoments)
                : consent.revoke(ConsentKey.memoryMoments),
          ),
          const SizedBox(height: 10),
          _quote(
            key: const ValueKey('moments-preview'),
            heading: on
                ? 'Sol is told:'
                : 'If you turn this on, Sol would be told:',
            text: lines.isEmpty
                ? 'Nothing yet. Moments you keep will appear here.'
                : [for (final l in lines) '• $l'].join('\n'),
            dim: !on,
          ),
        ],
      ),
    );
  }

  Widget _quote({
    required Key key,
    required String heading,
    required String text,
    required bool dim,
  }) => Container(
    key: key,
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8EA),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: _muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: dim ? _soft.withValues(alpha: 0.75) : _ink,
          ),
        ),
      ],
    ),
  );

  Widget _switchRow({
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: _soft,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Switch(
        key: key,
        value: value,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFFFFB534),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
    ],
  );

  Widget _momentList(BuildContext context) {
    final all = moments.all;
    if (all.isEmpty) {
      return _card(
        child: const Text(
          'No moments yet. When you write about something good, Sol may ask '
          'whether to remember it. Only what you say yes to is kept.',
          key: ValueKey('moments-empty'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: _soft,
          ),
        ),
      );
    }
    return _card(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < all.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: _line),
            _momentRow(context, all[i]),
          ],
        ],
      ),
    );
  }

  Widget _momentRow(BuildContext context, MemoryMoment m) {
    final (label, color) = switch (m.state) {
      MomentState.pending => ('Waiting for your yes', const Color(0xFFB57A12)),
      MomentState.confirmed => ('Kept', const Color(0xFF3F823B)),
      MomentState.hidden => ('Set aside', const Color(0xFF8A7B67)),
    };
    final date = DateTime.tryParse(m.occurredOn);
    return Padding(
      key: ValueKey('moment-row-${m.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$label${date == null ? '' : '  ·  ${date.day} ${_months[date.month - 1]}'}'
                  '${m.editedByUser ? '  ·  edited' : ''}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: ValueKey('moment-menu-${m.id}'),
            icon: const Icon(Icons.more_horiz_rounded, color: _muted),
            onSelected: (action) => _act(context, m, action),
            itemBuilder: (_) => [
              if (m.state == MomentState.pending)
                const PopupMenuItem(value: 'keep', child: Text('Keep it')),
              const PopupMenuItem(
                value: 'edit',
                child: Text('Change the words'),
              ),
              if (m.state == MomentState.confirmed)
                const PopupMenuItem(value: 'hide', child: Text('Set aside')),
              if (m.state == MomentState.hidden)
                const PopupMenuItem(
                  value: 'unhide',
                  child: Text('Bring it back'),
                ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
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

  Widget _askingCard() => _card(
    child: _switchRow(
      key: const ValueKey('asking-switch'),
      title: 'Ask me whether to remember things',
      subtitle:
          'After you write or chat, Sol may ask about a good moment. '
          'Nothing is ever kept without your yes.',
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
