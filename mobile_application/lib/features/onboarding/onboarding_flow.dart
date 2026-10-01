import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/contracts/onboarding_repository.dart';
import '../profile/profile_controller.dart';
import '../profile/sleep_hours_settings.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    required this.repository,
    required this.profileController,
    required this.onComplete,
    super.key,
  });

  final OnboardingRepository repository;
  final ProfileController profileController;
  final VoidCallback onComplete;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _pageCount = 5;

  /// Where the sleep question sits. Pages before it keep their old indices, so
  /// a half-finished onboarding resumes where it left off.
  static const _sleepPage = 3;

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

  /// Asks for sleep hours. Dismissing either picker saves nothing and stays on
  /// the page, so the person can still choose or skip.
  Future<void> _chooseSleep() async {
    final window = await pickSleepWindow(context);
    if (window == null || !mounted) return;
    await widget.profileController.setSleepHours(
      startMinutes: window.startMinutes,
      endMinutes: window.endMinutes,
    );
    if (mounted) await _next();
  }

  /// Declining is an answer, so it is recorded and the page moves on.
  Future<void> _skipSleep() async {
    await widget.profileController.skipSleepHours();
    if (mounted) await _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF9E8), Color(0xFFFEFCE8), Color(0xFFFFF3EC)],
            stops: [0.0, 0.45, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  _TopBar(
                    currentPage: _currentPage,
                    onSkip: _currentPage == _pageCount - 1
                        ? null
                        : _currentPage == _sleepPage
                            ? _skipSleep
                            : _next,
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (page) {
                        setState(() => _currentPage = page);
                        unawaited(widget.repository.setCurrentPage(page));
                      },
                      children: [
                        const _WelcomePage(),
                        const _WaysToCheckInPage(),
                        const _PermissionPage(),
                        _SleepPage(controller: widget.profileController),
                        const _SupportPage(),
                      ],
                    ),
                  ),
                  _BottomControls(
                    currentPage: _currentPage,
                    pageCount: _pageCount,
                    sleepPage: _sleepPage,
                    onNext: _next,
                    onChooseMedia: _chooseMedia,
                    onChooseSleep: _chooseSleep,
                    onSkipSleep: _skipSleep,
                  ),
                ],
              ),
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Row(
        children: [
          const _SolaceMark(size: 38),
          const SizedBox(width: 10),
          Text(
            'SOLACE',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
          ),
          const Spacer(),
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.mutedInk,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: const Text('Skip'),
            ),
        ],
      ),
    );
  }
}

class _KickerPillBadge extends StatelessWidget {
  const _KickerPillBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1FFF7F50),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFFFB534),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: Color(0xFFFF7F50),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryCtaButton extends StatelessWidget {
  const _PrimaryCtaButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC14F), Color(0xFFFFB534)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55FFB534),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(26),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF5A3E08),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  icon,
                  color: const Color(0xFF5A3E08),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.gradient,
    required this.foregroundColor,
    required this.shadowColor,
    required this.onPressed,
  });

  final String label;
  final Gradient gradient;
  final Color foregroundColor;
  final Color shadowColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(26),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.currentPage,
    required this.pageCount,
    required this.sleepPage,
    required this.onNext,
    required this.onChooseMedia,
    required this.onChooseSleep,
    required this.onSkipSleep,
  });

  final int currentPage;
  final int pageCount;
  final int sleepPage;
  final VoidCallback onNext;
  final ValueChanged<bool> onChooseMedia;
  final VoidCallback onChooseSleep;
  final VoidCallback onSkipSleep;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              pageCount,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: index == currentPage ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == currentPage
                      ? const Color(0xFFFFB534)
                      : const Color(0xFFEBDCC0),
                  borderRadius: BorderRadius.circular(100),
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC14F), Color(0xFFFFB534)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    foregroundColor: const Color(0xFF5A3E08),
                    shadowColor: const Color(0x55FFB534),
                    onPressed: () => onChooseMedia(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ChoiceButton(
                    label: "I'll use text",
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8E63), Color(0xFFFF7F50)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    foregroundColor: Colors.white,
                    shadowColor: const Color(0x55FF7F50),
                    onPressed: () => onChooseMedia(false),
                  ),
                ),
              ],
            )
          else if (currentPage == sleepPage)
            Column(
              children: [
                _PrimaryCtaButton(
                  label: 'Set my sleep hours',
                  icon: Icons.bedtime_rounded,
                  onPressed: onChooseSleep,
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onSkipSleep,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mutedInk,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Skip for now'),
                ),
              ],
            )
          else
            _PrimaryCtaButton(
              label: currentPage == 0
                  ? 'Get started'
                  : currentPage == pageCount - 1
                      ? 'Start checking in'
                      : 'Continue',
              icon: currentPage == pageCount - 1
                  ? Icons.check_rounded
                  : Icons.arrow_forward_rounded,
              onPressed: onNext,
            ),
        ],
      ),
    );
  }
}

class _SunriseArtwork extends StatelessWidget {
  const _SunriseArtwork();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 180,
      width: 240,
      child: CustomPaint(
        painter: _SunrisePainter(),
      ),
    );
  }
}

class _SunrisePainter extends CustomPainter {
  const _SunrisePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 240.0;
    final scaleY = size.height / 196.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    // Outer sun aura
    final outerAuraPaint = Paint()
      ..color = const Color(0xFFFFB534).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(120, 92), 86, outerAuraPaint);

    // Inner sun aura
    final innerAuraPaint = Paint()
      ..color = const Color(0xFFFFB534).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(120, 92), 66, innerAuraPaint);

    // Sun core
    final sunCorePaint = Paint()
      ..color = const Color(0xFFFFB534)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(120, 84), 34, sunCorePaint);

    // Sun inner highlight
    final highlightPaint = Paint()
      ..color = const Color(0xFFFFD98A).withValues(alpha: 0.70)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(131, 74), 10, highlightPaint);

    // Coral hill (Left): M20 158 c18-30 44-46 74-46 s56 16 74 46 H20 Z
    final coralHillPath = Path()
      ..moveTo(20, 158)
      ..cubicTo(38, 128, 64, 112, 94, 112)
      ..cubicTo(124, 112, 150, 128, 168, 158)
      ..lineTo(20, 158)
      ..close();
    final coralHillPaint = Paint()
      ..color = const Color(0xFFFF7F50).withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;
    canvas.drawPath(coralHillPath, coralHillPaint);

    // Amber hill (Right): M96 158 c14-22 34-34 58-34 c30 0 52 14 66 34 H96 Z
    final amberHillPath = Path()
      ..moveTo(96, 158)
      ..cubicTo(110, 136, 130, 124, 154, 124)
      ..cubicTo(184, 124, 206, 138, 220, 158)
      ..lineTo(96, 158)
      ..close();
    final amberHillPaint = Paint()
      ..color = const Color(0xFFFFB534).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawPath(amberHillPath, amberHillPaint);

    // Ground line: rect x="10" y="156" width="220" height="8" rx="4" fill="#F4E7C8"
    final groundPaint = Paint()
      ..color = const Color(0xFFF4E7C8)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 156, 220, 8),
        const Radius.circular(4),
      ),
      groundPaint,
    );

    // Floating Sparkles & Dots
    final dot1 = Paint()
      ..color = const Color(0xFFFF7F50).withValues(alpha: 0.50)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(38, 52), 5, dot1);

    final dot2 = Paint()
      ..color = const Color(0xFFFFB534).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(203, 66), 6.5, dot2);

    final dot3 = Paint()
      ..color = const Color(0xFFFF7F50).withValues(alpha: 0.40)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(184, 34), 3.5, dot3);

    // Sparkle arc: path d="M52 96c4-8 12-12 20-10"
    final arcPath = Path()
      ..moveTo(52, 96)
      ..cubicTo(56, 88, 64, 84, 72, 86);
    final arcPaint = Paint()
      ..color = const Color(0xFFFF7F50).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(arcPath, arcPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      illustration: _SunriseArtwork(),
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

class _SleepPage extends StatelessWidget {
  const _SleepPage({required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _OnboardingIllustration(
        icon: Icons.bedtime_rounded,
        secondaryIcon: Icons.wb_twilight_rounded,
        accent: AppColors.amber,
      ),
      eyebrow: 'Your own rhythm',
      title: 'When do you usually\nsleep?',
      body:
          'So ideas can fit how much energy you probably have. It stays on '
          'this phone, and you can change or remove it anytime in Settings.',
      extra: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final window = controller.profile.sleepWindowFor(weekend: false);
          if (window == null) {
            return const _PromiseRow(
              icon: Icons.lock_outline_rounded,
              text: 'Optional. Skipping changes nothing about how Solace works.',
            );
          }
          final start = TimeOfDay(
            hour: window.startMinutes ~/ 60,
            minute: window.startMinutes % 60,
          ).format(context);
          final end = TimeOfDay(
            hour: window.endMinutes ~/ 60,
            minute: window.endMinutes % 60,
          ).format(context);
          return _PromiseRow(
            icon: Icons.check_circle_outline_rounded,
            text: 'Saved: $start to $end.',
          );
        },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 18,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                illustration,
                const SizedBox(height: 16),
                _KickerPillBadge(label: eyebrow),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.mutedInk,
                        height: 1.5,
                        fontSize: 14.5,
                      ),
                  textAlign: TextAlign.center,
                ),
                if (extra != null) ...[
                  const SizedBox(height: 20),
                  extra!,
                ],
              ],
            ),
          ),
        );
      },
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
      height: 180,
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
            child: Icon(icon, size: 62, color: accent),
          ),
          Positioned(
            top: 22,
            right: 68,
            child: Icon(secondaryIcon, size: 26, color: AppColors.coral.withValues(alpha: 0.72)),
          ),
          Positioned(
            bottom: 22,
            left: 72,
            child: _Dot(color: AppColors.amber.withValues(alpha: 0.72), size: 12),
          ),
          Positioned(
            bottom: 38,
            right: 76,
            child: _Dot(color: AppColors.coral.withValues(alpha: 0.55), size: 8),
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
