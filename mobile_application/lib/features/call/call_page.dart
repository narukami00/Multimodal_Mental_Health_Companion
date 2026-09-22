import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';

class CallPage extends StatefulWidget {
  const CallPage({required this.safetyController, super.key});

  final SafetyController safetyController;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CaptionLine {
  _CaptionLine({required this.aria, required this.words});

  final bool aria;
  final List<String> words;
  int shown = 0;
}

class _CallPageState extends State<CallPage> with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF4A3B2A);
  static const _softInk = Color(0xFF6E5D49);
  static const _timerInk = Color(0xFF8E7E6A);
  static const _amber = Color(0xFFFFB534);
  static const _coral = Color(0xFFFF7F50);
  static const _line = Color(0x1F7A5D3A);

  // ponytail: fixed script loop instead of real audio pipeline; swap for live STT/TTS when available
  static const _script = <(bool, String)>[
    (true, "Hi, it's Aria. I'm really glad you came back today."),
    (false, "Hey… honestly, it's been a heavy week."),
    (true, 'That sounds like a lot to carry. Where would feel easiest to begin?'),
    (false, "I keep feeling like I'm behind on everything."),
    (true, "Behind is such an exhausting place to sit. Let's slow it down for a moment — just you and me."),
    (false, 'Okay. That already helps a little.'),
    (true, "It does, doesn't it? One breath at a time. I'm not going anywhere."),
    (false, 'Can we just stay here for a bit?'),
    (true, "Of course. However long you need — I'll keep the light on."),
  ];

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6400),
  )..repeat();

  Timer? _ticker;
  Completer<void>? _delay;
  var _seconds = 0;
  var _lineIndex = 0;
  var _generation = 0;
  var _muted = false;
  var _camera = false;
  var _speaker = true;
  var _paused = false;
  var _ended = false;
  final _lines = <_CaptionLine>[];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ended || _paused || !mounted) return;
      setState(() => _seconds++);
    });
    final token = ++_generation;
    _runConversation(token);
  }

  @override
  void dispose() {
    _generation++;
    _releaseDelay();
    _ticker?.cancel();
    _breath.dispose();
    super.dispose();
  }

  void _releaseDelay() {
    final delay = _delay;
    if (delay != null && !delay.isCompleted) delay.complete();
  }

  static String _fmt(int total) {
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _wait(int ms, int token) async {
    final completer = Completer<void>();
    _delay = completer;
    final timer = Timer(Duration(milliseconds: ms), completer.complete);
    await completer.future;
    timer.cancel();
    if (_delay == completer) _delay = null;
    if (!mounted || token != _generation) throw const _Stale();
  }

  Future<void> _runConversation(int token) async {
    try {
      while (mounted && token == _generation && !_ended) {
        if (_paused) {
          await _wait(220, token);
          continue;
        }

        final (aria, text) = _script[_lineIndex % _script.length];
        if (!aria && _muted) {
          _lineIndex++;
          await _wait(1100, token);
          continue;
        }

        final words = text.split(' ');
        setState(() {
          if (_lines.length >= 2) _lines.removeAt(0);
          _lines.add(_CaptionLine(aria: aria, words: words));
        });

        for (var i = 0; i < words.length; i++) {
          while (_paused && token == _generation && !_ended) {
            await _wait(200, token);
          }
          if (token != _generation || _ended) return;

          var beat = aria ? 96 : 82;
          if (words[i].length > 7) beat += 34;
          if (RegExp(r'[,.;:—?!]$').hasMatch(words[i])) beat += 210;
          await _wait(beat, token);
          if (!mounted) return;
          setState(() => _lines.last.shown = i + 1);
        }

        _lineIndex++;
        await _wait(aria ? 1500 : 1150, token);
        await _wait(500, token);
      }
    } on _Stale {
      // conversation superseded or widget disposed
    }
  }

  void _toggleMic() {
    if (_ended) return;
    setState(() => _muted = !_muted);
  }

  void _toggleCamera() {
    if (_ended) return;
    setState(() => _camera = !_camera);
  }

  void _toggleSpeaker() {
    setState(() => _speaker = !_speaker);
  }

  void _endSession() {
    if (_ended) return;
    setState(() {
      _ended = true;
      _paused = false;
      _generation++;
    });
    _releaseDelay();
  }

  void _restart() {
    setState(() {
      _ended = false;
      _seconds = 0;
      _lineIndex = 0;
      _lines.clear();
      _generation++;
    });
    _releaseDelay();
    _runConversation(_generation);
  }

  Future<void> _confirmLeave() async {
    if (_ended) return;
    setState(() => _paused = true);
    final leave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _LeaveSheet(
        onStay: () => Navigator.of(sheetContext).pop(false),
        onLeave: () => Navigator.of(sheetContext).pop(true),
      ),
    );
    if (!mounted) return;
    setState(() => _paused = false);
    if (leave == true) _endSession();
  }

  Future<void> _openSupport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportResourcesPage(
          safetyController: widget.safetyController,
          regionCode: Localizations.localeOf(context).countryCode ?? 'GLOBAL',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E241A),
      body: ClipRect(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 392),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.45,
                        stops: [0, 0.42, 0.72, 1],
                        colors: [
                          Color(0xFFFFF7DE),
                          Color(0xFFFEFCE8),
                          Color(0xFFFDF6E4),
                          Color(0xFFFBF1DC),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: -40,
                  left: -60,
                  child: _Pool(color: Color(0x38FFB534), size: 300),
                ),
                const Positioned(
                  bottom: 80,
                  right: -70,
                  child: _Pool(color: Color(0x29FF7F50), size: 280),
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: _buildStage()),
                        _buildCaptions(),
                        _buildModeChip(),
                        _buildDock(),
                        const SizedBox(height: 4),
                        Container(
                          width: 120,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: _ink.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                if (_ended)
                  Positioned.fill(
                    child: _EndOverlay(
                      seconds: _seconds,
                      camera: _camera,
                      onRestart: _restart,
                      onHome: () => Navigator.of(context).maybePop(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          _GlassButton(
            size: 40,
            radius: 14,
            onTap: _confirmLeave,
            tooltip: 'Minimize',
            child: const Icon(Icons.chevron_left_rounded, size: 22, color: _ink),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Voice reflection',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: 0.1,
              ),
            ),
          ),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
            ),
            child: Text(
              _fmt(_seconds),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _timerInk,
                letterSpacing: 0.4,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _GlassButton(
            size: 40,
            radius: 14,
            onTap: _openSupport,
            tooltip: 'Support resources',
            child: const Icon(Icons.health_and_safety_outlined, size: 21, color: _coral),
          ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    return Stack(
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BreathingOrb(controller: _breath, muted: _muted),
                const SizedBox(height: 26),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Take your time. Silence is welcome here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _softInk,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 16,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            opacity: _camera ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_camera,
              child: const _SelfView(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptions() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 104),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 0, 30, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _coral.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE TRANSCRIPT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: _ink.withValues(alpha: 0.30),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _lines.length; i++)
              _CaptionText(line: _lines[i], past: i < _lines.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: _camera
              ? _amber.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 13,
              color: _camera ? const Color(0xC7966014) : _ink.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                _camera ? 'CAMERA ON · YOU ARE VISIBLE' : 'VOICE ONLY · CAMERA OFF',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _camera ? const Color(0xC7966014) : _ink.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2ED68A20),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Ctrl(
              label: _muted ? 'Muted' : 'Mic on',
              active: !_muted,
              onTap: _toggleMic,
              icon: Icons.mic_none_rounded,
              slashed: _muted,
            ),
            _Ctrl(
              label: _speaker ? 'Speaker' : 'Earpiece',
              active: _speaker,
              onTap: _toggleSpeaker,
              icon: _speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
              slashed: !_speaker,
            ),
            _Ctrl(
              label: _camera ? 'Cam on' : 'Cam off',
              active: _camera,
              onTap: _toggleCamera,
              icon: Icons.videocam_outlined,
              slashed: !_camera,
            ),
            _EndCtrl(onTap: _endSession),
          ],
        ),
      ),
    );
  }
}

class _Stale implements Exception {
  const _Stale();
}

class _Pool extends StatelessWidget {
  const _Pool({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.size,
    required this.radius,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final double size;
  final double radius;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x38A06E28),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          ),
          child: child,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _BreathingOrb extends StatelessWidget {
  const _BreathingOrb({required this.controller, required this.muted});

  final AnimationController controller;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    const size = 180.0;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        final breath = 1 + 0.055 * math.sin(math.pi * t);
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -47,
                right: -47,
                top: -47,
                bottom: -47,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _CallPageState._amber.withValues(alpha: muted ? 0.22 : 0.42),
                        _CallPageState._coral.withValues(alpha: muted ? 0.10 : 0.20),
                        _CallPageState._coral.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.38, 0.7],
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < 3; i++) _Ring(controller: controller, index: i),
              Transform.scale(
                scale: breath,
                child: Container(
                  width: size * 0.74,
                  height: size * 0.74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-0.25, -0.3),
                      colors: [
                        Color(0xFFFFE3A6),
                        Color(0xFFFFB534),
                        Color(0xFFFF9A5C),
                        Color(0xFFFF7F50),
                      ],
                      stops: [0, 0.4, 0.72, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE2963C).withValues(alpha: 0.34),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.2, -0.3),
                        colors: [
                          Colors.white.withValues(alpha: 0.9),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.6],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.controller, required this.index});

  final AnimationController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    const base = 158.0;
    final start = index / 3;
    final curved = Interval(start, math.min(start + 0.55, 1.0), curve: Curves.easeOut)
        .transform(controller.value);
    final scale = 0.82 + 0.44 * curved;
    final opacity = (math.sin(math.pi * curved) * 0.4).clamp(0.0, 1.0).toDouble();
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: base,
          height: base,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Color.lerp(
                const Color(0x52FFB534),
                const Color(0x42FF7F50),
                controller.value,
              )!,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionText extends StatelessWidget {
  const _CaptionText({required this.line, required this.past});

  final _CaptionLine line;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final revealed = line.words.take(line.shown).join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: past ? 0.34 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.aria ? 'ARIA' : 'YOU',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.9,
                color: line.aria
                    ? const Color(0x9ED66E34)
                    : _CallPageState._ink.withValues(alpha: 0.34),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              revealed,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: past ? FontWeight.w400 : FontWeight.w600,
                height: 1.5,
                color: _CallPageState._ink.withValues(alpha: 0.74),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelfView extends StatelessWidget {
  const _SelfView();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      height: 116,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE0B2), Color(0xFFFFC79B), Color(0xFFFFB08A)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99965A28),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.9), blurRadius: 8),
                ],
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                'YOU',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: Color(0xBF5A3A1E),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ctrl extends StatelessWidget {
  const _Ctrl({
    required this.label,
    required this.active,
    required this.onTap,
    required this.icon,
    required this.slashed,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  final bool slashed;

  @override
  Widget build(BuildContext context) {
    final fg = active ? _CallPageState._ink : const Color(0xFF8A5A1E);
    return Column(
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0xFFFFFBEA)],
                      )
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFE9C4), Color(0xFFFFD79A)],
                      ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xB3A06E28),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 23, color: fg),
                  Opacity(
                    opacity: slashed ? 1 : 0,
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: Container(
                        width: 2.2,
                        height: 26,
                        decoration: BoxDecoration(
                          color: fg,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: active
                ? _CallPageState._ink.withValues(alpha: 0.42)
                : const Color(0xB8966014),
          ),
        ),
      ],
    );
  }
}

class _EndCtrl extends StatelessWidget {
  const _EndCtrl({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _CallPageState._coral.withValues(alpha: 0.28)),
                  ),
                ),
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF7F50), Color(0xFFF06030)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xBF9C3A18),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_end_rounded, size: 26, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'END',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: const Color(0xFFD9562C).withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

class _LeaveSheet extends StatelessWidget {
  const _LeaveSheet({required this.onStay, required this.onLeave});

  final VoidCallback onStay;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF2), Color(0xFFFDF7E6)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: _CallPageState._ink.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Leave this session?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xF04A3B2A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'You can end now or keep talking. Your reflections stay saved either way.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              fontWeight: FontWeight.w600,
              color: Color(0x9E4A3B2A),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onStay,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC861), Color(0xFFFFB534)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xE6D69632),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Keep talking',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5A3B10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onLeave,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _CallPageState._coral.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _CallPageState._coral.withValues(alpha: 0.28)),
                  ),
                  child: const Text(
                    'End session',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD9562C),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndOverlay extends StatelessWidget {
  const _EndOverlay({
    required this.seconds,
    required this.camera,
    required this.onRestart,
    required this.onHome,
  });

  final int seconds;
  final bool camera;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  String get _meta {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return 'Session $m:$s · ${camera ? 'Voice + camera' : 'Voice only'}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0FEFCE8), Color(0xF7FFF4E2)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(46),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD07A), Color(0xFFFF9E5C)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xB38C8C3C),
                      blurRadius: 40,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(46),
                    gradient: RadialGradient(
                      center: const Alignment(-0.25, -0.35),
                      colors: [Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0)],
                      stops: const [0, 0.68],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Take good care',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xF24A3B2A),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "You showed up for yourself today — that matters. I'll be right here whenever you want to talk again.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  fontWeight: FontWeight.w600,
                  color: Color(0x9E4A3B2A),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _CallPageState._line),
                ),
                child: Text(
                  _meta.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: _CallPageState._ink.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onRestart,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC861), Color(0xFFFFB534)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xF2D69632),
                            blurRadius: 30,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Start a new session',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5A3B10),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onHome,
                child: const Text(
                  'Return home',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0x804A3B2A),
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0x404A3B2A),
                    decorationThickness: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
