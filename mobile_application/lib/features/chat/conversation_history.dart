import 'package:flutter/material.dart';

import '../../core/models/chat_conversation_record.dart';
import '../../domain/chat/conversation_search.dart';
import 'chat_controller.dart';
import 'highlighted_text.dart';

class ConversationThread {
  const ConversationThread({
    required this.id,
    required this.title,
    required this.dateStr,
    required this.preview,
    required this.messageCount,
    this.hasVoice = false,
    this.isActive = false,
  });

  final String id;
  final String title;
  final String dateStr;
  final String preview;
  final int messageCount;
  final bool hasVoice;
  final bool isActive;

  factory ConversationThread.fromRecord(
    ChatConversationRecord record, {
    bool isActive = false,
  }) {
    return ConversationThread(
      id: record.id,
      title: record.title,
      dateStr: record.dateStr,
      preview: record.preview,
      messageCount: record.messageCount,
      hasVoice: record.hasVoice,
      isActive: isActive,
    );
  }

  static const sampleThreads = <ConversationThread>[];
}

class ConversationHistorySheet extends StatefulWidget {
  const ConversationHistorySheet({
    required this.onSelectThread,
    required this.onNewConversation,
    this.chatController,
    this.onDeleteThread,
    this.activeThreadId,
    this.startSearching = false,
    super.key,
  });

  final ValueChanged<ConversationThread> onSelectThread;
  final VoidCallback onNewConversation;
  final ValueChanged<String>? onDeleteThread;
  final ChatController? chatController;
  final String? activeThreadId;
  final bool startSearching;

  static const _ink = Color(0xFF3A3125);
  static const _softInk = Color(0xFF6E6252);
  static const _amber = Color(0xFFFFB534);
  static const _coral = Color(0xFFFF7F50);

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<ConversationThread> onSelectThread,
    required VoidCallback onNewConversation,
    ChatController? chatController,
    ValueChanged<String>? onDeleteThread,
    String? activeThreadId,
    bool startSearching = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConversationHistorySheet(
        onSelectThread: onSelectThread,
        onNewConversation: onNewConversation,
        chatController: chatController,
        onDeleteThread: onDeleteThread,
        activeThreadId: activeThreadId,
        startSearching: startSearching,
      ),
    );
  }

  @override
  State<ConversationHistorySheet> createState() =>
      _ConversationHistorySheetState();
}

class _ConversationHistorySheetState extends State<ConversationHistorySheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  late bool _searching = widget.startSearching;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final existing = widget.chatController?.highlightQuery;
    if (widget.startSearching || (existing != null && existing.isNotEmpty)) {
      _searching = true;
      if (existing != null && existing.isNotEmpty) {
        _query = existing;
        _searchController.text = existing;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocus.requestFocus();
        });
      }
    });
  }

  ConversationSearchMatch? _matchFallbackThread(
    ConversationThread thread,
    String query,
  ) {
    final terms = searchQueryTerms(query);
    if (terms.isEmpty) return null;
    final haystack = '${thread.title}\n${thread.preview}'.toLowerCase();
    for (final t in terms) {
      if (!haystack.contains(t)) return null;
    }
    final titleLower = thread.title.toLowerCase();
    return ConversationSearchMatch(
      conversationId: thread.id,
      titleMatched: terms.any(titleLower.contains),
      summaryMatched: false,
      matchCount: terms.length,
      matchedExcerpt: thread.preview,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.chatController ?? ChangeNotifier(),
      builder: (context, _) {
        final records = widget.chatController?.conversations ?? const [];
        final currentActiveId = widget.activeThreadId;
        final List<ConversationThread> allThreads;

        if (widget.chatController != null) {
          allThreads = records
              .map(
                (c) => ConversationThread.fromRecord(
                  c,
                  isActive: c.id == currentActiveId,
                ),
              )
              .toList();
        } else {
          allThreads = ConversationThread.sampleThreads;
        }

        final trimmedQuery = _query.trim();
        final matchesById = <String, ConversationSearchMatch>{};
        final List<ConversationThread> threads;

        if (trimmedQuery.isEmpty) {
          threads = allThreads;
        } else {
          final filtered = <ConversationThread>[];
          if (widget.chatController != null) {
            final byId = {for (final r in records) r.id: r};
            for (final thread in allThreads) {
              final rec = byId[thread.id];
              if (rec == null) continue;
              final match = matchConversationRecord(rec, trimmedQuery);
              if (match != null) {
                matchesById[thread.id] = match;
                filtered.add(thread);
              }
            }
          } else {
            for (final thread in allThreads) {
              final match = _matchFallbackThread(thread, trimmedQuery);
              if (match != null) {
                matchesById[thread.id] = match;
                filtered.add(thread);
              }
            }
          }
          filtered.sort((a, b) {
            final ma = matchesById[a.id]?.matchCount ?? 0;
            final mb = matchesById[b.id]?.matchCount ?? 0;
            return mb.compareTo(ma);
          });
          threads = filtered;
        }

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFFEFCE8),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x384A3B2A),
                blurRadius: 30,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: ConversationHistorySheet._ink.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Conversations',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: ConversationHistorySheet._ink,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              trimmedQuery.isNotEmpty
                                  ? '${threads.length} ${threads.length == 1 ? 'conversation matches' : 'conversations match'} "$trimmedQuery"'
                                  : threads.isEmpty
                                  ? 'No saved conversations'
                                  : '${threads.length} ${threads.length == 1 ? "thread" : "threads"} · kept safe with Sol',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: ConversationHistorySheet._softInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('history-search-toggle'),
                        onPressed: _toggleSearch,
                        tooltip: _searching ? 'Close search' : 'Search chats',
                        icon: Icon(
                          _searching
                              ? Icons.search_off_rounded
                              : Icons.search_rounded,
                          size: 21,
                          color: _searching
                              ? ConversationHistorySheet._coral
                              : ConversationHistorySheet._ink,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: _searching
                              ? const Color(0x20FF7F50)
                              : const Color(0x147A5D3A),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          widget.chatController?.setHighlightQuery(null);
                          Navigator.of(context).pop();
                          widget.onNewConversation();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: TextField(
                      key: const ValueKey('history-search-field'),
                      controller: _searchController,
                      focusNode: _searchFocus,
                      autofocus: true,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'Search by keyword, topic, or memory…',
                        hintStyle: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF9B8C76),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: ConversationHistorySheet._softInk,
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                key: const ValueKey('history-search-clear'),
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: ConversationHistorySheet._softInk,
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFFFFEFA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0x337A5D3A),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0x337A5D3A),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: ConversationHistorySheet._amber,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                const Divider(color: Color(0x1F7A5D3A), height: 1),
                if (threads.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          trimmedQuery.isNotEmpty
                              ? Icons.search_off_rounded
                              : Icons.forum_outlined,
                          size: 40,
                          color: const Color(0xFFB7A98F),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          trimmedQuery.isNotEmpty
                              ? 'No conversations matched "$trimmedQuery"'
                              : 'No conversations yet',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: ConversationHistorySheet._ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          trimmedQuery.isNotEmpty
                              ? 'Try a shorter word or check another phrase.'
                              : 'Tap + New to start a quiet space with Sol.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: ConversationHistorySheet._softInk,
                          ),
                        ),
                        if (trimmedQuery.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            child: const Text('Clear search'),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                      itemCount: threads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final thread = threads[i];
                        final isActive = thread.isActive;
                        final match = matchesById[thread.id];
                        final isHighlighted = match != null;
                        final previewText =
                            match?.matchedExcerpt ?? thread.preview;

                        return Container(
                          key: ValueKey('history-thread-${thread.id}'),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? const Color(0xFFFFF8E2)
                                : isActive
                                ? const Color(0xFFFFF9EC)
                                : const Color(0xFFFFFEFB),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isHighlighted || isActive
                                  ? const Color(0xB3FFB534)
                                  : const Color(0x2E7A5D3A),
                              width: isHighlighted || isActive ? 1.5 : 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0F78501E),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                widget.chatController?.setHighlightQuery(
                                  trimmedQuery.isEmpty ? null : trimmedQuery,
                                );
                                Navigator.of(context).pop();
                                widget.onSelectThread(thread);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: isActive || isHighlighted
                                                  ? const [
                                                      ConversationHistorySheet
                                                          ._amber,
                                                      ConversationHistorySheet
                                                          ._coral,
                                                    ]
                                                  : const [
                                                      Color(0xFFFFE8B5),
                                                      Color(0xFFFFD07A),
                                                    ],
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.chat_bubble_outline_rounded,
                                            size: 16,
                                            color: isActive || isHighlighted
                                                ? Colors.white
                                                : const Color(0xFF6B4A1A),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              HighlightedText(
                                                thread.title,
                                                query: trimmedQuery,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      ConversationHistorySheet
                                                          ._ink,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                '${thread.dateStr} · ${thread.messageCount} messages',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      ConversationHistorySheet
                                                          ._softInk,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (match != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0x33FFB534),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${match.matchCount} ${match.matchCount == 1 ? 'hit' : 'hits'}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF7D5007),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        if (isActive) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0x24FF7F50),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'ACTIVE',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.8,
                                                color: Color(0xFFC0441C),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        if (widget.onDeleteThread != null)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: Color(0xFFB7A98F),
                                            ),
                                            tooltip: 'Delete thread',
                                            onPressed: () =>
                                                widget.onDeleteThread?.call(
                                                  thread.id,
                                                ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    HighlightedText(
                                      previewText,
                                      query: trimmedQuery,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF63523F),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
