enum CaptureMode { text, voice, video }

class SessionInput {
  const SessionInput({
    required this.sessionId,
    required this.mode,
    this.text,
    this.audioPath,
    this.videoPath,
  });

  final String sessionId;
  final CaptureMode mode;
  final String? text;
  final String? audioPath;
  final String? videoPath;
}
