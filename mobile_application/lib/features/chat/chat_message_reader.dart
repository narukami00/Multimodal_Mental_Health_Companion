import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/models/chat_message_record.dart';
import '../../core/models/emotion_result.dart';
import '../../services/journal_analysis_client.dart';

/// Reads how one of the person's chat messages sounded, using the same companion-server endpoints as
/// the journal. It is the fallback for messages the live socket did not read (older messages, a server
/// that was away): a live conversation is read as it happens, with the server's running memory of it.
///
/// Context: a short message ("ok", "yeah, I guess") says almost nothing alone, so the person's few
/// previous messages are read together with it, and the reading is marked [EmotionResult.inContext].
/// A longer message is read as it stands. A voice message that still has its recording is read from
/// the recording as well as the words. Returns null on any problem, never an invented reading.
class ChatMessageReader {
  ChatMessageReader({
    required this.client,
    required this.consentGranted,
    this.readFile = _readFile,
  });

  final JournalAnalysisClient client;
  final bool Function() consentGranted;
  final Future<Uint8List?> Function(String path) readFile;

  /// Under this many words a message is read together with what the person said just before.
  static const shortWords = 6;
  static const contextMessages = 2;
  static const contextWindow = Duration(minutes: 30);
  static const _placeholder = 'Audio reflection';

  Future<EmotionResult?> call(ChatMessageRecord message, List<ChatMessageRecord> before) async {
    if (!consentGranted() || !message.isUser) return null;
    final words = message.spokenText;
    if (words.isEmpty || words == _placeholder) return null;

    final path = message.localAudioPath;
    if (message.isVoice && path != null) {
      final pcm = await readFile(path);
      if (pcm != null && pcm.length > 16000) {
        final result = await client.analyzeAudio(message.id, pcm);
        final reading = _first(result, message, inContext: false);
        if (reading != null) return reading;
      }
    }

    var text = words;
    var inContext = false;
    if (words.split(RegExp(r'\s+')).length < shortWords) {
      final recent = <String>[
        for (final m in before.reversed)
          if (m.isUser &&
              message.timestamp.difference(m.timestamp) <= contextWindow &&
              m.spokenText.isNotEmpty &&
              m.spokenText != _placeholder)
            m.spokenText,
      ].take(contextMessages).toList().reversed.toList();
      if (recent.isNotEmpty) {
        text = '${recent.join(' ')} $words';
        inContext = true;
      }
    }
    final result = await client.analyzeText(message.id, text);
    return _first(result, message, inContext: inContext);
  }

  static EmotionResult? _first(JournalAnalysis? analysis, ChatMessageRecord m, {required bool inContext}) {
    if (analysis == null) return null;
    final results = analysis.toResults(sessionId: m.id, at: m.timestamp);
    if (results.isEmpty) return null;
    return results.first.copyWith(origin: EmotionOrigin.chat, inContext: inContext);
  }

  /// A 16 kHz mono WAV written by the chat recorder: the raw samples after its 44-byte header.
  static Future<Uint8List?> _readFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length <= 44) return null;
      return Uint8List.sublistView(bytes, 44);
    } catch (e) {
      debugPrint('[Chat] could not read a recording: ${e.runtimeType}');
      return null;
    }
  }
}
