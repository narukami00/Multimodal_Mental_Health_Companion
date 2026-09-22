import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({required this.safetyController, super.key});

  final SafetyController safetyController;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _Msg {
  const _Msg(this.isUser, this.text, this.time);

  final bool isUser;
  final String text;
  final String time;
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

  @override
  void initState() {
    super.initState();
    // Seed with a short example conversation so the screen feels alive.
    _messages = [
      const _Msg(false, _greeting, '10:09 AM'),
      const _Msg(
        true,
        "I've been feeling really scattered today. Hard to focus on anything.",
        '10:11 AM',
      ),
      const _Msg(
        false,
        "Scattered is a real feeling — not a flaw. Sometimes that pull in many directions is your mind trying to process a lot at once. What feels like the heaviest thing right now?",
        '10:11 AM',
      ),
      const _Msg(
        true,
        "Probably work. A big deadline tomorrow and I haven't slept well.",
        '10:12 AM',
      ),
      const _Msg(
        false,
        "That makes complete sense. Poor sleep and a looming deadline is a hard combination. Your body knows. Before we talk about the deadline — how is your body feeling right now, sitting here?",
        '10:12 AM',
      ),
    ];
    _replyIndex = 0;
    _input.addListener(() => setState(() {}));
    // Scroll to the most recent message on first render.
    unawaited(_scrollDown());
  }

  @override
  void dispose() {
    _breath.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _now() {
    final d = DateTime.now();
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _scrollDown() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!_scroll.hasClients) return;
    final maxExtent = _scroll.position.maxScrollExtent;
    if (maxExtent <= _scroll.position.pixels) return;
    await _scroll.animateTo(
      maxExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() => _messages.add(_Msg(true, text, _now())));
    unawaited(_scrollDown());

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
            regionCode: Localizations.localeOf(context).countryCode ?? 'GLOBAL',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _messages.add(
        _Msg(false, _replies[_replyIndex % _replies.length], _now()),
      );
      _replyIndex++;
    });
    await _scrollDown();
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
                        Expanded(
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) => _Bubble(msg: _messages[i]),
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
        border: Border(bottom: BorderSide(color: Color(0x24B4965A))),
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
          _BreathingOrb(controller: _breath),
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
            onPressed: _openSupport,
            tooltip: 'Support resources',
            icon: const Icon(Icons.health_and_safety_outlined, size: 23),
            style: IconButton.styleFrom(
              foregroundColor: _coral,
              minimumSize: const Size(44, 44),
            ),
          ),
        ],
      ),
    );
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
      child: DecoratedBox(
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
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Voice mode is coming soon.'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                tooltip: 'Switch to voice',
                icon: const Icon(Icons.mic_none_rounded, size: 22),
                style: IconButton.styleFrom(
                  foregroundColor: _softInk,
                  minimumSize: const Size(44, 44),
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
      ),
    );
  }
}

class _BreathingOrb extends StatelessWidget {
  const _BreathingOrb({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        return Transform.scale(
          scale: 1 + 0.055 * t,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const RadialGradient(
                center: Alignment(-0.5, -0.6),
                colors: [
                  Color(0xFFFFE3A6),
                  Color(0xFFFFB534),
                  Color(0xFFFF7F50),
                ],
                stops: [0, 0.5, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: _coral.withValues(alpha: 0.32),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Align(
              alignment: Alignment(0.75, 0.75),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6FCF97),
                    boxShadow: [
                      BoxShadow(color: Color(0x666FCF97), blurRadius: 4),
                    ],
                  ),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});

  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(isUser ? 22 : 6),
      bottomRight: Radius.circular(isUser ? 6 : 22),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 246),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
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
            child: Text(
              msg.text,
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
              color: _faint,
            ),
          ),
        ],
      ),
    );
  }
}
