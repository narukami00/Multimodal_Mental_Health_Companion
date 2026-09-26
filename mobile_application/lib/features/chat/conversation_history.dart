import 'package:flutter/material.dart';

import '../../core/models/chat_conversation_record.dart';
import 'chat_controller.dart';

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

class ConversationHistorySheet extends StatelessWidget {
  const ConversationHistorySheet({
    required this.onSelectThread,
    required this.onNewConversation,
    this.chatController,
    this.onDeleteThread,
    this.activeThreadId,
    super.key,
  });

  final ValueChanged<ConversationThread> onSelectThread;
  final VoidCallback onNewConversation;
  final ValueChanged<String>? onDeleteThread;
  final ChatController? chatController;
  final String? activeThreadId;

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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatController ?? ChangeNotifier(),
      builder: (context, _) {
        final List<ConversationThread> threads;
        final currentActiveId = activeThreadId;

        if (chatController != null) {
          threads = chatController!.conversations
              .map((c) => ConversationThread.fromRecord(
                    c,
                    isActive: c.id == currentActiveId,
                  ))
              .toList();
        } else {
          threads = ConversationThread.sampleThreads;
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
                // Handle bar
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: _ink.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                // Header row
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
                                color: _ink,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              threads.isEmpty
                                  ? 'No saved conversations'
                                  : '${threads.length} ${threads.length == 1 ? "thread" : "threads"} · kept safe with Sol',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _softInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onNewConversation();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _amber,
                          foregroundColor: const Color(0xFF5A3B10),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0x1F7A5D3A), height: 1),
                // List of threads or empty state
                if (threads.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.forum_outlined,
                          size: 40,
                          color: Color(0xFFB7A98F),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No conversations yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap + New to start a quiet space with Sol.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: _softInk,
                          ),
                        ),
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

                        return Container(
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFFFF9EC)
                                : const Color(0xFFFFFEFB),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0x99FFB534)
                                  : const Color(0x2E7A5D3A),
                              width: isActive ? 1.5 : 1.0,
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
                                Navigator.of(context).pop();
                                onSelectThread(thread);
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
                                              colors: isActive
                                                  ? [_amber, _coral]
                                                  : const [
                                                      Color(0xFFFFE8B5),
                                                      Color(0xFFFFD07A),
                                                    ],
                                            ),
                                          ),
                                          child: Icon(
                                            thread.hasVoice
                                                ? Icons.mic_none_rounded
                                                : Icons
                                                    .chat_bubble_outline_rounded,
                                            size: 16,
                                            color: isActive
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
                                              Text(
                                                thread.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: _ink,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                '${thread.dateStr} · ${thread.messageCount} messages',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: _softInk,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                                        if (onDeleteThread != null)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: Color(0xFFB7A98F),
                                            ),
                                            tooltip: 'Delete thread',
                                            onPressed: () =>
                                                onDeleteThread?.call(thread.id),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      thread.preview,
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
