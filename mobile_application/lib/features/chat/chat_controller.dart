import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/chat_conversation_record.dart';
import '../../core/models/chat_message_record.dart';
import '../../core/models/emotion_result.dart';

/// Manages persistent chat conversation sessions, message history, and active session state.
class ChatController extends ChangeNotifier {
  ChatController({
    SharedPreferences? preferences,
    String storageKey = _defaultStorageKey,
    String activeIdKey = _defaultActiveIdKey,
  })  : _prefs = preferences,
        _storageKey = storageKey,
        _activeIdKey = activeIdKey;

  SharedPreferences? _prefs;
  static const _defaultStorageKey = 'solace_chat_conversations_v2';
  static const _defaultActiveIdKey = 'solace_active_chat_id_v2';

  final String _storageKey;
  final String _activeIdKey;

  static const defaultGreeting =
      "Hello. Take your time here. Whatever you're holding today, "
      "you don't have to carry it all by yourself. What feels present right now?";

  List<ChatConversationRecord> _conversations = [];
  String? _activeConversationId;
  bool _isLoaded = false;

  /// Returns persistent conversations that contain at least one user message.
  List<ChatConversationRecord> get conversations =>
      List.unmodifiable(_conversations.where((c) => c.hasUserMessage));

  /// Returns true if the user has at least one active, real conversation.
  bool get hasHistory => _conversations.any((c) => c.hasUserMessage);

  bool get isLoaded => _isLoaded;

  ChatConversationRecord? get activeConversation {
    if (_conversations.isEmpty) {
      _seedFirstConversation();
    }
    if (_activeConversationId != null) {
      for (final conv in _conversations) {
        if (conv.id == _activeConversationId) return conv;
      }
    }
    return _conversations.isNotEmpty ? _conversations.first : null;
  }

  /// Initialize and load saved conversations from persistent storage.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();

    final rawJson = _prefs?.getString(_storageKey);
    final savedActiveId = _prefs?.getString(_activeIdKey);

    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        _conversations = decoded
            .whereType<Map<String, dynamic>>()
            .map(ChatConversationRecord.fromMap)
            .where((c) => c.hasUserMessage)
            .toList();
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (e) {
        debugPrint('[ChatController] Error loading conversations: $e');
        _conversations = [];
      }
    }

    _activeConversationId = savedActiveId;

    // If no real conversations exist, prepare an in-memory clean draft session
    if (_conversations.isEmpty) {
      _seedFirstConversation();
    } else if (_activeConversationId == null ||
        !_conversations.any((c) => c.id == _activeConversationId)) {
      _activeConversationId = _conversations.first.id;
    }

    _isLoaded = true;
    notifyListeners();
  }

  static int _idCounter = 0;

  /// Generates a globally unique identifier guaranteed not to collide even within the same microsecond.
  static String generateId(String prefix) {
    _idCounter++;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '${prefix}_${micros}_$_idCounter';
  }

  void _seedFirstConversation() {
    final now = DateTime.now();
    final firstId = generateId('conv');
    final initialMessage = ChatMessageRecord(
      id: generateId('msg'),
      isUser: false,
      text: defaultGreeting,
      timestamp: now,
    );
    final initialConv = ChatConversationRecord(
      id: firstId,
      title: 'Holding space today',
      createdAt: now,
      updatedAt: now,
      messages: [initialMessage],
    );
    _conversations = [initialConv];
    _activeConversationId = firstId;
  }

  /// Start a fresh, clean conversation session.
  ChatConversationRecord startNewConversation() {
    // If the active conversation is already clean (no user messages), reuse it directly
    final current = activeConversation;
    if (current != null && !current.hasUserMessage) {
      return current;
    }

    // Prune any draft conversations with zero user messages
    _conversations.removeWhere((c) => !c.hasUserMessage);

    final now = DateTime.now();
    final newId = generateId('conv');
    final greetingMsg = ChatMessageRecord(
      id: generateId('msg'),
      isUser: false,
      text: defaultGreeting,
      timestamp: now,
    );

    final newConv = ChatConversationRecord(
      id: newId,
      title: 'New reflection',
      createdAt: now,
      updatedAt: now,
      messages: [greetingMsg],
    );

    _conversations.insert(0, newConv);
    _activeConversationId = newId;
    notifyListeners();
    return newConv;
  }

  /// Prunes empty conversations that have no user messages (e.g. user entered chat and left without messaging).
  void pruneEmptyConversations() {
    final realConvs = _conversations.where((c) => c.hasUserMessage).toList();
    if (realConvs.isNotEmpty) {
      ChatConversationRecord? active;
      if (_activeConversationId != null) {
        for (final c in _conversations) {
          if (c.id == _activeConversationId) {
            active = c;
            break;
          }
        }
      }
      if (active == null || !active.hasUserMessage) {
        _activeConversationId = realConvs.first.id;
      }
      _conversations.removeWhere((c) => !c.hasUserMessage);
    } else {
      if (_conversations.length > 1 || _conversations.isEmpty) {
        _conversations.clear();
        _seedFirstConversation();
      }
    }
    _saveToPrefs();
    notifyListeners();
  }

  /// Switch the active conversation to a specific thread ID.
  void switchConversation(String id) {
    if (_activeConversationId == id) return;
    if (_conversations.any((c) => c.id == id)) {
      _activeConversationId = id;
      _prefs?.setString(_activeIdKey, id);
      notifyListeners();
    }
  }

  /// Called after the person sends a typed message, so other features can look
  /// at it. Voice messages are not passed on until they have a transcription.
  void Function(ChatMessageRecord message)? onUserMessage;

  /// Append a new message to the active conversation and auto-save.
  Future<void> addMessage(ChatMessageRecord message) async {
    if (_conversations.isEmpty || _activeConversationId == null) {
      startNewConversation();
    }

    final activeIdx =
        _conversations.indexWhere((c) => c.id == _activeConversationId);
    if (activeIdx < 0) return;

    final current = _conversations[activeIdx];
    final updatedMessages = List<ChatMessageRecord>.from(current.messages)
      ..add(message);

    // Derive a concise, expressive title if title is still default
    var title = current.title;
    if ((title == 'New reflection' ||
            title == 'Conversation with Sol' ||
            title == 'Holding space today') &&
        message.isUser) {
      if (message.isVoice) {
        title = message.transcription != null &&
                message.transcription!.trim().isNotEmpty
            ? _deriveTitle(message.transcription!)
            : 'Voice check-in';
      } else {
        title = _deriveTitle(message.text);
      }
    }

    final updatedConv = current.copyWith(
      title: title,
      updatedAt: DateTime.now(),
      messages: updatedMessages,
    );

    _conversations[activeIdx] = updatedConv;
    // Re-sort so most recently active conversation stays at the top
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await _saveToPrefs();
    notifyListeners();
    if (message.isUser && !message.isVoice) onUserMessage?.call(message);
    if (message.isUser) await _givePendingReading(message);
  }

  /// Update an existing message (e.g. adding transcription or finishing LLM stream).
  Future<void> updateMessage(
    String messageId,
    ChatMessageRecord updatedMessage,
  ) async {
    final activeIdx =
        _conversations.indexWhere((c) => c.id == _activeConversationId);
    if (activeIdx < 0) return;

    final current = _conversations[activeIdx];
    final msgIdx = current.messages.indexWhere((m) => m.id == messageId);
    if (msgIdx < 0) return;

    final updatedMessages = List<ChatMessageRecord>.from(current.messages);
    // A later update (audio path, transcript) must not wipe a reading that arrived in between.
    updatedMessages[msgIdx] = updatedMessage.reading == null && current.messages[msgIdx].reading != null
        ? updatedMessage.copyWith(reading: current.messages[msgIdx].reading)
        : updatedMessage;

    // Update title if user transcription just arrived
    var title = current.title;
    if ((title == 'New reflection' ||
            title == 'Voice check-in' ||
            title == 'Holding space today' ||
            title == 'Conversation with Sol') &&
        updatedMessage.isUser &&
        updatedMessage.transcription != null &&
        updatedMessage.transcription!.isNotEmpty) {
      title = _deriveTitle(updatedMessage.transcription!);
    }

    final updatedConv = current.copyWith(
      title: title,
      updatedAt: DateTime.now(),
      messages: updatedMessages,
    );

    _conversations[activeIdx] = updatedConv;
    await _saveToPrefs();
    notifyListeners();
  }

  // --- how each of the person's messages read ---------------------------------

  /// Reads one message of the person's when the live socket did not (older messages, or a server that
  /// was away). Given the message and the messages before it in the same conversation; null = no reading.
  /// Set by the app only when the person agreed to Sol noticing how they sound.
  Future<EmotionResult?> Function(ChatMessageRecord message, List<ChatMessageRecord> before)? messageReader;

  bool get canReadMessages => messageReader != null;

  ChatConversationRecord? conversationById(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Keeps [reading] on message [messageId], wherever its conversation is.
  Future<void> setReading(String messageId, EmotionResult reading) async {
    for (var c = 0; c < _conversations.length; c++) {
      final conv = _conversations[c];
      final i = conv.messages.indexWhere((m) => m.id == messageId && m.isUser);
      if (i < 0) continue;
      final messages = List<ChatMessageRecord>.from(conv.messages);
      messages[i] = messages[i].copyWith(reading: reading);
      _conversations[c] = conv.copyWith(messages: messages);
      await _saveToPrefs();
      notifyListeners();
      return;
    }
  }

  EmotionResult? _pendingReading;
  DateTime? _pendingAt;

  /// A live reading from the server (typed text, a voice message, or a call turn read with voice and
  /// face) arrives just after the person's turn: it belongs to the newest message of theirs that has none
  /// yet, if that message is recent. If the message is not saved yet (a call turn's words can land a
  /// moment after the reading) the reading waits briefly and is given to the next message of theirs.
  Future<bool> attachToLatestUserMessage(EmotionResult reading, {Duration within = const Duration(seconds: 20)}) async {
    final conv = activeConversation;
    if (conv != null) {
      for (var i = conv.messages.length - 1; i >= 0; i--) {
        final m = conv.messages[i];
        if (!m.isUser) continue;
        if (m.reading != null) return false; // already read (another listener got there first)
        if (DateTime.now().difference(m.timestamp) <= within) {
          await setReading(m.id, reading);
          return true;
        }
        break;
      }
    }
    _pendingReading = reading;
    _pendingAt = DateTime.now();
    return false;
  }

  Future<void> _givePendingReading(ChatMessageRecord message) async {
    final reading = _pendingReading;
    final at = _pendingAt;
    if (reading == null || at == null || !message.isUser || message.reading != null) return;
    _pendingReading = null;
    _pendingAt = null;
    if (DateTime.now().difference(at) > const Duration(seconds: 20)) return;
    await setReading(message.id, reading);
  }

  /// Reads one message now, with the messages before it as context. Returns the reading, or null.
  Future<EmotionResult?> readMessage(String conversationId, String messageId) async {
    final reader = messageReader;
    final conv = conversationById(conversationId);
    if (reader == null || conv == null) return null;
    final i = conv.messages.indexWhere((m) => m.id == messageId && m.isUser);
    if (i < 0) return null;
    if (conv.messages[i].reading != null) return conv.messages[i].reading;
    final reading = await reader(conv.messages[i], conv.messages.sublist(0, i));
    if (reading != null) await setReading(messageId, reading);
    return reading;
  }

  /// The person's messages in [conversationId] that have words but no reading yet.
  List<ChatMessageRecord> unreadMessages(String conversationId) {
    final conv = conversationById(conversationId);
    if (conv == null) return const [];
    return [
      for (final m in conv.messages)
        if (m.isUser && m.reading == null && m.spokenText.isNotEmpty && m.spokenText != 'Audio reflection') m,
    ];
  }

  /// Reads every unread message of one conversation, oldest first, and stops at the first miss (the
  /// server is away). Returns how many were read.
  Future<int> readUnreadMessages(String conversationId, {void Function(int done, int total)? onProgress}) async {
    final todo = unreadMessages(conversationId);
    var done = 0;
    for (final m in todo) {
      final r = await readMessage(conversationId, m.id);
      if (r == null) break;
      done++;
      onProgress?.call(done, todo.length);
    }
    return done;
  }

  /// Stores the summary of a conversation's older messages, covering up to and
  /// including [throughId]. Ignored if the conversation is gone, the message is
  /// not in it, or a newer summary is already stored, so a slow reply that
  /// arrives late can never roll a summary back.
  Future<void> setSummary(
    String conversationId,
    String summary,
    String throughId, {
    DateTime? at,
  }) async {
    final text = summary.trim();
    if (text.isEmpty) return;
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;
    final conversation = _conversations[index];
    final newest = conversation.messages.indexWhere((m) => m.id == throughId);
    if (newest < 0) return;
    final stored = conversation.summarizedThroughId;
    if (stored != null) {
      final storedAt = conversation.messages.indexWhere((m) => m.id == stored);
      if (storedAt >= newest) return;
    }
    _conversations[index] = conversation.copyWith(
      summary: text,
      summarizedThroughId: throughId,
      summaryUpdatedAt: at ?? DateTime.now(),
    );
    await _saveToPrefs();
    notifyListeners();
  }

  /// Forgets a conversation's summary. The messages themselves stay.
  Future<void> clearSummary(String conversationId) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0 || !_conversations[index].hasSummary) return;
    _conversations[index] = _conversations[index].copyWith(clearSummary: true);
    await _saveToPrefs();
    notifyListeners();
  }

  /// Called after a conversation is deleted, with the ids of the messages the
  /// person sent in it, so things derived from them can be deleted too.
  void Function(List<String> messageIds)? onConversationDeleted;

  /// Delete a conversation by its ID.
  Future<void> deleteConversation(String id) async {
    final messageIds = [
      for (final c in _conversations.where((c) => c.id == id))
        for (final m in c.messages)
          if (m.isUser) m.id,
    ];
    _conversations.removeWhere((c) => c.id == id);
    final remaining = _conversations.where((c) => c.hasUserMessage).toList();

    if (_activeConversationId == id) {
      if (remaining.isNotEmpty) {
        _activeConversationId = remaining.first.id;
      } else {
        _seedFirstConversation();
      }
    } else if (remaining.isEmpty && _conversations.isEmpty) {
      _seedFirstConversation();
    }

    await _saveToPrefs();
    notifyListeners();
    if (messageIds.isNotEmpty) onConversationDeleted?.call(messageIds);
  }

  String _deriveTitle(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'Conversation with Sol';
    final words = cleaned.split(' ');
    if (words.length <= 5) return cleaned;
    return '${words.take(5).join(' ')}...';
  }

  Future<void> _saveToPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    try {
      final persistentConvs =
          _conversations.where((c) => c.hasUserMessage).toList();
      final jsonList = persistentConvs.map((c) => c.toMap()).toList();
      await _prefs?.setString(_storageKey, jsonEncode(jsonList));
      if (_activeConversationId != null &&
          persistentConvs.any((c) => c.id == _activeConversationId)) {
        await _prefs?.setString(_activeIdKey, _activeConversationId!);
      } else if (persistentConvs.isNotEmpty) {
        await _prefs?.setString(_activeIdKey, persistentConvs.first.id);
      } else {
        await _prefs?.remove(_activeIdKey);
      }
    } catch (e) {
      debugPrint('[ChatController] Error saving conversations: $e');
    }
  }
}
