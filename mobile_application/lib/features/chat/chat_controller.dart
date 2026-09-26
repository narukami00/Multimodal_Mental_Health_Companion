import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/chat_conversation_record.dart';
import '../../core/models/chat_message_record.dart';

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
    updatedMessages[msgIdx] = updatedMessage;

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

  /// Delete a conversation by its ID.
  Future<void> deleteConversation(String id) async {
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
