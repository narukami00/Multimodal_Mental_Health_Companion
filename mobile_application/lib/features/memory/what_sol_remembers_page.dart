import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/models/memory_moment.dart';
import '../../core/theme/solace_palette.dart';
import '../consent/consent_controller.dart';
import '../profile/profile_controller.dart';
import 'companion_memory_context.dart';
import 'moments_controller.dart';

const _ink = Color(0xFF3A3125);
const _soft = Color(0xFF6C5E50);
const _muted = Color(0xFFA69883);
const _line = Color(0x143B2F26);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    super.key,
  });

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: ListenableBuilder(
              listenable: Listenable.merge([moments, consent, profileController]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
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
                  _label('YOUR MOMENTS'),
                  _momentList(context),
                  const SizedBox(height: 10),
                  _addButton(context),
                  _label('ASKING'),
                  _askingCard(),
                  const SizedBox(height: 18),
                  if (moments.all.isNotEmpty)
                    Center(
                      child: TextButton(
                        key: const ValueKey('forget-all-moments'),
                        onPressed: () => _confirmForgetAll(context),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFB5503C)),
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
        ),
      ),
    );
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
            subtitle: 'Your tone, what has felt heavy or light lately, and '
                'whether energy seems low. Never numbers, times, or app names.',
            value: on,
            onChanged: (v) =>
                v ? consent.grant(ConsentKey.profileSnippet) : consent.revoke(ConsentKey.profileSnippet),
          ),
          const SizedBox(height: 10),
          _quote(
            key: const ValueKey('snippet-preview'),
            heading: on ? 'Sol is told:' : 'If you turn this on, Sol would be told:',
            text: snippet.isEmpty
                ? 'Nothing yet. There is not enough to say.'
                : snippet.text,
            dim: !on,
          ),
        ],
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
            subtitle: 'Your few most recent kept moments, word for word, so '
                'Sol can gently bring up the good things.',
            value: on,
            onChanged: (v) =>
                v ? consent.grant(ConsentKey.memoryMoments) : consent.revoke(ConsentKey.memoryMoments),
          ),
          const SizedBox(height: 10),
          _quote(
            key: const ValueKey('moments-preview'),
            heading: on ? 'Sol is told:' : 'If you turn this on, Sol would be told:',
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
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _muted),
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
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink),
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
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.5, color: _soft),
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
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
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
              const PopupMenuItem(value: 'edit', child: Text('Change the words')),
              if (m.state == MomentState.confirmed)
                const PopupMenuItem(value: 'hide', child: Text('Set aside')),
              if (m.state == MomentState.hidden)
                const PopupMenuItem(value: 'unhide', child: Text('Bring it back')),
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
        final text = await _askText(context, initial: m.text, title: 'Change the words');
        if (text != null) await moments.edit(m.id, text);
    }
  }

  Widget _addButton(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      key: const ValueKey('add-moment'),
      onPressed: () async {
        final text = await _askText(context, initial: '', title: 'Add a moment');
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
      subtitle: 'After you write or chat, Sol may ask about a good moment. '
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
        content: const Text('This removes every moment on this phone. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep them')),
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
