import '../../domain/chat/conversation_summary.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/companion_server_config.dart';
import '../../core/models/chat_message_record.dart';
import '../../core/models/emotion_result.dart';
import '../../core/models/memory_moment.dart';
import '../../domain/memory/moment_entry.dart';
import '../memory/keep_moment.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/widgets/page_back_button.dart';
import '../../services/companion_websocket_service.dart';
import '../../services/journal_analysis_client.dart';
import '../../services/pcm_audio_recorder_service.dart';
import '../../services/tts_playback_service.dart';
import '../call/call_page.dart';
import '../profile/profile_controller.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import 'chat_controller.dart';
import 'conversation_breakdown_page.dart';
import 'connection_sheet.dart';
import 'conversation_history.dart';
import 'message_reading_popover.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.safetyController,
    this.profileController,
    this.chatController,
    this.initialMessages,
    this.webSocketService,
    this.audioRecorderService,
    this.ttsPlaybackService,
    this.autoConnect = true,
    super.key,
  });

  final SafetyController safetyController;
  final ProfileController? profileController;
  final ChatController? chatController;
  final List<ChatMessageRecord>? initialMessages;
  final CompanionWebSocketService? webSocketService;
  final PcmAudioRecorderService? audioRecorderService;
  final TtsPlaybackService? ttsPlaybackService;
  final bool autoConnect;

  /// The moments the person chose to keep, shown on the conversation breakdown. Set once in main.dart.
  static List<MemoryMoment> Function()? keptMoments;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

const List<double> _mockSpeechWaveform = [
  0.15, 0.28, 0.58, 0.84, 0.66, 0.38, 0.20, 0.44,
  0.80, 0.96, 0.72, 0.36, 0.18, 0.28, 0.62, 0.88,
  0.70, 0.48, 0.22, 0.38, 0.65, 0.50, 0.28, 0.15,
];

class _Msg {
  const _Msg(
    this.isUser,
    this.text,
    this.time, {
    this.id,
    this.isVoice = false,
    this.voiceDuration = '0:00',
    this.isStreaming = false,
    this.localAudioPath,
    this.waveform,
    this.turnId,
    this.transcription,
    this.utteranceId,
    this.audioPath,
  });

  final String? id;
  final bool isUser;
  final String text;
  final String time;
  final bool isVoice;
  final String voiceDuration;
  final bool isStreaming;
  final String? localAudioPath;
  final List<double>? waveform;
  final String? turnId;
  final String? transcription;
  final String? utteranceId;
  final String? audioPath;

  static _Msg fromRecord(ChatMessageRecord r) {
    var h = r.timestamp.hour % 12;
    if (h == 0) h = 12;
    final m = r.timestamp.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m ${r.timestamp.hour >= 12 ? 'PM' : 'AM'}';
    return _Msg(
      r.isUser,
      r.text,
      timeStr,
      id: r.id,
      isVoice: r.isVoice,
      voiceDuration: r.voiceDuration,
      isStreaming: false,
      localAudioPath: r.localAudioPath,
      waveform: r.waveform,
      turnId: r.turnId,
      transcription: r.transcription,
      audioPath: r.localAudioPath,
    );
  }

  ChatMessageRecord toRecord() {
    return ChatMessageRecord(
      id: id ?? 'msg_${DateTime.now().microsecondsSinceEpoch}',
      isUser: isUser,
      text: text,
      timestamp: DateTime.now(),
      isVoice: isVoice,
      voiceDuration: voiceDuration,
      localAudioPath: localAudioPath ?? audioPath,
      waveform: waveform,
      turnId: turnId,
      transcription: transcription,
    );
  }
}


const _bubbleInk = Color(0xFF46382A);
const _softInk = Color(0xFF6E6252);
const _faint = Color(0xFFB7A98F);
const _amber = Color(0xFFFFB534);
const _coral = Color(0xFFFF7F50);
const _surface = Color(0xFFFFFDF4);

class _ChatPageState extends State<ChatPage> {
  static const _greeting =
      "Hello. Take your time here. Whatever you're holding today, "
      "you don't have to carry it all by yourself. What feels present right now?";

  static const _initialChips = [
    "I'm feeling a bit restless",
    'Help me unwind tonight',
    'Just want to vent',
    'Notice where I am',
  ];

  late List<String> _chips = List.of(_initialChips);

  static const _replies = [
    "I hear you. You don't have to have it figured out to say it out loud — what part feels loudest right now?",
    'Thank you for trusting me with that. What would feel even slightly lighter right now?',
    "That's a very human thing to feel. Where does your mind go when it's quiet?",
    'I\u2019m glad you said it. We can stay with this as long as you need.',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  var _messages = <_Msg>[];
  var _replyIndex = 0;

  var _isRecording = false;
  var _isLocked = false;
  var _recordingSeconds = 0;
  Timer? _recordingTimer;
  var _dragOffset = 0.0;
  var _cancelTriggered = false;

  late final ChatController _chatController;
  late final bool _ownsChatController;

  late final CompanionWebSocketService _wsService;
  StreamSubscription<CompanionConnectionStatus>? _wsStatusSub;
  StreamSubscription<int>? _wsLatencySub;
  StreamSubscription<Map<String, dynamic>>? _wsStartSub;
  StreamSubscription<Map<String, dynamic>>? _wsChunkSub;
  StreamSubscription<Map<String, dynamic>>? _wsDoneSub;
  StreamSubscription<Map<String, dynamic>>? _wsEmotionSub;

  late final PcmAudioRecorderService _audioRecorder;
  StreamSubscription<Uint8List>? _audioFrameSub;
  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<Map<String, dynamic>>? _wsAudioReceivedSub;
  StreamSubscription<Map<String, dynamic>>? _wsTranscriptFinalSub;
  StreamSubscription<Map<String, dynamic>>? _wsTranscriptFailedSub;

  final List<Uint8List> _recordedAudioChunks = [];
  double _currentAmplitude = 0.0;
  String? _activeAudioTurnId;
  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;

  late final TtsPlaybackService _ttsPlayback;
  StreamSubscription<bool>? _ttsPlayingSub;
  StreamSubscription<Map<String, String>>? _ttsAudioReadySub;

  bool _ttsEnabled = true;
  String _selectedVoiceId = 'af_bella';
  double _ttsSpeed = 0.96;

  CompanionConnectionStatus _wsStatus = CompanionConnectionStatus.disconnected;
  int? _lastLatencyMs;
  void Function(void Function())? _modalSetState;

  /// True while [CallPage] owns the shared socket: it records the call's
  /// turns itself, so this page must not record them a second time.
  var _callActive = false;

  @override
  void initState() {
    super.initState();
    _wsService = widget.webSocketService ?? CompanionWebSocketService();
    _audioRecorder = widget.audioRecorderService ?? PcmAudioRecorderService();
    _ttsPlayback = widget.ttsPlaybackService ??
        TtsPlaybackService(webSocketService: _wsService);
    _wsStatus = _wsService.status;
    _lastLatencyMs = _wsService.lastLatencyMs;

    _ttsPlayingSub = _ttsPlayback.playingStream.listen((_) {
      if (mounted) setState(() {});
    });

    _ttsAudioReadySub = _ttsPlayback.audioReadyStream.listen((data) {
      if (!mounted) return;
      final uttId = data['utterance_id'];
      final path = data['audio_path'];
      if (uttId == null || path == null) return;
      ChatMessageRecord? recordToUpdate;
      setState(() {
        for (var i = _messages.length - 1; i >= 0; i--) {
          if (_messages[i].utteranceId == uttId ||
              (_messages[i].utteranceId == null &&
                  !_messages[i].isUser &&
                  i == _messages.length - 1)) {
            final old = _messages[i];
            final updated = _Msg(
              old.isUser,
              old.text,
              old.time,
              id: old.id,
              isStreaming: old.isStreaming,
              isVoice: old.isVoice,
              voiceDuration: old.voiceDuration,
              localAudioPath: old.localAudioPath,
              waveform: old.waveform,
              turnId: old.turnId,
              transcription: old.transcription,
              utteranceId: old.utteranceId ?? uttId,
              audioPath: path,
            );
            _messages[i] = updated;
            recordToUpdate = updated.toRecord();
            break;
          }
        }
      });
      if (recordToUpdate != null && recordToUpdate!.id.isNotEmpty) {
        _chatController.updateMessage(recordToUpdate!.id, recordToUpdate!);
      }
    });

    if (widget.initialMessages != null) {
      _messages = widget.initialMessages!.map(_Msg.fromRecord).toList();
    } else {
      _messages = [_Msg(false, _greeting, _now())];
    }

    if (widget.chatController != null) {
      _chatController = widget.chatController!;
      _ownsChatController = false;
      if (_chatController.isLoaded) {
        _initChatHistory();
      } else {
        _chatController.load().then((_) {
          if (mounted) _initChatHistory();
        });
      }
    } else {
      _chatController = ChatController();
      _ownsChatController = true;
      _chatController.load().then((_) {
        if (mounted) _initChatHistory();
      });
    }

    _amplitudeSub = _audioRecorder.amplitudeStream.listen((amp) {
      if (!mounted || !_isRecording) return;
      setState(() => _currentAmplitude = amp);
    });

    _wsAudioReceivedSub = _wsService.audioReceivedStream.listen((data) {
      if (!mounted) return;
      final wav = data['wav_file'] as String?;
      final dur = data['duration_ms'] as int? ?? 0;
      debugPrint('[ChatPage] Audio captured & saved on server: $wav ($dur ms)');
    });

    _wsTranscriptFinalSub = _wsService.transcriptFinalStream.listen((data) {
      if (!mounted || _callActive) return;
      final text = data['text'] as String? ?? '';
      final turnId = data['turn_id'] as String? ?? '';
      if (text.isNotEmpty) {
        ChatMessageRecord? recordToUpdate;
        setState(() {
          for (var i = _messages.length - 1; i >= 0; i--) {
            if (_messages[i].isVoice &&
                (_messages[i].turnId == turnId || turnId.isEmpty)) {
              final old = _messages[i];
              final updated = _Msg(
                old.isUser,
                text,
                old.time,
                id: old.id,
                isVoice: true,
                voiceDuration: old.voiceDuration,
                localAudioPath: old.localAudioPath,
                waveform: old.waveform,
                turnId: old.turnId,
                transcription: text,
              );
              _messages[i] = updated;
              recordToUpdate = updated.toRecord();
              break;
            }
          }
        });
        if (recordToUpdate != null && recordToUpdate!.id.isNotEmpty) {
          _chatController.updateMessage(recordToUpdate!.id, recordToUpdate!);
        }
        _scrollDown();
      }
    });

    _wsTranscriptFailedSub = _wsService.transcriptFailedStream.listen((data) {
      if (!mounted || _callActive) return;
      final reason = data['reason'] as String? ?? '';
      final turnId = data['turn_id'] as String? ?? '';
      final label = reason == 'silence'
          ? '(No speech detected)'
          : '(Unintelligible audio)';
      ChatMessageRecord? recordToUpdate;
      setState(() {
        for (var i = _messages.length - 1; i >= 0; i--) {
          if (_messages[i].isVoice &&
              (_messages[i].turnId == turnId || turnId.isEmpty)) {
            final old = _messages[i];
            final updated = _Msg(
              old.isUser,
              old.text,
              old.time,
              id: old.id,
              isVoice: true,
              voiceDuration: old.voiceDuration,
              localAudioPath: old.localAudioPath,
              waveform: old.waveform,
              turnId: old.turnId,
              transcription: label,
            );
            _messages[i] = updated;
            recordToUpdate = updated.toRecord();
            break;
          }
        }
      });
      if (recordToUpdate != null && recordToUpdate!.id.isNotEmpty) {
        _chatController.updateMessage(recordToUpdate!.id, recordToUpdate!);
      }
    });

    _wsStatusSub = _wsService.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _wsStatus = status);
      _modalSetState?.call(() {});
      if (status == CompanionConnectionStatus.connected) {
        _wsService.sendSessionConfigure(
          mode: 'chat_voice_playback',
          ttsEnabled: _ttsEnabled,
          voiceId: _selectedVoiceId,
          speed: _ttsSpeed,
          // A resumed conversation brings its summary and last few turns, so
          // Sol remembers what was said even on a fresh connection.
          resume: resumeBlock(_chatController.activeConversation),
        );
      }
    });

    _wsLatencySub = _wsService.latencyStream.listen((latency) {
      if (!mounted) return;
      setState(() => _lastLatencyMs = latency);
      _modalSetState?.call(() {});
    });

    _wsStartSub = _wsService.llmStartStream.listen((data) {
      if (!mounted || _callActive) return;
      final msgId = 'msg_${DateTime.now().microsecondsSinceEpoch}';
      final uttId = data['utterance_id'] as String?;
      final turnId = data['turn_id'] as String?;
      setState(() {
        if (_messages.isEmpty || !_messages.last.isStreaming) {
          _messages.add(_Msg(
            false,
            '',
            _now(),
            id: msgId,
            isStreaming: true,
            utteranceId: uttId,
            turnId: turnId,
          ));
        }
      });
      _scrollDown();
    });

    _wsChunkSub = _wsService.llmChunkStream.listen((data) {
      if (!mounted || _callActive) return;
      final delta = data['delta'] as String? ?? '';
      final uttId = data['utterance_id'] as String?;
      final turnId = data['turn_id'] as String?;
      setState(() {
        if (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.isStreaming) {
          final old = _messages.last;
          _messages[_messages.length - 1] = _Msg(
            false,
            old.text + delta,
            old.time,
            id: old.id,
            isStreaming: true,
            utteranceId: uttId ?? old.utteranceId,
            turnId: turnId ?? old.turnId,
            audioPath: old.audioPath,
          );
        } else {
          final msgId = 'msg_${DateTime.now().microsecondsSinceEpoch}';
          _messages.add(_Msg(
            false,
            delta,
            _now(),
            id: msgId,
            isStreaming: true,
            utteranceId: uttId,
            turnId: turnId,
          ));
        }
      });
      _scrollDown();
    });

    _wsDoneSub = _wsService.llmDoneStream.listen((data) {
      if (!mounted || _callActive) return;
      final finalText = data['text'] as String? ?? '';
      final uttId = data['utterance_id'] as String?;
      final turnId = data['turn_id'] as String?;
      ChatMessageRecord? completedRecord;

      final rawSuggestions = data['suggestions'];
      List<String>? newSuggestions;
      if (rawSuggestions is List && rawSuggestions.isNotEmpty) {
        final parsed = rawSuggestions
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) {
          newSuggestions = parsed;
        }
      }
      newSuggestions ??= _generateLocalSuggestions(
        finalText.isNotEmpty
            ? finalText
            : (_messages.isNotEmpty ? _messages.last.text : ''),
      );

      setState(() {
        if (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.isStreaming) {
          final old = _messages.last;
          final completed = _Msg(
            false,
            finalText.isNotEmpty ? finalText : old.text,
            _now(),
            id: old.id,
            isStreaming: false,
            utteranceId: uttId ?? old.utteranceId,
            turnId: turnId ?? old.turnId,
            audioPath: old.audioPath,
          );
          _messages[_messages.length - 1] = completed;
          completedRecord = completed.toRecord();
        } else {
          final completed = _Msg(
            false,
            finalText,
            _now(),
            id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
            isStreaming: false,
            utteranceId: uttId,
            turnId: turnId,
          );
          _messages.add(completed);
          completedRecord = completed.toRecord();
        }
        _chips = newSuggestions!;
      });
      if (completedRecord != null) {
        _chatController
            .addMessage(completedRecord!)
            .then((_) => _maybeSummarize());
      }
      _scrollDown();
    });

    // The server reads each turn as it happens (with its running memory of the conversation) when the
    // person has agreed; that reading belongs to the message they just sent.
    _wsEmotionSub = _wsService.emotionUpdateStream.listen((data) {
      final reading = JournalAnalysis(transcript: '', emotion: data)
          .toResults(sessionId: data['turn_id'] as String? ?? '')
          .firstOrNull
          ?.copyWith(origin: EmotionOrigin.chat, inContext: true);
      if (reading != null) _chatController.attachToLatestUserMessage(reading);
    });

    _input.addListener(() => setState(() {}));

    _loadSavedServerConfig();

    if (widget.autoConnect &&
        !CompanionServerConfig.isTestEnvironment &&
        _wsStatus != CompanionConnectionStatus.connected &&
        _wsStatus != CompanionConnectionStatus.connecting) {
      _wsService.connect(sessionId: _chatController.activeConversation?.id);
    }
  }

  List<String> _generateLocalSuggestions(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('breathe') ||
        lower.contains('breath') ||
        lower.contains('chest')) {
      return const [
        "Let's try 1 minute",
        'I feel tension in my shoulders',
        'Can we try something else?',
      ];
    }
    if (lower.contains('sleep') ||
        lower.contains('night') ||
        lower.contains('rest') ||
        lower.contains('unwind')) {
      return const [
        'My mind is racing a bit',
        'Help me wind down',
        "I'll try to rest now",
      ];
    }
    if (lower.contains('anxious') ||
        lower.contains('worry') ||
        lower.contains('stress') ||
        lower.contains('overwhelm')) {
      return const [
        'It feels overwhelming',
        'Can you stay with me?',
        'Help me ground myself',
      ];
    }
    if (text.contains('?')) {
      return const [
        "I'm not really sure",
        'Tell me more about that',
        'A little bit of both',
      ];
    }
    return const [
      'Tell me more',
      'That resonates with me',
      'What should I do next?',
    ];
  }

  void _initChatHistory() {
    if (widget.initialMessages != null) return;
    final activeConv = _chatController.activeConversation;
    if (activeConv != null && activeConv.messages.isNotEmpty) {
      _messages = activeConv.messages.map(_Msg.fromRecord).toList();
      if (_messages.isNotEmpty && !_messages.last.isUser) {
        _chips = _generateLocalSuggestions(_messages.last.text);
      }
      if (mounted) {
        setState(() {});
      }
      _scrollDown();
    }
  }

  bool _summarizing = false;

  /// Folds older turns into the conversation's summary once enough have piled
  /// up. Quiet: nothing in the chat changes, and a missing answer just means
  /// trying again after a later turn.
  Future<void> _maybeSummarize() async {
    if (_summarizing || _wsStatus != CompanionConnectionStatus.connected) return;
    final conversation = _chatController.activeConversation;
    if (conversation == null) return;
    final plan = planSummary(conversation);
    if (plan == null) return;
    _summarizing = true;
    try {
      final summary = await _wsService.requestSummary(
        messages: turnsOf(plan.toSummarize),
        previousSummary: conversation.summary,
      );
      if (summary != null) {
        await _chatController.setSummary(conversation.id, summary, plan.throughId);
      }
    } finally {
      _summarizing = false;
    }
  }

  void _startNewConversation() {
    final newConv = _chatController.startNewConversation();
    setState(() {
      _messages = newConv.messages.map(_Msg.fromRecord).toList();
      _chips = List.of(_initialChips);
    });
    if (widget.autoConnect && !CompanionServerConfig.isTestEnvironment) {
      _wsService.connect(sessionId: newConv.id);
    }
  }

  void _switchConversation(String id) {
    _chatController.switchConversation(id);
    final conv = _chatController.activeConversation;
    if (conv != null) {
      setState(() {
        _messages = conv.messages.map(_Msg.fromRecord).toList();
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          _chips = _generateLocalSuggestions(_messages.last.text);
        } else {
          _chips = List.of(_initialChips);
        }
      });
      if (widget.autoConnect && !CompanionServerConfig.isTestEnvironment) {
        _wsService.connect(sessionId: conv.id);
      }
      _scrollDown();
    }
  }

  void _deleteConversation(String id) {
    _chatController.deleteConversation(id);
    final conv = _chatController.activeConversation;
    if (conv != null) {
      setState(() {
        _messages = conv.messages.map(_Msg.fromRecord).toList();
      });
    }
  }

  void _loadSavedServerConfig() {
    SharedPreferences.getInstance().then((prefs) {
      final tailscaleMigrated =
          prefs.getBool(CompanionServerConfig.prefKeyTailscaleMigrated) ?? false;
      var savedHost = prefs.getString(CompanionServerConfig.prefKeyHost);
      final savedPort = prefs.getInt(CompanionServerConfig.prefKeyPort);
      _ttsEnabled = prefs.getBool('companion_tts_enabled') ?? true;
      _selectedVoiceId =
          prefs.getString('companion_tts_voice_id') ?? 'af_bella';
      _ttsSpeed = prefs.getDouble('companion_tts_speed') ?? 0.96;

      // Auto-migrate from old local Wi-Fi / localhost IPs to Tailscale
      if (!tailscaleMigrated ||
          savedHost == '192.168.0.38' ||
          savedHost == '127.0.0.1' ||
          savedHost == null ||
          savedHost.isEmpty) {
        savedHost = CompanionServerConfig.defaultTailscaleIp;
        prefs.setString(CompanionServerConfig.prefKeyHost, savedHost);
        prefs.setBool(CompanionServerConfig.prefKeyTailscaleMigrated, true);
      }

      _wsService.host = savedHost;
      if (savedPort != null && savedPort > 0) {
        _wsService.port = savedPort;
      }
      if (mounted) setState(() {});

      // Auto-connect once config is loaded if not already connected/connecting
      if (widget.autoConnect &&
          !CompanionServerConfig.isTestEnvironment &&
          _wsService.status != CompanionConnectionStatus.connected &&
          _wsService.status != CompanionConnectionStatus.connecting) {
        _wsService.connect(sessionId: _chatController.activeConversation?.id);
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    if (_ownsChatController) {
      _chatController.dispose();
    }
    _ttsPlayingSub?.cancel();
    _ttsAudioReadySub?.cancel();
    if (widget.ttsPlaybackService == null) {
      _ttsPlayback.dispose();
    }
    _recordingTimer?.cancel();
    _audioFrameSub?.cancel();
    _amplitudeSub?.cancel();
    _wsAudioReceivedSub?.cancel();
    _wsTranscriptFinalSub?.cancel();
    _wsTranscriptFailedSub?.cancel();
    if (widget.audioRecorderService == null) {
      _audioRecorder.dispose();
    }
    _wsStatusSub?.cancel();
    _wsLatencySub?.cancel();
    _wsStartSub?.cancel();
    _wsChunkSub?.cancel();
    _wsDoneSub?.cancel();
    _wsEmotionSub?.cancel();
    _closeReading();
    if (widget.webSocketService == null) {
      _wsService.dispose();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    _recordingTimer?.cancel();
    final turnId =
        'turn_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    _activeAudioTurnId = turnId;
    _recordedAudioChunks.clear();

    setState(() {
      _isRecording = true;
      _isLocked = false;
      _recordingSeconds = 0;
      _dragOffset = 0.0;
      _cancelTriggered = false;
      _currentAmplitude = 0.0;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording) return;
      setState(() => _recordingSeconds++);
    });

    final started = await _audioRecorder.startRecording(
      sampleRate: 16000,
      frameMs: 100,
    );

    if (!started) {
      debugPrint('[ChatPage] Failed to start audio recorder');
      _cancelRecording();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required to record voice reflections.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (_wsStatus == CompanionConnectionStatus.connected) {
      _wsService.sendAudioStart(
        turnId: turnId,
        sampleRate: 16000,
        frameMs: 100,
      );
    }

    await _audioFrameSub?.cancel();
    _audioFrameSub = _audioRecorder.audioStream.listen((chunk) {
      if (!_isRecording) return;
      _recordedAudioChunks.add(chunk);
      if (_wsStatus == CompanionConnectionStatus.connected) {
        _wsService.sendAudioChunk(chunk);
      }
    });
  }

  Future<void> _cancelRecording() async {
    final turnId = _activeAudioTurnId;
    _activeAudioTurnId = null;
    _recordedAudioChunks.clear();
    _recordingTimer?.cancel();
    await _audioFrameSub?.cancel();
    _audioFrameSub = null;
    await _audioRecorder.cancelRecording();

    if (turnId != null && _wsStatus == CompanionConnectionStatus.connected) {
      _wsService.sendAudioCancel(turnId: turnId);
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isLocked = false;
      _dragOffset = 0.0;
      _cancelTriggered = false;
      _currentAmplitude = 0.0;
    });
  }

  Future<void> _sendRecording() async {
    final turnId = _activeAudioTurnId;
    _activeAudioTurnId = null;
    _recordingTimer?.cancel();
    await _audioFrameSub?.cancel();
    _audioFrameSub = null;
    await _audioRecorder.stopRecording();

    // Accumulate all recorded PCM chunks
    final pcmBytes = BytesBuilder();
    for (final c in _recordedAudioChunks) {
      pcmBytes.add(c);
    }
    final allPcm = pcmBytes.toBytes();
    _recordedAudioChunks.clear();

    String? localAudioPath;
    List<double>? waveform;

    if (allPcm.isNotEmpty) {
      waveform = PcmAudioRecorderService.extractWaveform(allPcm, barCount: 24);
      try {
        final wavData = PcmAudioRecorderService.createWav(
          allPcm,
          sampleRate: 16000,
          channels: 1,
          bitsPerSample: 16,
        );
        final tempDir = await getTemporaryDirectory();
        final filePath =
            '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
        final file = File(filePath);
        await file.writeAsBytes(wavData, flush: true);
        localAudioPath = filePath;
      } catch (e) {
        debugPrint('[ChatPage] Error saving local WAV audio: $e');
      }
    }

    waveform ??= _mockSpeechWaveform;

    final sec = _recordingSeconds < 1 ? 1 : _recordingSeconds;
    final durMs = sec * 1000;
    final durStr = '0:${sec.toString().padLeft(2, '0')}';

    final voiceRecord = ChatMessageRecord(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      isUser: true,
      text: 'Audio reflection',
      timestamp: DateTime.now(),
      isVoice: true,
      voiceDuration: durStr,
      localAudioPath: localAudioPath,
      waveform: waveform,
      turnId: turnId,
    );

    if (turnId != null && _wsStatus == CompanionConnectionStatus.connected) {
      _wsService.sendAudioEnd(
        turnId: turnId,
        durationMs: durMs,
      );
    }

    if (!mounted) return;
    setState(() {
      _messages.add(_Msg.fromRecord(voiceRecord));
      _isRecording = false;
      _isLocked = false;
      _dragOffset = 0.0;
      _cancelTriggered = false;
      _currentAmplitude = 0.0;
    });
    _chatController.addMessage(voiceRecord);
    _scrollDown();

    if (_wsStatus != CompanionConnectionStatus.connected) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        final replyRecord = ChatMessageRecord(
          id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
          isUser: false,
          text: _replies[_replyIndex % _replies.length],
          timestamp: DateTime.now(),
        );
        _replyIndex++;
        setState(() => _messages.add(_Msg.fromRecord(replyRecord)));
        _chatController.addMessage(replyRecord);
        _scrollDown();
      });
    }
  }

  String _now() {
    final d = DateTime.now();
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    final userRecord = ChatMessageRecord(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      isUser: true,
      text: text,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(_Msg.fromRecord(userRecord));
      _chips = [];
    });
    _chatController.addMessage(userRecord);
    _scrollDown();

    // Safety first — never bypass the screener.
    final assessment = await widget.safetyController.assessText(
      source: 'chat',
      text: text,
    );
    if (assessment.level != SafetyLevel.clear) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportResourcesPage(
            safetyController: widget.safetyController,
            profileController: widget.profileController,
            assessment: assessment,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    if (_wsStatus == CompanionConnectionStatus.connected) {
      await _wsService.sendTextMessage(text, simulateStream: true);
      return;
    }

    final replyRecord = ChatMessageRecord(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      isUser: false,
      text: _replies[_replyIndex % _replies.length],
      timestamp: DateTime.now(),
    );
    _replyIndex++;
    setState(() {
      _messages.add(_Msg.fromRecord(replyRecord));
      _chips = _generateLocalSuggestions(replyRecord.text);
    });
    _chatController.addMessage(replyRecord);
    _scrollDown();
  }

  OverlayEntry? _readingPopover;

  void _closeReading() {
    final entry = _readingPopover;
    _readingPopover = null;
    if (entry != null && entry.mounted) entry.remove();
  }

  /// Long-press on one of the person's messages: a small card saying how that message read, in the
  /// context of the conversation. A message with no reading yet is read now (needs the server and the OK).
  void _showReading(String messageId, Rect anchor) {
    final conv = _chatController.activeConversation;
    if (conv == null) return;
    final index = conv.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final message = conv.messages[index];
    _closeReading();
    HapticFeedback.mediumImpact();
    _readingPopover = showMessageReading(
      context: context,
      anchor: anchor,
      message: message,
      read: _chatController.canReadMessages ? () => _chatController.readMessage(conv.id, messageId) : null,
      onKeep: KeepMoment.available
          ? (reading) => KeepMoment.open(
              context,
              MomentEntry(
                text: message.spokenText,
                source: MomentSource.chat,
                sourceRef: 'chat:${message.id}',
                at: message.timestamp,
                reading: reading ?? message.reading,
              ),
            )
          : null,
    );
  }

  void _openBreakdown() {
    final conv = _chatController.activeConversation;
    if (conv == null) return;
    _closeReading();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationBreakdownPage(
          chatController: _chatController,
          conversationId: conv.id,
          safetyController: widget.safetyController,
          profileController: widget.profileController,
          keptMoments: ChatPage.keptMoments,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFCE8),
      body: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.8, -1),
                    radius: 1.4,
                    colors: [Color(0x24FFB534), Color(0x00FFB534)],
                    stops: [0, 0.6],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.9, 1.1),
                    radius: 1.3,
                    colors: [Color(0x1AFF7F50), Color(0x00FF7F50)],
                    stops: [0, 0.6],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      children: [
                        _buildHeader(),
                        Expanded(
                          child: ListView.builder(
                            controller: _scroll,
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final msg = _messages[i];
                              final isSpeaking = !msg.isUser &&
                                  (_ttsPlayback.isPlaying ||
                                      _ttsPlayback.isReceivingStream) &&
                                  ((_ttsPlayback.activeUtteranceId != null &&
                                          _ttsPlayback.activeUtteranceId ==
                                              msg.utteranceId) ||
                                      (_ttsPlayback.activePlayingPath != null &&
                                          _ttsPlayback.activePlayingPath ==
                                              msg.audioPath) ||
                                      (_ttsPlayback.activeUtteranceId == null &&
                                          i == _messages.length - 1));

                              return _Bubble(
                                msg: msg,
                                isSpeaking: isSpeaking,
                                onLongPress: msg.isUser && msg.id != null && !msg.isStreaming
                                    ? (anchor) => _showReading(msg.id!, anchor)
                                    : null,
                                onCancelVoice: () => _ttsPlayback.cancelVoice(
                                  utteranceId: msg.utteranceId,
                                ),
                                onReplayVoice: msg.audioPath != null
                                    ? () => _ttsPlayback.playAudioFile(
                                          msg.audioPath!,
                                          utteranceId: msg.utteranceId,
                                        )
                                    : null,
                              );
                            },
                          ),
                        ),
                        _buildChips(),
                        _buildInputBar(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xEBFEFCE8),
        border: Border(
          bottom: BorderSide(color: Color(0x24B4965A)),
        ),
      ),
      child: Row(
        children: [
          const PageBackButton(),
          const Spacer(),
          IconButton(
            onPressed: () {
              ConversationHistorySheet.show(
                context,
                chatController: _chatController,
                activeThreadId: _chatController.activeConversation?.id,
                onSelectThread: (thread) => _switchConversation(thread.id),
                onNewConversation: _startNewConversation,
                onDeleteThread: _deleteConversation,
              );
            },
            tooltip: 'Past conversations',
            icon: const Icon(Icons.history_rounded, size: 22),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6C5E50),
              minimumSize: const Size(40, 44),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() => _callActive = true);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CallPage(
                    safetyController: widget.safetyController,
                    profileController: widget.profileController,
                    webSocketService: _wsService,
                    audioRecorderService: _audioRecorder,
                    ttsPlaybackService: _ttsPlayback,
                    chatController: _chatController,
                  ),
                ),
              ).then((_) {
                if (!mounted) return;
                setState(() => _callActive = false);
                final conv = _chatController.activeConversation;
                if (conv != null) {
                  setState(() {
                    _messages = conv.messages.map(_Msg.fromRecord).toList();
                  });
                  _scrollDown();
                }
              });
            },
            tooltip: 'Call Sol',
            icon: const Icon(Icons.phone_in_talk_rounded, size: 21),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6C5E50),
              minimumSize: const Size(40, 44),
            ),
          ),
          IconButton(
            onPressed: _showConnectionSettingsDialog,
            tooltip: _wsStatus == CompanionConnectionStatus.connected
                ? 'Companion Server Live · ${_lastLatencyMs ?? 0}ms'
                : 'Configure Companion Backend',
            icon: Stack(
              alignment: Alignment.topRight,
              children: [
                Icon(
                  _wsStatus == CompanionConnectionStatus.connected
                      ? Icons.sensors_rounded
                      : Icons.dns_outlined,
                  size: 21,
                  color: _wsStatus == CompanionConnectionStatus.connected
                      ? const Color(0xFF059669)
                      : _wsStatus == CompanionConnectionStatus.connecting
                          ? const Color(0xFFD97706)
                          : _softInk,
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _wsStatus == CompanionConnectionStatus.connected
                        ? const Color(0xFF10B981)
                        : _wsStatus == CompanionConnectionStatus.connecting
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFCBD5E0),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ],
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(38, 44),
            ),
          ),
          IconButton(
            key: const ValueKey('chat-breakdown'),
            onPressed: _openBreakdown,
            tooltip: 'How this conversation felt',
            icon: const Icon(Icons.mood_rounded, size: 23),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6C5E50),
              minimumSize: const Size(40, 44),
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectionSettingsDialog() {
    // A keyboard that is still open would fight the sheet for room.
    FocusManager.instance.primaryFocus?.unfocus();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFFFFDF8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            _modalSetState = setModalState;
            final isConnected = _wsStatus == CompanionConnectionStatus.connected;

            void sendVoiceConfig() {
              if (!isConnected) return;
              _wsService.sendSessionConfigure(
                mode: 'chat_voice_playback',
                ttsEnabled: _ttsEnabled,
                voiceId: _selectedVoiceId,
                speed: _ttsSpeed,
              );
            }

            return ConnectionSheetView(
              initialHost: _wsService.host,
              initialPort: _wsService.port,
              status: _wsStatus,
              latencyMs: _lastLatencyMs,
              errorMessage: _wsService.lastErrorMessage,
              ttsEnabled: _ttsEnabled,
              voiceId: _selectedVoiceId,
              onPing: () {
                _wsService.sendPing();
                setModalState(() {});
              },
              onDisconnect: () async {
                await _wsService.disconnect();
                setModalState(() {});
                setState(() {});
              },
              onConnect: (host, port) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(CompanionServerConfig.prefKeyHost, host);
                await prefs.setInt(CompanionServerConfig.prefKeyPort, port);
                await prefs.setBool(CompanionServerConfig.prefKeyTailscaleMigrated, true);
                _wsService.connect(customHost: host, customPort: port);
                setModalState(() {});
                setState(() {});
              },
              onTtsChanged: (value) async {
                _ttsEnabled = value;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('companion_tts_enabled', value);
                sendVoiceConfig();
                setModalState(() {});
                setState(() {});
              },
              onVoiceChanged: (voiceId) async {
                _selectedVoiceId = voiceId;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('companion_tts_voice_id', voiceId);
                sendVoiceConfig();
                setModalState(() {});
                setState(() {});
              },
            );
          },
        );
      },
    ).whenComplete(() {
      _modalSetState = null;
    });
  }

  Widget _buildChips() {
    if (_chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ActionChip(
          onPressed: () => _send(_chips[i]),
          label: Text(_chips[i]),
          backgroundColor: const Color(0xFFFFF9E9),
          side: const BorderSide(color: Color(0x8CFFB534)),
          labelStyle: const TextStyle(
            color: Color(0xFF7A5B1E),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText = _input.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: _isRecording ? _buildRecordingBar() : _buildNormalInputBar(hasText),
    );
  }

  Widget _buildNormalInputBar(bool hasText) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x42FFB534)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F7A5A28),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Listener(
              onPointerDown: (e) {
                _pointerDownPos = e.position;
                _pointerDownTime = DateTime.now();
                HapticFeedback.selectionClick();
                _startRecording();
              },
              onPointerMove: (e) {
                if (_pointerDownPos == null || !_isRecording) return;
                final dx = e.position.dx - _pointerDownPos!.dx;
                final dy = e.position.dy - _pointerDownPos!.dy;
                setState(() {
                  _dragOffset = dx;
                  _cancelTriggered = dx < -50;
                  if (dy < -45 || dx > 60) {
                    _isLocked = true;
                  }
                });
              },
              onPointerUp: (e) {
                if (_pointerDownPos == null) return;
                final held = DateTime.now().difference(_pointerDownTime!);
                if (_cancelTriggered) {
                  _cancelRecording();
                } else if (_isLocked) {
                  // Remains in locked hands-free recording mode
                } else if (held < const Duration(milliseconds: 350)) {
                  // Short tap -> enter locked hands-free recording mode
                  setState(() => _isLocked = true);
                } else {
                  _sendRecording();
                }
                _pointerDownPos = null;
              },
              onPointerCancel: (e) {
                if (_cancelTriggered) {
                  _cancelRecording();
                } else if (!_isLocked) {
                  _cancelRecording();
                }
                _pointerDownPos = null;
              },
              child: Tooltip(
                message: 'Tap or hold to record voice reflection',
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.mic_rounded,
                    size: 22,
                    color: _coral,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: _send,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _bubbleInk,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                  hintText: 'Say or type anything…',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _faint,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: hasText ? () => _send(_input.text) : null,
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: hasText ? 1 : 0.35,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_amber, _coral],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x66E89B14),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _cancelTriggered ? _coral : const Color(0x66FF7F50),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29FF7F50),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cancel recording / Trash
          IconButton(
            onPressed: _cancelRecording,
            tooltip: 'Cancel recording',
            icon: const Icon(Icons.delete_outline_rounded, size: 21),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFFD9562C),
              backgroundColor: const Color(0x1FFF7F50),
              minimumSize: const Size(38, 38),
            ),
          ),
          const SizedBox(width: 8),
          const _RecordingDot(),
          const SizedBox(width: 8),
          Text(
            '0:${_recordingSeconds.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFFC0441C),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: ClipRect(child: _AnimatedAudioWave(amplitude: _currentAmplitude))),
          const SizedBox(width: 8),
          if (!_isLocked) ...[
            Transform.translate(
              offset: Offset(_dragOffset.clamp(-30.0, 30.0), 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _cancelTriggered ? 'Release to cancel' : '‹ Slide left',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _cancelTriggered
                          ? const Color(0xFFD9562C)
                          : const Color(0xFF9E8A72),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _isLocked = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x24FFB534),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: Color(0xFF8A6A1C),
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Lock',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A6A1C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _sendRecording,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_amber, _coral],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x40E89B14),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5238),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5238).withValues(alpha: 0.4 + 0.4 * _ctrl.value),
                blurRadius: 6 + 4 * _ctrl.value,
                spreadRadius: 1 * _ctrl.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnimatedAudioWave extends StatefulWidget {
  final double amplitude;
  const _AnimatedAudioWave({this.amplitude = 0.0});

  @override
  State<_AnimatedAudioWave> createState() => _AnimatedAudioWaveState();
}

class _AnimatedAudioWaveState extends State<_AnimatedAudioWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _waveAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // Each bar is 3px wide + 3px margin (1.5 on each side) = 6px
        final barCount = (availableWidth / 6.0).floor().clamp(4, 16);
        return AnimatedBuilder(
          animation: _waveAnim,
          builder: (_, __) {
            final t = _waveAnim.value * 2 * math.pi;
            final amp = widget.amplitude.clamp(0.0, 1.0);
            return SizedBox(
              height: 38,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(barCount, (i) {
                  // Guaranteed normalized [0.0, 1.0] multiplier
                  final waveMod = 0.5 + 0.5 * math.sin(t + i * 0.55);
                  // Never negative, strictly clamped to fit container without overflow
                  final h = (6.0 + 24.0 * amp * waveMod).clamp(4.0, 32.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    width: 3,
                    height: h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_amber, _coral],
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }
}

class _VoiceBubbleContent extends StatefulWidget {
  const _VoiceBubbleContent({
    required this.duration,
    required this.isUser,
    this.audioPath,
    this.waveform,
  });

  final String duration;
  final bool isUser;
  final String? audioPath;
  final List<double>? waveform;

  @override
  State<_VoiceBubbleContent> createState() => _VoiceBubbleContentState();
}

class _VoiceBubbleContentState extends State<_VoiceBubbleContent> {
  static _VoiceBubbleContentState? _activePlayingState;

  AudioPlayer? _player;
  bool _isPlaying = false;
  double _progress = 0.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Timer? _simulatedTimer;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  @override
  void dispose() {
    if (_activePlayingState == this) {
      _activePlayingState = null;
    }
    _simulatedTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _initPlayerIfNeeded() {
    if (_player != null) return;
    _player = AudioPlayer();
    _posSub = _player!.onPositionChanged.listen((pos) {
      if (!mounted) return;
      final total = _totalDuration.inMilliseconds > 0
          ? _totalDuration.inMilliseconds
          : _parseDurationMs(widget.duration);
      if (total > 0) {
        setState(() {
          _currentPosition = pos;
          _progress = (pos.inMilliseconds / total).clamp(0.0, 1.0);
        });
      }
    });

    _durSub = _player!.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _totalDuration = dur);
    });

    _completeSub = _player!.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _progress = 0.0;
        _currentPosition = Duration.zero;
      });
      if (_activePlayingState == this) {
        _activePlayingState = null;
      }
    });
  }

  static int _parseDurationMs(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final s = int.parse(parts[1]);
        return math.max(1000, (m * 60 + s) * 1000);
      }
    } catch (_) {}
    return 4000;
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _pause();
    } else {
      await _play();
    }
  }

  Future<void> _play() async {
    if (_activePlayingState != null && _activePlayingState != this) {
      await _activePlayingState?._pause();
    }
    _activePlayingState = this;

    final path = widget.audioPath;
    if (path != null && File(path).existsSync()) {
      _initPlayerIfNeeded();
      try {
        await _player!.play(DeviceFileSource(path));
        if (mounted) setState(() => _isPlaying = true);
      } catch (e) {
        debugPrint('[VoiceBubble] AudioPlayer play error: $e');
        _startSimulatedPlayback();
      }
    } else {
      _startSimulatedPlayback();
    }
  }

  Future<void> _pause() async {
    _simulatedTimer?.cancel();
    _simulatedTimer = null;
    if (_player != null) {
      try {
        await _player!.pause();
      } catch (_) {}
    }
    if (_activePlayingState == this) {
      _activePlayingState = null;
    }
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _seekToProgress(double ratio) async {
    final clampedRatio = ratio.clamp(0.0, 1.0);
    final totalMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds
        : _parseDurationMs(widget.duration);
    final targetMs = (totalMs * clampedRatio).round();

    final path = widget.audioPath;
    if (path != null && File(path).existsSync()) {
      _initPlayerIfNeeded();
      try {
        await _player!.seek(Duration(milliseconds: targetMs));
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _progress = clampedRatio;
        _currentPosition = Duration(milliseconds: targetMs);
      });
    }
  }

  void _startSimulatedPlayback() {
    _simulatedTimer?.cancel();
    setState(() {
      _isPlaying = true;
      if (_progress >= 1.0) _progress = 0.0;
    });
    final totalMs = _parseDurationMs(widget.duration);
    const intervalMs = 60;
    _simulatedTimer =
        Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final nextProgress = _progress + (intervalMs / totalMs);
      if (nextProgress >= 1.0) {
        timer.cancel();
        _simulatedTimer = null;
        setState(() {
          _isPlaying = false;
          _progress = 0.0;
        });
        if (_activePlayingState == this) {
          _activePlayingState = null;
        }
      } else {
        setState(() {
          _progress = nextProgress;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.waveform ?? _mockSpeechWaveform;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x29845014),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 19,
              color: const Color(0xFFC07A1E),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            const barWidth = 3.0;
            const spacing = 2.5;
            final totalWidth =
                bars.length * barWidth + (bars.length - 1) * spacing;
            final ratio = (details.localPosition.dx / totalWidth).clamp(0.0, 1.0);
            _seekToProgress(ratio);
          },
          child: SizedBox(
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < bars.length; i++) ...[
                  Container(
                    width: 3,
                    height: (4 + 20 * bars[i]).clamp(4.0, 26.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: (i / bars.length) <= _progress
                          ? const Color(0xFFFF7F50)
                          : (widget.isUser
                              ? const Color(0xFFC99B6A)
                              : const Color(0xFFD6BE98)),
                    ),
                  ),
                  if (i < bars.length - 1) const SizedBox(width: 2.5),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _isPlaying && _currentPosition > Duration.zero
              ? '${_currentPosition.inMinutes}:${(_currentPosition.inSeconds % 60).toString().padLeft(2, '0')}'
              : widget.duration,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: widget.isUser
                ? const Color(0xFF8A5A26)
                : const Color(0xFF8A6A1C),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    this.isSpeaking = false,
    this.onCancelVoice,
    this.onReplayVoice,
    this.onLongPress,
  });

  final _Msg msg;
  final bool isSpeaking;
  final VoidCallback? onCancelVoice;
  final VoidCallback? onReplayVoice;

  /// Long-press on the bubble, with the bubble's place on screen (only given for the person's own messages).
  final void Function(Rect anchor)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    final isVoice = msg.isVoice;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(isUser ? 22 : 6),
      bottomRight: Radius.circular(isUser ? 6 : 22),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (bubbleContext) => GestureDetector(
              key: onLongPress == null ? null : ValueKey('bubble-${msg.id}'),
              behavior: HitTestBehavior.translucent,
              onLongPress: onLongPress == null
                  ? null
                  : () {
                      final box = bubbleContext.findRenderObject() as RenderBox?;
                      if (box == null || !box.attached) return;
                      onLongPress!(box.localToGlobal(Offset.zero) & box.size);
                    },
              child:
Container(
            constraints: const BoxConstraints(maxWidth: 256),
            padding: EdgeInsets.symmetric(
              horizontal: isVoice ? 12 : 15,
              vertical: isVoice ? 10 : 11,
            ),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFFFFE2D4) : const Color(0xFFFFF8E8),
              borderRadius: radius,
              border: isUser
                  ? null
                  : Border.all(color: const Color(0x24FFB534)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x177A5A28),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: isVoice
                ? Column(
                    crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _VoiceBubbleContent(
                        duration: msg.voiceDuration,
                        isUser: isUser,
                        audioPath: msg.localAudioPath,
                        waveform: msg.waveform,
                      ),
                      if (msg.transcription != null &&
                          msg.transcription!.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            msg.transcription!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                              color: isUser
                                  ? const Color(0xFF6E4A22)
                                  : const Color(0xFF5A4A28),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: msg.text),
                        if (msg.isStreaming)
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: _BlinkingCursor(),
                            ),
                          ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _bubbleInk,
                      height: 1.55,
                      letterSpacing: -0.1,
                    ),
                  ),
          ),
            ),
          ),
          if (!isUser && isSpeaking) ...[
            const SizedBox(height: 6),
            _AssistantVoicePill(
              isSpeaking: true,
              onStop: onCancelVoice,
            ),
          ] else if (!isUser && msg.audioPath != null) ...[
            const SizedBox(height: 5),
            _AssistantVoicePill(
              isSpeaking: false,
              onReplay: onReplayVoice,
            ),
          ],
          const SizedBox(height: 3),
          Text(
            msg.time,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB7A98F),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantVoicePill extends StatelessWidget {
  const _AssistantVoicePill({
    required this.isSpeaking,
    this.onStop,
    this.onReplay,
  });

  final bool isSpeaking;
  final VoidCallback? onStop;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    if (isSpeaking) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('stop_voice_pill'),
          onTap: onStop,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2DC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x40FFB534)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F7A5A28),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniEqualizerWave(),
                SizedBox(width: 7),
                Text(
                  'Stop voice',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8B4513),
                    letterSpacing: -0.1,
                  ),
                ),
                SizedBox(width: 5),
                Icon(
                  Icons.stop_circle_rounded,
                  size: 15,
                  color: Color(0xFFFF7F50),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('listen_again_pill'),
        onTap: onReplay,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x0C7A5A28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x187A5A28)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.volume_up_rounded,
                size: 14,
                color: Color(0xFF7A6855),
              ),
              SizedBox(width: 5),
              Text(
                'Listen',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7A6855),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniEqualizerWave extends StatefulWidget {
  const _MiniEqualizerWave();

  @override
  State<_MiniEqualizerWave> createState() => _MiniEqualizerWaveState();
}

class _MiniEqualizerWaveState extends State<_MiniEqualizerWave>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  static bool get _isTestEnvironment =>
      Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (!_isTestEnvironment) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isTestEnvironment || _controller == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _bar(7),
          const SizedBox(width: 2),
          _bar(13),
          const SizedBox(width: 2),
          _bar(9),
          const SizedBox(width: 2),
          _bar(5),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) {
        final t = _controller!.value;
        final h1 = 4.0 + 8.0 * math.sin(t * math.pi);
        final h2 = 5.0 + 9.0 * math.sin((t + 0.3) * math.pi);
        final h3 = 4.0 + 10.0 * math.sin((t + 0.6) * math.pi);
        final h4 = 3.5 + 7.0 * math.sin((t + 0.9) * math.pi);

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(h1),
            const SizedBox(width: 2),
            _bar(h2),
            const SizedBox(width: 2),
            _bar(h3),
            const SizedBox(width: 2),
            _bar(h4),
          ],
        );
      },
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 2.2,
      height: height.clamp(3.5, 14.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFF7F50),
        borderRadius: BorderRadius.circular(1.2),
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2.5,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFFFF7F50),
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    );
  }
}

