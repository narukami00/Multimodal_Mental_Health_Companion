import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/contracts/onboarding_repository.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    required this.repository,
    required this.onComplete,
    super.key,
  });

  final OnboardingRepository repository;
  final VoidCallback onComplete;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _pageCount = 4;

  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.repository.currentPage.clamp(0, _pageCount - 1).toInt();
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_currentPage == _pageCount - 1) {
      await widget.repository.complete();
      if (mounted) widget.onComplete();
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _chooseMedia(bool enabled) async {
    await widget.repository.setMediaPreference(enabled: enabled);
    if (mounted) await _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              currentPage: _currentPage,
              onSkip: _currentPage == _pageCount - 1 ? null : _next,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                  unawaited(widget.repository.setCurrentPage(page));
                },
                children: const [
                  _WelcomePage(),
                  _WaysToCheckInPage(),
                  _PermissionPage(),
                  _SupportPage(),
                ],
              ),
            ),
            _BottomControls(
              currentPage: _currentPage,
              onNext: _next,
              onChooseMedia: _chooseMedia,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.currentPage,
    required this.onSkip,
  });

  final int currentPage;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Row(
        children: [
          const _SolaceMark(size: 38),
          const SizedBox(width: 10),
          Text(
            'SOLACE',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const Spacer(),
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              child: const Text('Skip'),
            ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.currentPage,
    required this.onNext,
    required this.onChooseMedia,
  });

  final int currentPage;
  final VoidCallback onNext;
  final ValueChanged<bool> onChooseMedia;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              4,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: index == currentPage ? 26 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == currentPage
                      ? AppColors.amber
                      : AppColors.amber.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (currentPage == 2)
            Row(
              children: [
                Expanded(
                  child: _ChoiceButton(
                    label: 'Allow access',
                    color: AppColors.amber,
                    foregroundColor: AppColors.deepAmber,
                    onPressed: () => onChooseMedia(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ChoiceButton(
                    label: "I'll use text",
                    color: AppColors.coral,
                    foregroundColor: Colors.white,
                    onPressed: () => onChooseMedia(false),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNext,
                icon: Icon(
                  currentPage == 3 ? Icons.check_rounded : Icons.arrow_forward,
                ),
                label: Text(
                                  currentPage == 0
                                      ? 'Get started'
                                      : currentPage == 3
                                          ? 'Start checking in'
                                          : 'Continue',
                                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.color,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foregroundColor,
        minimumSize: const Size.fromHeight(58),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      illustration: _OnboardingIllustration(
        icon: Icons.wb_sunny_rounded,
        secondaryIcon: Icons.auto_awesome,
        accent: AppColors.amber,
      ),
      eyebrow: 'A little room for you',
      title: 'A calm space to\ncheck in with yourself.',
      body: 'No streaks, no pressure. Just a gentle moment that is always yours.',
    );
  }
}

class _WaysToCheckInPage extends StatelessWidget {
  const _WaysToCheckInPage();

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _OnboardingIllustration(
        icon: Icons.forum_rounded,
        secondaryIcon: Icons.graphic_eq_rounded,
        accent: AppColors.coral,
      ),
      eyebrow: 'Three ways to check in',
      title: 'Check in your way.',
      body: 'Share what feels right. Solace listens through only what you choose to share.',
      extra: const _ModeChoices(),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  const _PermissionPage();

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _OnboardingIllustration(
        icon: Icons.shield_rounded,
        secondaryIcon: Icons.favorite_rounded,
        accent: AppColors.amber,
      ),
      eyebrow: 'Your choice, always',
      title: 'Camera & mic are\nalways optional.',
      body: 'Voice and video add another way to be heard. Text is always enough.',
      extra: const Column(
        children: [
          _PromiseRow(
            icon: Icons.mic_none_rounded,
            text: 'Never required. Choose text, voice, or video session by session.',
          ),
          SizedBox(height: 10),
          _PromiseRow(
            icon: Icons.lock_outline_rounded,
            text: 'You can change this anytime in Settings — no questions asked.',
            accent: AppColors.coral,
          ),
          SizedBox(height: 12),
          Text(
            'Permissions will only be requested when you choose a mode that needs them.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.mutedInk,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportPage extends StatelessWidget {
  const _SupportPage();

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _OnboardingIllustration(
        icon: Icons.volunteer_activism_rounded,
        secondaryIcon: Icons.favorite_border_rounded,
        accent: AppColors.coral,
      ),
      eyebrow: 'A quiet safety net',
      title: 'Support is always nearby.',
      body: 'Support resources will live in the You tab — private, calm, and there whenever you need them.',
      extra: const _SupportPreview(),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.illustration,
    required this.eyebrow,
    required this.title,
    required this.body,
    this.extra,
  });

  final Widget illustration;
  final String eyebrow;
  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Column(
        children: [
          illustration,
          const SizedBox(height: 8),
          Text(
            eyebrow.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  height: 1.12,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.mutedInk,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
          if (extra != null) ...[
            const SizedBox(height: 22),
            extra!,
          ],
        ],
      ),
    );
  }
}

class _OnboardingIllustration extends StatelessWidget {
  const _OnboardingIllustration({
    required this.icon,
    required this.secondaryIcon,
    required this.accent,
  });

  final IconData icon;
  final IconData secondaryIcon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 188,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 172,
            height: 172,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.10),
            ),
          ),
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [accent.withValues(alpha: 0.28), accent.withValues(alpha: 0.04)],
              ),
            ),
            child: Icon(icon, size: 68, color: accent),
          ),
          Positioned(
            top: 25,
            right: 58,
            child: Icon(secondaryIcon, size: 28, color: AppColors.coral.withValues(alpha: 0.72)),
          ),
          Positioned(
            bottom: 24,
            left: 62,
            child: _Dot(color: AppColors.amber.withValues(alpha: 0.72), size: 13),
          ),
          Positioned(
            bottom: 42,
            right: 65,
            child: _Dot(color: AppColors.coral.withValues(alpha: 0.55), size: 9),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ModeChoices extends StatelessWidget {
  const _ModeChoices();

  @override
  Widget build(BuildContext context) {
    const modes = [
      (Icons.chat_bubble_outline_rounded, 'Text', 'Type it out'),
      (Icons.mic_none_rounded, 'Voice', 'Say what is there'),
      (Icons.videocam_outlined, 'Video', 'Be seen too'),
    ];

    return Row(
      children: [
        for (var index = 0; index < modes.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
                child: Column(
                  children: [
                    Icon(modes[index].$1, color: index == 1 ? AppColors.coral : AppColors.amber),
                    const SizedBox(height: 8),
                    Text(modes[index].$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      modes[index].$3,
                      style: const TextStyle(fontSize: 10, color: AppColors.mutedInk),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PromiseRow extends StatelessWidget {
  const _PromiseRow({
    required this.icon,
    required this.text,
    this.accent = AppColors.amber,
  });

  final IconData icon;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: accent, size: 21),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportPreview extends StatelessWidget {
  const _SupportPreview();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.coral.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: AppColors.coral),
                SizedBox(width: 6),
                Text(
                  'Available whenever you need it',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border_rounded, size: 16, color: AppColors.coral),
                    SizedBox(width: 7),
                    Text(
                      'You tab  →  Support',
                      style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SolaceMark extends StatelessWidget {
  const _SolaceMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.amber, AppColors.coral],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
        boxShadow: [
          BoxShadow(
            color: AppColors.coral.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(Icons.wb_sunny_rounded, size: size * 0.54, color: Colors.white),
    );
  }
}
