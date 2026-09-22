import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../call/call_page.dart';
import '../safety/safety_controller.dart';
import '../sessions/session_controller.dart';
import 'text_check_in_page.dart';

class CheckInModePage extends StatelessWidget {
  const CheckInModePage({
    required this.sessionController,
    required this.safetyController,
    super.key,
  });

  final SessionController sessionController;
  final SafetyController safetyController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRect(
        child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFDF8EC),
              Color(0xFFFBF3E4),
              Color(0xFFFBEFE3),
            ],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: -90,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x56FFB534),
                        Color(0x00FFB534),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -90,
              child: IgnorePointer(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x42FF7F50),
                        Color(0x00FF7F50),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 368),
                child: SafeArea(
                  child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                children: [
                  Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).maybePop(),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                              color: Color(0xFF3A3125),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'How would you like to check in?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3A3125),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 290),
                    child: const Text(
                      'Whatever feels easiest right now is the right one.',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6E6252),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _ModeTile(
                    mode: CaptureMode.text,
                    title: 'Text',
                    description: "Type how you're feeling",
                    icon: Icons.chat_bubble_outline_rounded,
                    onTap: () => _openText(context),
                  ),
                  const SizedBox(height: 16),
                  _ModeTile(
                    mode: CaptureMode.voice,
                    title: 'Voice',
                    description: 'Say it out loud',
                    icon: Icons.mic_none_rounded,
                    onTap: () => _openVoiceCall(context),
                  ),
                  const SizedBox(height: 16),
                  _ModeTile(
                    mode: CaptureMode.video,
                    title: 'Video',
                    description: 'See yourself as you speak',
                    icon: Icons.videocam_outlined,
                    onTap: () => _openVoiceCall(context),
                  ),
                  const SizedBox(height: 26),
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'You can switch anytime',
                            style: TextStyle(
                              color: Color(0xFFA2947F),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xBFFFB534),
                            ),
                          ),
                          const Text(
                            'nothing is saved until you start',
                            style: TextStyle(
                              color: Color(0xFFA2947F),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
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

  void _openText(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TextCheckInPage(
          sessionController: sessionController,
          safetyController: safetyController,
        ),
      ),
    );
  }

  void _openVoiceCall(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallPage(safetyController: safetyController),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final CaptureMode mode;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x42FFB534), width: 1.5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFDFA)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38B28028),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x1CB28028),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0x4DFFB534),
                      width: 1.0,
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0x29FFB534),
                        Color(0x21FF7F50),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFB534),
                        Color(0xFFFF7F50),
                      ],
                    ).createShader(bounds),
                    child: Icon(
                      icon,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3A3125),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFA2947F),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFD8C9B2),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

