import 'package:flutter/material.dart';

import '../../core/models/daily_features.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../chat/chat_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import '../memory/companion_memory_context.dart';
import '../memory/moments_controller.dart';
import '../memory/what_sol_remembers_page.dart';
import '../sessions/session_controller.dart';
import 'phone_patterns_page.dart';
import 'profile_controller.dart';

const _ink = kitInk;
const _soft = kitSoft;
const _muted = kitMuted;
const _line = kitLine;

/// One place that says what Solace keeps, how much of it, and where to look at
/// or delete each kind. Counts come straight from the stores, so the page cannot
/// claim a thing that is not there or miss one that is.
class EverythingKeptPage extends StatelessWidget {
  const EverythingKeptPage({
    required this.sessionController,
    required this.profileController,
    this.chatController,
    this.moments,
    this.memory,
    this.phonePatterns,
    super.key,
  });

  final SessionController sessionController;
  final ProfileController profileController;
  final ChatController? chatController;
  final MomentsController? moments;
  final CompanionMemoryContext? memory;
  final PhonePatternsController? phonePatterns;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          sessionController,
          ?chatController,
          ?moments,
          ?phonePatterns,
        ]),
        builder: (context, _) => FutureBuilder<List<DailyFeatures>>(
          future: phonePatterns?.storedDays(),
          builder: (context, snapshot) => ListView(
            padding: EdgeInsets.zero,
            children: [
              const PageHero(
                scene: HeroScene.privacy,
                title: 'Everything Solace keeps',
                subtitle: 'All on your phone. You decide what stays.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _rows(context, snapshot.data ?? const []),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context, List<DailyFeatures> phoneRows) {
    final entries = sessionController.sessions.length;
    final conversations = [
      for (final c in chatController?.conversations ?? const [])
        if (c.hasUserMessage) c,
    ];
    final notes = conversations.where((c) => c.hasSummary).length;
    final kept = moments?.confirmed.length ?? 0;
    final waiting = moments?.pending.length ?? 0;
    final days = phoneRows.where((r) => r.hasUsage).length;

    return [
      Row(
        children: [
          StatTile(
            value: '$entries',
            label: 'entries',
            color: kitAmber,
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(width: 8),
          StatTile(
            value: '${conversations.length}',
            label: 'chats',
            color: const Color(0xFF6E73C8),
            icon: Icons.chat_bubble_outline_rounded,
          ),
          if (moments != null) ...[
            const SizedBox(width: 8),
            StatTile(
              value: '$kept',
              label: 'moments',
              color: kitCoral,
              icon: Icons.bookmark_added_outlined,
            ),
          ],
          if (phonePatterns != null) ...[
            const SizedBox(width: 8),
            StatTile(
              value: '$days',
              label: 'days',
              color: const Color(0xFF4F9D76),
              icon: Icons.phone_android_rounded,
            ),
          ],
        ],
      ),
      const KitLabel('LOOK AT OR DELETE'),
      _card([
        _Row(
          key: const ValueKey('kept-entries'),
          icon: Icons.edit_note_rounded,
          color: kitAmber,
          title: 'Check-ins and journal',
          detail: entries == 0
              ? 'Nothing yet.'
              : '$entries ${entries == 1 ? 'entry' : 'entries'}. Delete one from the Journal tab.',
        ),
        _Row(
          key: const ValueKey('kept-chats'),
          icon: Icons.chat_bubble_outline_rounded,
          color: const Color(0xFF6E73C8),
          title: 'Conversations with Sol',
          detail: conversations.isEmpty
              ? 'Nothing yet.'
              : '${conversations.length} '
                    '${conversations.length == 1 ? 'conversation' : 'conversations'}'
                    '${notes == 0 ? '' : ', $notes with a short note'}. '
                    'Delete one from the list.',
        ),
        if (moments != null)
          _Row(
            key: const ValueKey('kept-moments'),
            icon: Icons.bookmark_added_outlined,
            color: kitCoral,
            title: 'Moments',
            detail: kept == 0 && waiting == 0
                ? 'Nothing kept.'
                : '$kept kept'
                      '${waiting == 0 ? '' : ', $waiting waiting for your yes'}.',
            onTap: memory == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WhatSolRemembersPage(
                        moments: moments!,
                        memory: memory!,
                        consent: memory!.consent,
                        profileController: profileController,
                        chat: chatController,
                      ),
                    ),
                  ),
          ),
        if (phonePatterns != null)
          _Row(
            key: const ValueKey('kept-phone'),
            icon: Icons.phone_android_rounded,
            color: const Color(0xFF4F9D76),
            title: 'Phone patterns',
            detail: days == 0
                ? 'Nothing stored.'
                : '$days ${days == 1 ? 'day' : 'days'} of patterns, kept for '
                      '${profileController.profile.featureRetentionDays} days.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PhonePatternsPage(
                  phonePatterns: phonePatterns!,
                  profileController: profileController,
                ),
              ),
            ),
          ),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
        child: Text(
          'Your choices, like sleep hours and preferences, are kept too. '
          'Nothing leaves unless you switch it on in What Sol remembers.',
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

  Widget _card(List<Widget> rows) => KitCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 70, color: _line),
          rows[i],
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: icon, color: color, size: 40),
            const SizedBox(width: 14),
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
                    detail,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: _soft,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(Icons.chevron_right_rounded, color: _muted),
              ),
          ],
        ),
      ),
    );
  }
}
