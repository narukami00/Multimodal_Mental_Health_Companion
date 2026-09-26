import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/safety_assessment.dart';
import '../../services/companion_websocket_service.dart';
import '../../services/pcm_audio_recorder_service.dart';
import '../call/call_page.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import 'conversation_history.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.safetyController,
    this.webSocketService,
    this.audioRecorderService,
    this.autoConnect = false,
    super.key,
  });

  final SafetyController safetyController;
  final CompanionWebSocketService? webSocketService;
  final PcmAudioRecorderService? audioRecorderService;
  final bool autoConnect;

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
    this.isVoice = false,
    this.voiceDuration = '0:00',
    this.isStreaming = false,
    this.localAudioPath,
    this.waveform,
  });

  final bool isUser;
  final String text;
  final String time;
  final bool isVoice;
  final String voiceDuration;
  final bool isStreaming;
  final String? localAudioPath;
  final List<double>? waveform;
}


const _ink = Color(0xFF3A3125);
const _bubbleInk = Color(0xFF46382A);
const _softInk = Color(0xFF6E6252);
const _faint = Color(0xFFB7A98F);
const _amber = Color(0xFFFFB534);
const _coral = Color(0xFFFF7F50);
const _surface = Color(0xFFFFFDF4);

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  static const _greeting =
      "Hello. Take your time here. Whatever you're holding today, "
      "you don't have to carry it all by yourself. What feels present right now?";

  static const _chips = [
    "I'm feeling a bit restless",
    'Help me unwind tonight',
    'Just want to vent',
    'Notice where I am',
  ];

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
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  var _isRecording = false;
  var _isLocked = false;
  var _recordingSeconds = 0;
  Timer? _recordingTimer;
  var _dragOffset = 0.0;
  var _cancelTriggered = false;

  late final CompanionWebSocketService _wsService;
  StreamSubscription<CompanionConnectionStatus>? _wsStatusSub;
  StreamSubscription<int>? _wsLatencySub;
  StreamSubscription<Map<String, dynamic>>? _wsChunkSub;
  StreamSubscription<Map<String, dynamic>>? _wsDoneSub;

  late final PcmAudioRecorderService _audioRecorder;
  StreamSubscription<Uint8List>? _audioFrameSub;
  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<Map<String, dynamic>>? _wsAudioReceivedSub;
  StreamSubscription<Map<String, dynamic>>? _wsTranscriptFinalSub;

  final List<Uint8List> _recordedAudioChunks = [];
  double _currentAmplitude = 0.0;
  String? _activeAudioTurnId;
  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;

  CompanionConnectionStatus _wsStatus = CompanionConnectionStatus.disconnected;
  int? _lastLatencyMs;
  void Function(void Function())? _modalSetState;

  @override
  void initState() {
    super.initState();
    _wsService = widget.webSocketService ?? CompanionWebSocketService();
    _audioRecorder = widget.audioRecorderService ?? PcmAudioRecorderService();
    _wsStatus = _wsService.status;
    _lastLatencyMs = _wsService.lastLatencyMs;

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
      if (!mounted) return;
      final text = data['text'] as String? ?? '';
      debugPrint('[ChatPage] Server transcript: $text');
    });

    _wsStatusSub = _wsService.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _wsStatus = status);
      _modalSetState?.call(() {});
    });

    _wsLatencySub = _wsService.latencyStream.listen((latency) {
      if (!mounted) return;
      setState(() => _lastLatencyMs = latency);
      _modalSetState?.call(() {});
    });

    _wsChunkSub = _wsService.llmChunkStream.listen((data) {
      if (!mounted) return;
      final delta = data['delta'] as String? ?? '';
      setState(() {
        if (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.isStreaming) {
          final old = _messages.last;
          _messages[_messages.length - 1] = _Msg(
            false,
            old.text + delta,
            old.time,
            isStreaming: true,
          );
        } else {
          _messages.add(_Msg(false, delta, _now(), isStreaming: true));
        }
      });
      _scrollDown();
    });

    _wsDoneSub = _wsService.llmDoneStream.listen((data) {
      if (!mounted) return;
      final finalText = data['text'] as String? ?? '';
      setState(() {
        if (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.isStreaming) {
          _messages[_messages.length - 1] = _Msg(
            false,
            finalText.isNotEmpty ? finalText : _messages.last.text,
            _now(),
            isStreaming: false,
          );
        } else {
          _messages.add(_Msg(false, finalText, _now(), isStreaming: false));
        }
      });
      _scrollDown();
    });

    _messages = [
      _Msg(false, _greeting, _now()),
      const _Msg(
        true,
        'Audio reflection',
        '8:12 PM',
        isVoice: true,
        voiceDuration: '0:14',
        waveform: _mockSpeechWaveform,
      ),
      const _Msg(
        false,
        "Thank you for sharing that with me. Take a gentle breath — what feels easiest to focus on right now?",
        '8:13 PM',
      ),
    ];
    _input.addListener(() => setState(() {}));

    _loadSavedServerConfig();

    if (widget.autoConnect &&
        _wsStatus == CompanionConnectionStatus.disconnected) {
      _wsService.connect();
    }
  }

  void _loadSavedServerConfig() {
    SharedPreferences.getInstance().then((prefs) {
      final savedHost = prefs.getString('companion_server_host');
      final savedPort = prefs.getInt('companion_server_port');
      if (savedHost != null && savedHost.isNotEmpty) {
        _wsService.host = savedHost;
      } else {
        _wsService.host = '192.168.0.38';
      }
      if (savedPort != null && savedPort > 0) {
        _wsService.port = savedPort;
      }
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioFrameSub?.cancel();
    _amplitudeSub?.cancel();
    _wsAudioReceivedSub?.cancel();
    _wsTranscriptFinalSub?.cancel();
    if (widget.audioRecorderService == null) {
      _audioRecorder.dispose();
    }
    _wsStatusSub?.cancel();
    _wsLatencySub?.cancel();
    _wsChunkSub?.cancel();
    _wsDoneSub?.cancel();
    if (widget.webSocketService == null) {
      _wsService.dispose();
    }
    _breath.dispose();
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

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isRecording || _isLocked) return;
    setState(() {
      _dragOffset += details.primaryDelta ?? 0.0;
      _cancelTriggered = _dragOffset < -60;
      if (_dragOffset > 70) {
        _isLocked = true;
        _dragOffset = 0.0;
      }
    });
  }

  void _handleDragEnd() {
    if (!_isRecording || _isLocked) return;
    if (_cancelTriggered || _dragOffset < -50) {
      _cancelRecording();
    } else {
      _sendRecording();
    }
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

    if (turnId != null && _wsStatus == CompanionConnectionStatus.connected) {
      _wsService.sendAudioEnd(
        turnId: turnId,
        durationMs: durMs,
      );
    }

    if (!mounted) return;
    setState(() {
      _messages.add(
        _Msg(
          true,
          'Audio reflection',
          _now(),
          isVoice: true,
          voiceDuration: durStr,
          localAudioPath: localAudioPath,
          waveform: waveform,
        ),
      );
      _isRecording = false;
      _isLocked = false;
      _dragOffset = 0.0;
      _cancelTriggered = false;
      _currentAmplitude = 0.0;
    });
    _scrollDown();

    if (_wsStatus != CompanionConnectionStatus.connected) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        setState(() {
          _messages.add(
            _Msg(
              false,
              _replies[_replyIndex % _replies.length],
              _now(),
            ),
          );
          _replyIndex++;
        });
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
    setState(() => _messages.add(_Msg(true, text, _now())));
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
            assessment: assessment,
            regionCode: Localizations.localeOf(context).countryCode ??
                'GLOBAL',
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

    setState(() {
      _messages.add(
        _Msg(false, _replies[_replyIndex % _replies.length], _now()),
      );
      _replyIndex++;
    });
    _scrollDown();
  }

  Future<void> _openSupport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportResourcesPage(
          safetyController: widget.safetyController,
          assessment: const SafetyAssessment.clear(),
          regionCode: Localizations.localeOf(context).countryCode ?? 'GLOBAL',
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
                        _buildConnectionBanner(),
                        Expanded(
                          child: ListView.builder(
                            controller: _scroll,
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) =>
                                _Bubble(msg: _messages[i]),
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
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            style: IconButton.styleFrom(
              foregroundColor: _ink,
              minimumSize: const Size(44, 44),
              backgroundColor: const Color(0xFFFFFDF6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SolMiniAvatar(controller: _breath),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sol',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Always here · Non-clinical companion',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _softInk,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              ConversationHistorySheet.show(
                context,
                onSelectThread: (thread) {
                  // Switch or reload thread
                },
                onNewConversation: () {
                  setState(() {
                    _messages = [
                      _Msg(false, _greeting, _now()),
                    ];
                  });
                },
              );
            },
            tooltip: 'Past conversations',
            icon: const Icon(Icons.history_rounded, size: 22),
            style: IconButton.styleFrom(
              foregroundColor: _ink,
              minimumSize: const Size(40, 44),
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CallPage(safetyController: widget.safetyController),
                ),
              );
            },
            tooltip: 'Call Sol',
            icon: const Icon(Icons.phone_in_talk_rounded, size: 21),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFFC08A1E),
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
            onPressed: _openSupport,
            tooltip: 'Support resources',
            icon: const Icon(Icons.health_and_safety_outlined, size: 22),
            style: IconButton.styleFrom(
              foregroundColor: _coral,
              minimumSize: const Size(40, 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner() {
    final isConnected = _wsStatus == CompanionConnectionStatus.connected;
    final isConnecting = _wsStatus == CompanionConnectionStatus.connecting;
    final isError = _wsStatus == CompanionConnectionStatus.error;

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String title;
    String subtitle;
    Widget trailingAction;

    if (isConnected) {
      bgColor = const Color(0xFFEBFDF2);
      borderColor = const Color(0xFF6EE7B7);
      textColor = const Color(0xFF065F46);
      icon = Icons.sensors_rounded;
      final rtt = _lastLatencyMs != null ? '${_lastLatencyMs}ms RTT' : 'Ready';
      title = 'Companion Server Online';
      subtitle = '${_wsService.host}:${_wsService.port} · $rtt';
      trailingAction = const Icon(
        Icons.tune_rounded,
        size: 16,
        color: Color(0xFF059669),
      );
    } else if (isConnecting) {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFCD34D);
      textColor = const Color(0xFF92400E);
      icon = Icons.sync_rounded;
      title = 'Connecting to Server...';
      subtitle = 'Attempting ${_wsService.host}:${_wsService.port}';
      trailingAction = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Color(0xFFD97706)),
        ),
      );
    } else if (isError) {
      bgColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFCA5A5);
      textColor = const Color(0xFF991B1B);
      icon = Icons.error_outline_rounded;
      title = 'Connection Unreachable';
      subtitle = _wsService.lastErrorMessage ??
          'No route to host. If connected via USB, select 127.0.0.1';
      trailingAction = InkWell(
        onTap: () {
          _wsService.connect();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Retry',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else {
      bgColor = const Color(0xFFFFF7ED);
      borderColor = const Color(0xFFFFD5A5);
      textColor = const Color(0xFF9A3412);
      icon = Icons.wifi_find_rounded;
      title = 'Companion Server (PC): Offline';
      subtitle = 'Tap to connect to ${_wsService.host}:${_wsService.port}';
      trailingAction = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _coral,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Connect',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showConnectionSettingsDialog,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: textColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: textColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailingAction,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showConnectionSettingsDialog() {
    final hostCtrl = TextEditingController(text: _wsService.host);
    final portCtrl = TextEditingController(text: _wsService.port.toString());

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFDF8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            _modalSetState = setModalState;
            final isConnected =
                _wsStatus == CompanionConnectionStatus.connected;
            final isConnecting =
                _wsStatus == CompanionConnectionStatus.connecting;
            final isError =
                _wsStatus == CompanionConnectionStatus.error;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDD2BE),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.hub_outlined, color: _coral, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Companion Backend Settings',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Connect to the Python Solace companion engine for live WebSocket communication & STT/LLM streaming.',
                    style:
                        TextStyle(fontSize: 12, color: _softInk, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: hostCtrl,
                          decoration: InputDecoration(
                            labelText: 'Host / IP',
                            hintText: '127.0.0.1',
                            filled: true,
                            fillColor: const Color(0xFFF9F5EC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: portCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Port',
                            hintText: '8000',
                            filled: true,
                            fillColor: const Color(0xFFF9F5EC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Quick Presets:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _softInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.computer_rounded, size: 14, color: _coral),
                        label: const Text('Localhost (USB): 127.0.0.1'),
                        backgroundColor: const Color(0xFFFFF2E6),
                        side: const BorderSide(color: Color(0xFFFFCC99)),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                        onPressed: () {
                          hostCtrl.text = '127.0.0.1';
                          portCtrl.text = '8000';
                          setModalState(() {});
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.wifi_rounded, size: 14, color: _softInk),
                        label: const Text('Wi-Fi PC: 192.168.0.38'),
                        backgroundColor: const Color(0xFFF7F2E7),
                        side: const BorderSide(color: Color(0xFFDDD2BE)),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                        onPressed: () {
                          hostCtrl.text = '192.168.0.38';
                          portCtrl.text = '8000';
                          setModalState(() {});
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.devices_rounded, size: 14, color: _softInk),
                        label: const Text('Emulator: 10.0.2.2'),
                        backgroundColor: const Color(0xFFF7F2E7),
                        side: const BorderSide(color: Color(0xFFDDD2BE)),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                        onPressed: () {
                          hostCtrl.text = '10.0.2.2';
                          portCtrl.text = '8000';
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isError
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFF7F2E7),
                      borderRadius: BorderRadius.circular(12),
                      border: isError
                          ? Border.all(color: const Color(0xFFFCA5A5))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isConnected
                              ? Icons.check_circle_rounded
                              : isConnecting
                                  ? Icons.hourglass_top_rounded
                                  : (isError
                                      ? Icons.error_outline_rounded
                                      : Icons.radio_button_unchecked_rounded),
                          size: 18,
                          color: isConnected
                              ? const Color(0xFF38A169)
                              : isConnecting
                                  ? const Color(0xFFD69E2E)
                                  : (isError
                                      ? const Color(0xFFDC2626)
                                      : _faint),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isConnected
                                ? 'Connected · Latency: ${_lastLatencyMs ?? 0}ms'
                                : isConnecting
                                    ? 'Connecting to ${hostCtrl.text}...'
                                    : (isError
                                        ? (_wsService.lastErrorMessage ??
                                            'Connection unreachable')
                                        : 'Disconnected'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isError ? const Color(0xFFDC2626) : _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (isConnected) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _wsService.sendPing();
                              setModalState(() {});
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ink,
                              side: const BorderSide(color: Color(0xFFDDD2BE)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Test Ping'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await _wsService.disconnect();
                              setModalState(() {});
                              setState(() {});
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE2E8F0),
                              foregroundColor: _ink,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Disconnect'),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isConnecting
                                ? null
                                : () async {
                                    final host = hostCtrl.text.trim();
                                    final port =
                                        int.tryParse(portCtrl.text.trim()) ?? 8000;
                                    final effectiveHost =
                                        host.isNotEmpty ? host : '127.0.0.1';
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setString(
                                      'companion_server_host',
                                      effectiveHost,
                                    );
                                    await prefs.setInt(
                                      'companion_server_port',
                                      port,
                                    );
                                    _wsService.connect(
                                      customHost: effectiveHost,
                                      customPort: port,
                                    );
                                    setModalState(() {});
                                    setState(() {});
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _coral,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isConnecting
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation(Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Connecting...'),
                                    ],
                                  )
                                : Text(isError ? 'Retry Connection' : 'Connect Now'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _modalSetState = null;
    });
  }

  Widget _buildChips() {
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
                  hintText: 'Speak or type what\u2019s here…',
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
          Expanded(child: _AnimatedAudioWave(amplitude: _currentAmplitude)),
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

class _SolMiniAvatar extends StatelessWidget {
  const _SolMiniAvatar({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Ambient warm aura glow
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _amber.withValues(alpha: 0.35 + 0.15 * t),
                    blurRadius: 10 + 4 * t,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            // Luminous golden sun-drop orb with gentle organic morph
            Transform.scale(
              scale: 1.0 + 0.04 * t,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const RadialGradient(
                    center: Alignment(-0.35, -0.4),
                    radius: 0.95,
                    colors: [
                      Color(0xFFFFE8B5),
                      Color(0xFFFFB534),
                      Color(0xFFFF7F50),
                    ],
                    stops: [0.0, 0.52, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                ),
                child: Stack(
                  children: [
                    // Specular highlight at top-left
                    Positioned(
                      top: 4,
                      left: 6,
                      child: Container(
                        width: 14,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.85),
                              Colors.white.withValues(alpha: 0.1),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Subtle presence dot at bottom-right
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF48BB78),
                  border: Border.all(
                    color: const Color(0xFFFEFCE8),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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
    const barCount = 14;
    return AnimatedBuilder(
      animation: _waveAnim,
      builder: (_, __) {
        final t = _waveAnim.value * 2 * math.pi;
        final amp = widget.amplitude.clamp(0.0, 1.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final waveMod = 0.4 + 0.6 * math.sin(t + i * 0.55);
            final h = 5.0 + (10.0 + 20.0 * amp) * waveMod;
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
          widget.duration,
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
  const _Bubble({required this.msg});

  final _Msg msg;

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
                ? _VoiceBubbleContent(
                    duration: msg.voiceDuration,
                    isUser: isUser,
                    audioPath: msg.localAudioPath,
                    waveform: msg.waveform,
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

