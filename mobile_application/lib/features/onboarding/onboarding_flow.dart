import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/models/consent.dart';
import '../../services/check_in_reminder_service.dart';
import '../checkin/check_in_mode_page.dart';
import '../consent/consent_controller.dart';
import 'onboarding_choices.dart';
import '../../core/widgets/visual_kit.dart';
import '../art/checkin_art.dart';
import '../../data/contracts/onboarding_repository.dart';
import '../profile/country_picker.dart';
import '../profile/profile_controller.dart';
import '../profile/sleep_hours_settings.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    required this.repository,
    required this.profileController,
    required this.onComplete,
    this.consent,
    this.scheduleReminder,
    super.key,
  });

  /// Where the voice and face choices are recorded. Defaults to the app's own; without one the page is left out.
  final ConsentController? consent;

  /// Turns the daily reminder on at the given minute (asking for notification permission) and says whether it worked.
  final Future<bool> Function(int minutes)? scheduleReminder;

  final OnboardingRepository repository;
  final ProfileController profileController;
  final VoidCallback onComplete;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _pageCount = 10;

  /// The two pages that only make sense for someone who chose to use voice or video.
  static const _readingPage = 3;
  static const _modelsPage = 4;

  /// Where the sleep question sits.
  static const _sleepPage = 5;

  /// The optional "what should I call you" step.
  static const _namePage = 7;

  /// The optional daily reminder, just before the safety page.
  static const _reminderPage = 8;

  ConsentController? get _consent => widget.consent ?? CheckInModePage.consent;

  /// Whether [page] is part of this person's onboarding: the voice and video pages are skipped for someone who chose text.
  bool _shows(int page) {
    if (page == _readingPage) return widget.repository.usesMedia == true && _consent != null;
    if (page == _modelsPage) return widget.repository.usesMedia == true;
    return true;
  }

  late final PageController _pageController;
  late int _currentPage;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.repository.currentPage.clamp(0, _pageCount - 1).toInt();
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_currentPage == _pageCount - 1) {
      await widget.repository.complete();
      if (mounted) widget.onComplete();
      return;
    }

    var next = _currentPage + 1;
    while (next < _pageCount - 1 && !_shows(next)) {
      next++;
    }
    await _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// Offers the daily reminder: a time, then notification permission. Nothing is claimed unless it was really set.
  Future<void> _setReminder() async {
    final profile = widget.profileController.profile;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (profile.reminderMinutes ~/ 60) % 24, minute: profile.reminderMinutes % 60),
      helpText: 'Check-in reminder time',
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    var worked = false;
    try {
      worked = await (widget.scheduleReminder ?? _scheduleReal)(minutes);
    } catch (_) {}
    if (worked) {
      await widget.profileController.setReminderMinutes(minutes);
      await widget.profileController.setReminderEnabled(true);
    }
    if (!mounted) return;
    if (!worked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No reminder was set, because notifications are off for Solace. You can turn it on later in Settings.'),
      ));
    }
    await _next();
  }

  Future<bool> _scheduleReal(int minutes) async {
    final service = CheckInReminderService.instance;
    if (!await service.requestPermission()) return false;
    final name = widget.profileController.profile.displayName;
    return (await service.scheduleDaily(minutesPastMidnight: minutes, displayName: name)).isScheduled;
  }

  /// Keeps the name if they typed one, then moves on. Leaving it empty is fine.
  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      await widget.profileController.saveIdentity(displayName: name);
    }
    if (mounted) await _next();
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
                        _ReadingPage(consent: _consent),
                        _ModelsPage(consent: _consent),
                        _SleepPage(controller: widget.profileController),
                        _CountryPage(controller: widget.profileController),
                        _NamePage(field: _name, onDone: _saveName),
                        _ReminderPage(controller: widget.profileController),
                        const _SupportPage(),
                      ],
                    ),
                  ),
                  _BottomControls(
                    currentPage: _currentPage,
                    dotCount: [for (var p = 0; p < _pageCount; p++) if (_shows(p)) p].length,
                    dotIndex: [for (var p = 0; p < _currentPage; p++) if (_shows(p)) p].length,
                    pageCount: _pageCount,
                    sleepPage: _sleepPage,
                    namePage: _namePage,
                    reminderPage: _reminderPage,
                    onSetReminder: _setReminder,
                    onSaveName: _saveName,
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
    required this.dotCount,
    required this.dotIndex,
    required this.pageCount,
    required this.sleepPage,
    required this.namePage,
    required this.reminderPage,
    required this.onSetReminder,
    required this.onSaveName,
    required this.onNext,
    required this.onChooseMedia,
    required this.onChooseSleep,
    required this.onSkipSleep,
  });

  final int currentPage;
  final int dotCount;
  final int dotIndex;
  final int pageCount;
  final int sleepPage;
  final int namePage;
  final int reminderPage;
  final VoidCallback onSetReminder;
  final VoidCallback onSaveName;
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
              dotCount,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: index == dotIndex ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == dotIndex
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
          else if (currentPage == reminderPage)
            Column(
              children: [
                _PrimaryCtaButton(
                  label: 'Set a reminder',
                  icon: Icons.notifications_active_rounded,
                  onPressed: onSetReminder,
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onNext,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mutedInk,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  child: const Text('Not now'),
                ),
              ],
            )
          else if (currentPage == namePage)
            _PrimaryCtaButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: onSaveName,
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
    return const _OnboardingPage(
      illustration: _ModeChoices(),
      eyebrow: 'Three ways to check in',
      title: 'Check in your way.',
      body: 'Share what feels right, and only as much as you choose.',
    );
  }
}

class _PermissionPage extends StatelessWidget {
  const _PermissionPage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      illustration: _Scene(HeroScene.permissions),
      eyebrow: 'Your choice, always',
      title: 'Camera & mic are\nalways optional.',
      body: 'Voice and video add another way to be heard. Text is always enough.',
      extra: Column(
        children: [
          _PromiseRow(
            icon: Icons.mic_none_rounded,
            text: 'Never required. Pick text, voice or video each time.',
          ),
          SizedBox(height: 10),
          _PromiseRow(
            icon: Icons.lock_outline_rounded,
            text: 'Asked only when a mode needs it. Change it in Settings.',
            accent: AppColors.coral,
          ),
        ],
      ),
    );
  }
}

/// What Solace may read, asked once and kindly: same switches as Permissions & privacy.
class _ReadingPage extends StatelessWidget {
  const _ReadingPage({required this.consent});

  final ConsentController? consent;

  @override
  Widget build(BuildContext context) {
    final consent = this.consent;
    return _OnboardingPage(
      illustration: const _Scene(HeroScene.privacy),
      eyebrow: 'Only if you want',
      title: 'What may Solace\nnotice?',
      body: 'A weak guess about how an entry sounds can make your journal more useful. It is always your call.',
      extra: consent == null ? null : ReadingChoices(consent: consent),
    );
  }
}

/// Voice and video journals that work without the server, by keeping two small models on this phone.
class _ModelsPage extends StatelessWidget {
  const _ModelsPage({required this.consent});

  final ConsentController? consent;

  @override
  Widget build(BuildContext context) {
    final consent = this.consent;
    return _OnboardingPage(
      illustration: const _Scene(HeroScene.settings),
      eyebrow: 'Works without the server',
      title: 'Journal anywhere,\neven offline.',
      body: 'Keep a small model on this phone and your voice and video journals are written down even when your server is off. '
          'They are read later, when it is back.',
      extra: consent == null
          ? const OfflineModelChoices()
          : ListenableBuilder(
              listenable: consent,
              builder: (context, _) => OfflineModelChoices(offerFace: consent.isGranted(ConsentKey.faceFeatures)),
            ),
    );
  }
}

class _ReminderPage extends StatelessWidget {
  const _ReminderPage({required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _Scene(HeroScene.memory),
      eyebrow: 'A gentle nudge',
      title: 'Want a daily\nreminder?',
      body: 'A quiet check-in reminder at a time that suits you. No streaks, and it fades away if you are busy.',
      extra: ReminderChoice(controller: controller),
    );
  }
}

class _SleepPage extends StatelessWidget {
  const _SleepPage({required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _Scene(HeroScene.rhythm),
      eyebrow: 'Your own rhythm',
      title: 'When do you usually\nsleep?',
      body: 'So ideas can fit your energy. It stays on this phone and you can change it in Settings.',
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

class _CountryPage extends StatelessWidget {
  const _CountryPage({required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _Scene(HeroScene.contacts),
      eyebrow: 'So help is local',
      title: 'Where are you\nbased?',
      body: 'This only decides which emergency number and support line you see. It stays on this phone.',
      extra: CountryPicker(controller: controller),
    );
  }
}

/// An optional name, only used to say hello. Nothing is required.
class _NamePage extends StatelessWidget {
  const _NamePage({required this.field, required this.onDone});

  final TextEditingController field;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      illustration: const _Scene(HeroScene.about),
      eyebrow: 'Just between us',
      title: 'What should I\ncall you?',
      body: 'Only used to greet you. Stays on this phone, and you can leave it blank.',
      extra: TextField(
        key: const ValueKey('onboarding-name'),
        controller: field,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        maxLength: 24,
        onSubmitted: (_) => onDone(),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: 'Your name or a nickname',
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: Color(0xFFEBDCC0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: Color(0xFFEBDCC0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.amber, width: 1.8),
          ),
        ),
      ),
    );
  }
}

class _SupportPage extends StatelessWidget {
  const _SupportPage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingPage(
      illustration: _Scene(HeroScene.support),
      eyebrow: 'A quiet safety net',
      title: 'Support is always nearby.',
      body: 'Private, calm, and there whenever you need it. Solace is a space for reflection, not medical care.',
      extra: _SupportPreview(),
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
        // The page settles in: the picture first, then the words.
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: (constraints.maxHeight - 18).clamp(0.0, double.infinity)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: t,
                    child: Transform.scale(scale: 0.94 + 0.06 * t, child: illustration),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - t)),
                      child: Column(
                        children: [
                          _KickerPillBadge(label: eyebrow),
                          const SizedBox(height: 14),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            body,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: AppColors.mutedInk,
                                  height: 1.45,
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
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A painted, gently moving scene from the app's own picture set, in a soft frame.
class _Scene extends StatefulWidget {
  const _Scene(this.scene);

  final HeroScene scene;

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 10));

  @override
  void initState() {
    super.initState();
    if (!_still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static bool get _still {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x1FB0782A), blurRadius: 24, spreadRadius: -8, offset: Offset(0, 12))],
      ),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: HeroPainter(widget.scene, _still ? 0.35 : _c.value)),
        ),
      ),
    );
  }
}

class _ModeChoices extends StatelessWidget {
  const _ModeChoices();

  @override
  Widget build(BuildContext context) {
    const modes = [
      (CheckInKind.text, 'Text', 'Type it out'),
      (CheckInKind.voice, 'Voice', 'Say what is there'),
      (CheckInKind.video, 'Video', 'Be seen too'),
    ];
    return Row(
      children: [
        for (var index = 0; index < modes.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 0.82,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [BoxShadow(color: Color(0x1FB0782A), blurRadius: 16, spreadRadius: -6, offset: Offset(0, 8))],
                    ),
                    child: CheckInArt(kind: modes[index].$1, radius: 26),
                  ),
                ),
                const SizedBox(height: 10),
                Text(modes[index].$2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  modes[index].$3,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.mutedInk),
                  textAlign: TextAlign.center,
                ),
              ],
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
                Flexible(
                  child: Text(
                    'Available whenever you need it',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
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
                    Flexible(
                      child: Text(
                        'You tab  →  Support',
                        style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w800),
                      ),
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
