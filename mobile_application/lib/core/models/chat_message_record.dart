import 'dart:convert';

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

  ChatMessageRecord copyWith({
    String? text,
    String? voiceDuration,
    String? localAudioPath,
    List<double>? waveform,
    String? turnId,
    String? transcription,
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
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ChatMessageRecord.fromJson(String source) =>
      ChatMessageRecord.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
