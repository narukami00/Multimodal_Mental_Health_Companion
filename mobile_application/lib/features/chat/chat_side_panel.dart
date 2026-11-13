import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/chat_conversation_record.dart';
import '../../domain/chat/conversation_search.dart';
import 'chat_controller.dart';
import 'conversation_history.dart';
import 'highlighted_text.dart';

/// Right-hand ChatGPT/Claude-inspired side panel for ChatPage:
/// pinned top search + new-chat CTA, full-height scrollable conversation list
/// (so filtering never shrinks under the mobile keyboard), and pinned bottom
/// conversation tools (emotional breakdown and companion server status).
class ChatSidePanel extends StatefulWidget {
  const ChatSidePanel({
    required this.chatController,
    required this.isServerConnected,
    required this.isServerConnecting,
    required this.onSelectThread,
    required this.onNewConversation,
    required this.onOpenBreakdown,
    required this.onOpenServerSettings,
    this.activeThreadId,
    this.lastLatencyMs,
    this.onDeleteThread,
    super.key,
  });

  final ChatController chatController;
  final String? activeThreadId;
  final bool isServerConnected;
  final bool isServerConnecting;
  final int? lastLatencyMs;
  final ValueChanged<ConversationThread> onSelectThread;
  final VoidCallback onNewConversation;
  final VoidCallback onOpenBreakdown;
  final VoidCallback onOpenServerSettings;
  final ValueChanged<String>? onDeleteThread;

  @override
  State<ChatSidePanel> createState() => _ChatSidePanelState();
}

class _ChatSidePanelState extends State<ChatSidePanel> {
  static const _ink = Color(0xFF46382A);
  static const _softInk = Color(0xFF7B6A55);
  static const _amber = Color(0xFFFFB534);
  static const _coral = Color(0xFFE07352);
  static const _sage = Color(0xFF3F9A7C);

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.chatController.highlightQuery;
    if (initial != null && initial.isNotEmpty) {
      _query = initial;
      _searchController.text = initial;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    setState(() => _query = value);
  }

  void _confirmDelete(BuildContext context, ConversationThread thread) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFDF8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete conversation?',
          style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
        ),
        content: Text(
          '"${thread.title}" will be permanently removed from this device.',
          style: const TextStyle(color: _softInk, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: _softInk)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onDeleteThread?.call(thread.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: _coral,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = math.min(screenWidth * 0.86, 344.0);

    return Drawer(
      key: const ValueKey('chat-side-panel'),
      width: drawerWidth,
      backgroundColor: const Color(0xFFFFFDF7),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: widget.chatController,
          builder: (context, _) {
            final records = [
              for (final r in widget.chatController.conversations)
                if (r.hasUserMessage) r,
            ];
            final hasQuery = _query.trim().isNotEmpty;
            final visible = <({
              ChatConversationRecord record,
              ConversationThread thread,
              ConversationSearchMatch? match,
            })>[];

            for (final r in records) {
              final thread = ConversationThread.fromRecord(
                r,
                isActive: r.id == widget.activeThreadId,
              );
              if (!hasQuery) {
                visible.add((record: r, thread: thread, match: null));
              } else {
                final hit = matchConversationRecord(r, _query);
                if (hit != null) {
                  visible.add((record: r, thread: thread, match: hit));
                }
              }
            }

            final serverDotColor = widget.isServerConnected
                ? const Color(0xFF10B981)
                : widget.isServerConnecting
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFCBD5E0);
            final serverSubtitle = widget.isServerConnected
                ? 'Live · ${widget.lastLatencyMs ?? 0}ms'
                : widget.isServerConnecting
                    ? 'Connecting…'
                    : 'Offline · Tap to configure';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header + Search Bar + New Chat CTA
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  _amber.withValues(alpha: 0.28),
                                  _coral.withValues(alpha: 0.2),
                                ],
                              ),
                            ),
                            child: const Icon(
                              Icons.forum_outlined,
                              size: 16,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Conversations',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('side-panel-close'),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Close panel',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            style: IconButton.styleFrom(
                              foregroundColor: _softInk,
                              minimumSize: const Size(36, 36),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('history-search-field'),
                        controller: _searchController,
                        onChanged: _setQuery,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search chats & keywords…',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF9C8D79),
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 19,
                            color: _softInk,
                          ),
                          suffixIcon: hasQuery
                              ? IconButton(
                                  key: const ValueKey('history-search-clear'),
                                  onPressed: () {
                                    _searchController.clear();
                                    _setQuery('');
                                    widget.chatController.setHighlightQuery(null);
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: _softInk,
                                  ),
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF6EFE0),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: const ValueKey('side-panel-new-chat'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onNewConversation();
                        },
                        icon: const Icon(Icons.edit_square, size: 17),
                        label: const Text(
                          'New conversation',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF1D6),
                          foregroundColor: _ink,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: const BorderSide(color: Color(0x33B48228)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        hasQuery
                            ? '${visible.length} ${visible.length == 1 ? 'MATCH' : 'MATCHES'}'
                            : 'HISTORY',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Color(0xFF9C8D79),
                        ),
                      ),
                    ],
                  ),
                ),
                // Full-height flexible conversation list (never shrinks below keyboard)
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              hasQuery
                                  ? 'No chats mention "$_query".'
                                  : 'Your past conversations with Sol will appear here.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                                color: _softInk,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final entry = visible[index];
                            final thread = entry.thread;
                            final match = entry.match;
                            final isActive = thread.isActive;
                            final subtitleText =
                                match?.matchedExcerpt ?? thread.preview;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: ValueKey('history-thread-${thread.id}'),
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  widget.chatController.setHighlightQuery(
                                    hasQuery ? _query : null,
                                  );
                                  Navigator.of(context).pop();
                                  widget.onSelectThread(thread);
                                },
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFFFFF4DB)
                                        : match != null
                                            ? const Color(0xFFFFFAEE)
                                            : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isActive
                                          ? _amber.withValues(alpha: 0.7)
                                          : match != null
                                              ? const Color(0x45B48228)
                                              : const Color(0x1846382A),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: HighlightedText(
                                                    thread.title,
                                                    query: hasQuery ? _query : '',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w800,
                                                      color: _ink,
                                                    ),
                                                  ),
                                                ),
                                                if (match != null) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFFFFE5B4),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              99),
                                                    ),
                                                    child: Text(
                                                      '${match.matchCount} ${match.matchCount == 1 ? 'hit' : 'hits'}',
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Color(0xFF7D5007),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (subtitleText.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              HighlightedText(
                                                subtitleText,
                                                query: hasQuery ? _query : '',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  height: 1.35,
                                                  color: _softInk,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            Text(
                                              '${thread.dateStr} · ${thread.messageCount} ${thread.messageCount == 1 ? 'msg' : 'msgs'}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF9C8D79),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (widget.onDeleteThread != null)
                                        IconButton(
                                          onPressed: () =>
                                              _confirmDelete(context, thread),
                                          tooltip: 'Delete conversation',
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 17,
                                          ),
                                          style: IconButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFFB5A794),
                                            minimumSize: const Size(30, 30),
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Pinned Bottom Conversation Tools (Breakdown + Companion Server)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFCF7EA),
                    border: Border(
                      top: BorderSide(color: Color(0x1EB4965A)),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PanelActionRow(
                        key: const ValueKey('chat-breakdown'),
                        icon: Icons.mood_rounded,
                        iconColor: _coral,
                        iconBg: const Color(0x1AE07352),
                        title: 'Emotional breakdown',
                        subtitle: 'How this conversation felt',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onOpenBreakdown();
                        },
                      ),
                      const SizedBox(height: 6),
                      _PanelActionRow(
                        key: const ValueKey('chat-server-settings'),
                        icon: widget.isServerConnected
                            ? Icons.sensors_rounded
                            : Icons.dns_outlined,
                        iconColor: widget.isServerConnected
                            ? _sage
                            : widget.isServerConnecting
                                ? const Color(0xFFD97706)
                                : _softInk,
                        iconBg: widget.isServerConnected
                            ? const Color(0x1A3F9A7C)
                            : const Color(0x1446382A),
                        statusDotColor: serverDotColor,
                        title: 'Companion server',
                        subtitle: serverSubtitle,
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onOpenServerSettings();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PanelActionRow extends StatelessWidget {
  const _PanelActionRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.statusDotColor,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? statusDotColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 19, color: iconColor),
                  ),
                  if (statusDotColor != null)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusDotColor,
                          border: Border.all(
                            color: const Color(0xFFFCF7EA),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF46382A),
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7B6A55),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFFB5A794),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
