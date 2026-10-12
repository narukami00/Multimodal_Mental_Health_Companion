import 'dart:convert';

import 'emotion_result.dart';

/// Represents a single message in a chat conversation.
class ChatMessageRecord {
  const ChatMessageRecord({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.isVoice = false,
    this.voiceDuration = '0:00',
    this.localAudioPath,
    this.waveform,
    this.turnId,
    this.transcription,
    this.reading,
  });

  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final bool isVoice;
  final String voiceDuration;
  final String? localAudioPath;
  final List<double>? waveform;
  final String? turnId;
  final String? transcription;

  /// How the model read this message (only ever set on the person's own messages, and only with their
  /// OK). Null on older messages and while a reading is pending.
  final EmotionResult? reading;

  /// What the person actually said: the transcription of a voice message, else the typed text.
  String get spokenText {
    final t = transcription?.trim();
    return isVoice && t != null && t.isNotEmpty ? t : text.trim();
  }

  ChatMessageRecord copyWith({
    String? text,
    String? voiceDuration,
    String? localAudioPath,
    List<double>? waveform,
    String? turnId,
    String? transcription,
    EmotionResult? reading,
  }) {
    return ChatMessageRecord(
      id: id,
      isUser: isUser,
      text: text ?? this.text,
      timestamp: timestamp,
      isVoice: isVoice,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      localAudioPath: localAudioPath ?? this.localAudioPath,
      waveform: waveform ?? this.waveform,
      turnId: turnId ?? this.turnId,
      transcription: transcription ?? this.transcription,
      reading: reading ?? this.reading,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'isUser': isUser,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isVoice': isVoice,
      'voiceDuration': voiceDuration,
      'localAudioPath': localAudioPath,
      'waveform': waveform,
      'turnId': turnId,
      'transcription': transcription,
      if (reading != null) 'reading': reading!.toMap(),
    };
  }

  factory ChatMessageRecord.fromMap(Map<String, dynamic> map) {
    return ChatMessageRecord(
      id: map['id'] as String? ?? '',
      isUser: map['isUser'] as bool? ?? false,
      text: map['text'] as String? ?? '',
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      isVoice: map['isVoice'] as bool? ?? false,
      voiceDuration: map['voiceDuration'] as String? ?? '0:00',
      localAudioPath: map['localAudioPath'] as String?,
      waveform: (map['waveform'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      turnId: map['turnId'] as String?,
      transcription: map['transcription'] as String?,
      reading: map['reading'] is Map
          ? EmotionResult.fromMap(Map<String, dynamic>.from(map['reading'] as Map))
          : null,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ChatMessageRecord.fromJson(String source) =>
      ChatMessageRecord.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
