import 'package:flutter/material.dart';

import '../../core/models/session_input.dart';
import '../../core/theme/app_theme.dart';
import '../sessions/session_controller.dart';
import 'text_check_in_page.dart';

class CheckInModePage extends StatelessWidget {
  const CheckInModePage({
    required this.sessionController,
    super.key,
  });

  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How would you like to check in?'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          children: [
            Text(
              'Whatever feels easiest right now is the right one.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.mutedInk,
                  ),
            ),
            const SizedBox(height: 28),
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
              onTap: () => _openPlaceholder(context, CaptureMode.voice),
            ),
            const SizedBox(height: 16),
            _ModeTile(
              mode: CaptureMode.video,
              title: 'Video',
              description: 'Camera + voice',
              icon: Icons.videocam_outlined,
              onTap: () => _openPlaceholder(context, CaptureMode.video),
            ),
            const SizedBox(height: 26),
            const Center(
              child: Text(
                'You can switch anytime  ·  nothing is saved until you start',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.mutedInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openText(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TextCheckInPage(sessionController: sessionController),
      ),
    );
  }

  void _openPlaceholder(BuildContext context, CaptureMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CapturePlaceholderPage(mode: mode),
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
    final accent = mode == CaptureMode.voice ? AppColors.coral : AppColors.amber;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.amber.withValues(alpha: 0.18),
                      AppColors.coral.withValues(alpha: 0.14),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Icon(icon, size: 28, color: accent),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(description, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.mutedInk),
            ],
          ),
        ),
      ),
    );
  }
}

class CapturePlaceholderPage extends StatelessWidget {
  const CapturePlaceholderPage({
    required this.mode,
    super.key,
  });

  final CaptureMode mode;

  @override
  Widget build(BuildContext context) {
    final isVoice = mode == CaptureMode.voice;
    final label = isVoice ? 'Voice capture is next' : 'Video capture is next';
    final icon = isVoice ? Icons.mic_none_rounded : Icons.videocam_outlined;

    return Scaffold(
      appBar: AppBar(title: Text(isVoice ? 'Voice check-in' : 'Video check-in')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.coral.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Icon(icon, size: 42, color: AppColors.coral),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(label, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 10),
                    const Text(
                      'The capture interface is reserved here. When enabled, permission will be requested only when you choose this mode.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Choose another way'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
