import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/theme/app_theme.dart';
import '../library/activity_library_page.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../suggestions/suggestion_controller.dart';
import '../suggestions/suggestion_page.dart';
import 'baseline_quiz_page.dart';
import 'profile_controller.dart';

// ─── design tokens ────────────────────────────────────────────────────────────
const _ink = Color(0xFF3A2E1E);
const _muted = Color(0xFF9A8F7A);
const _amber = Color(0xFFFFB534);
const _coral = Color(0xFFFF7F50);
const _cardBg = Colors.white;
const _border = Color(0x28F7F2E6);

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.profileController,
    required this.safetyController,
    required this.suggestionController,
    super.key,
  });

  final ProfileController profileController;
  final SafetyController safetyController;
  final SuggestionController suggestionController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profileController,
      builder: (context, _) {
        final profile = profileController.profile;
        final isQuizComplete = profile.baselineComplete;

        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // ambient warmth blobs
              Positioned(
                top: -80,
                left: -60,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x26FFB534), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
                      children: [
                        // ── page header ──────────────────────────────────
                        _buildPageHeader(context),
                        const SizedBox(height: 20),

                        // ── baseline CTA (must stay near top for tests) ──
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BaselineQuizPage(
                                  profileController: profileController,
                                  safetyController: safetyController,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              isQuizComplete
                                  ? 'Review baseline'
                                  : 'Continue baseline',
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // ── avatar + identity row ────────────────────────
                        _buildAvatarRow(),
                        const SizedBox(height: 18),

                        // ── 4-day rhythm card ────────────────────────────
                        _buildRhythmCard(),
                        const SizedBox(height: 22),

                        // ── YOUR SPACE section ───────────────────────────
                        _buildSectionLabel('YOUR SPACE'),
                        const SizedBox(height: 10),
                        _buildCard(
                          children: [
                            _buildRow(
                              context,
                              icon: Icons.assignment_outlined,
                              title: 'Baseline reflections',
                              subtitle: 'PHQ-9 & GAD-7 baseline assessment',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => BaselineQuizPage(
                                    profileController: profileController,
                                    safetyController: safetyController,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: Color(0x143A3226)),
                            _buildRow(
                              context,
                              icon: Icons.auto_awesome_rounded,
                              title: 'Try a gentle idea',
                              subtitle:
                                  'Optional suggestions with feedback and an easy skip',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => SuggestionPage(
                                    suggestionController: suggestionController,
                                    profileController: profileController,
                                    safetyController: safetyController,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: Color(0x143A3226)),
                            _buildRow(
                              context,
                              icon: Icons.auto_stories_outlined,
                              title: 'Activity library',
                              subtitle:
                                  'Browse the reviewed lifestyle starter set',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ActivityLibraryPage(),
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: Color(0x143A3226)),
                            _buildRow(
                              context,
                              icon: Icons.tune_rounded,
                              title: 'Check-in preferences',
                              subtitle:
                                  'Modality default, gentle notifications',
                              onTap: () => ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Preferences are automatically saved.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // ── PRIVACY & DATA section ───────────────────────
                        _buildSectionLabel('PRIVACY & DATA'),
                        const SizedBox(height: 10),
                        _buildCard(
                          children: [
                            _buildRow(
                              context,
                              icon: Icons.download_outlined,
                              title: 'Export reflections',
                              subtitle: 'Download your notes & entries',
                              onTap: () => ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Export will be available soon.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                ),
                            ),
                            const Divider(height: 1, color: Color(0x143A3226)),
                            _buildRow(
                              context,
                              icon: Icons.lock_outline_rounded,
                              title: 'On-device encryption',
                              subtitle:
                                  'Encrypted locally, zero third-party telemetry',
                              badge: 'Active',
                              badgeActive: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // ── Crisis card ──────────────────────────────────
                        _buildCrisisCard(context),
                        const SizedBox(height: 28),

                        // ── footer ───────────────────────────────────────
                        const Text(
                          'Solace is an emotional reflection space,\nnot a medical provider.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _muted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Solace v0.1.0 · Local-first & Private',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC8BDB0),
                          ),
                        ),
                      ],
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

  // ── page header ─────────────────────────────────────────────────────────────
  Widget _buildPageHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.amber, AppColors.coral],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.person_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Your choices stay yours to revisit.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── avatar row ──────────────────────────────────────────────────────────────
  Widget _buildAvatarRow() {
    return Row(
      children: [
        // avatar ring
        Stack(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE9A0), Color(0xFFFFB534)],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55FFB534),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF8DCB8A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Maya Lin',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: Color(0xFF332C21),
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Member since September 2026',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 4-day rhythm card ───────────────────────────────────────────────────────
  Widget _buildRhythmCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF6), Color(0xFFFFF9EE)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x52F6EFD9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14785C28),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3DC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.eco_rounded, color: Color(0xFFB57A12), size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '4-day rhythm',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4A4133),
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Showing up when it feels right · 2 rest days',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _dot(true, false),
                    const SizedBox(width: 5),
                    _dot(true, false),
                    const SizedBox(width: 5),
                    _dot(false, false),
                    const SizedBox(width: 5),
                    _dot(true, false),
                    const SizedBox(width: 5),
                    _dot(true, false),
                    const SizedBox(width: 5),
                    _dot(true, true),
                    const SizedBox(width: 5),
                    _dot(false, false),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(bool on, bool today) => Container(
        width: today ? 9 : 7,
        height: today ? 9 : 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: today
              ? _coral
              : on
                  ? _amber
                  : const Color(0xFFEFE6D2),
        ),
      );

  // ── section label ───────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: _muted,
        ),
      ),
    );
  }

  // ── generic card container ──────────────────────────────────────────────────
  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14785C28),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  // ── row within card ─────────────────────────────────────────────────────────
  Widget _buildRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    bool badgeActive = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFC08A1E), size: 19),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeActive
                        ? const Color(0xFFFFF3DC)
                        : const Color(0xFFF4F1E7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: badgeActive
                          ? const Color(0xFFB57A12)
                          : const Color(0xFF9A9182),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFD3C8B2),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── crisis card ─────────────────────────────────────────────────────────────
  Widget _buildCrisisCard(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SupportResourcesPage(
              safetyController: safetyController,
              assessment:
                  safetyController.activeAssessment ??
                  const SafetyAssessment.clear(),
              regionCode:
                  Localizations.localeOf(context).countryCode ?? 'GLOBAL',
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF4EE), Color(0xFFFFEEE5)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFFDAC8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x28FF7F50),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4D6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Color(0xFFD2603A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need human care right now?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB4522C),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Free, confidential crisis lines available 24/7.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFC08060),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFE8A98C),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
