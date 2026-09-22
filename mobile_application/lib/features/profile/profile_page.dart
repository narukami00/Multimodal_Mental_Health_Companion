import 'package:flutter/material.dart';

import '../../core/models/safety_assessment.dart';
import '../../core/models/user_profile.dart';
import '../library/activity_library_page.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../suggestions/suggestion_controller.dart';
import '../suggestions/suggestion_page.dart';
import 'baseline_quiz_page.dart';
import 'profile_controller.dart';

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
        final completeCount = _completedBlocks(profile);
        const displayName = 'Maya Lin';

        return Scaffold(
          backgroundColor: const Color(0xFFFEFCE8),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  children: [
                    // Top header: Brandmark + subtle settings button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFFFB534), Color(0xFFFF7F50)],
                                ),
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x66FF7F50),
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            const Text(
                              'SOLACE',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                color: Color(0xFFB9A98C),
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () => _showAppSettingsSheet(context),
                          borderRadius: BorderRadius.circular(13),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: const Color(0xFFF2ECDD)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1078501E),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              size: 19,
                              color: Color(0xFF8E8272),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Profile avatar + Name header
                    Row(
                      children: [
                        // Avatar ring
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 74,
                              height: 74,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFFD88A),
                                    Color(0xFFFFB534),
                                    Color(0xFFFF9A6A),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x3BD69628),
                                    blurRadius: 20,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(23),
                                child: Container(
                                  color: const Color(0xFFFFF6E4),
                                  child: const Center(
                                    child: Icon(
                                      Icons.face_3_rounded,
                                      size: 42,
                                      color: Color(0xFF7A5832),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF8DCB8A),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF332C21),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => _showEditProfileSheet(context),
                                    borderRadius: BorderRadius.circular(99),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                        color: Color(0xFFA2988A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Member since September 2026',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF93887A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Gentle Rhythm Card (Non-punitive streak)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFFFDF6), Color(0xFFFFFAEE)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFF6EFD9)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14785C28),
                            blurRadius: 18,
                            offset: Offset(0, 4),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.eco_rounded,
                              size: 20,
                              color: Color(0xFFB57A12),
                            ),
                          ),
                          const SizedBox(width: 13),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '4-day rhythm',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4A4133),
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Showing up when it feels right · 2 rest days',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF93887A),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 7-day gentle rhythm indicators
                          Row(
                            children: [
                              _dot(true, false),
                              const SizedBox(width: 4),
                              _dot(true, false),
                              const SizedBox(width: 4),
                              _dot(false, false),
                              const SizedBox(width: 4),
                              _dot(true, false),
                              const SizedBox(width: 4),
                              _dot(true, true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // SECTION: YOUR CARE (Matching HTML Reference)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'YOUR CARE',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: Color(0xFFBCAC8E),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0xFFF7F2E6)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x18785C28),
                            blurRadius: 22,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _menuRow(
                            icon: Icons.checklist_rounded,
                            iconBg: const Color(0xFFFFF3DC),
                            iconColor: const Color(0xFFC08A1E),
                            title: 'Habit & medication tracking',
                            subtitle: 'Morning routine · 2 reminders',
                            badgeText: '3 of 4',
                            onTap: () => _showHabitsSheet(context),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF2ECDD),
                          ),
                          _menuRow(
                            icon: Icons.file_download_outlined,
                            iconBg: const Color(0xFFFFF3DC),
                            iconColor: const Color(0xFFC08A1E),
                            title: 'Export reflections & data',
                            subtitle: 'Journal, moods & tracking as PDF / JSON',
                            badgeText: 'Export',
                            onTap: () => _showExportSheet(context),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF2ECDD),
                          ),
                          _menuRow(
                            icon: Icons.groups_outlined,
                            iconBg: const Color(0xFFFFF3DC),
                            iconColor: const Color(0xFFC08A1E),
                            title: 'Therapist collaboration',
                            subtitle: 'Shared with Dr. Amara Reid',
                            badgeText: 'On',
                            badgeColor: const Color(0xFFF4F1E7),
                            badgeTextColor: const Color(0xFF7A6E5D),
                            onTap: () => _showTherapistSheet(context),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF2ECDD),
                          ),
                          _menuRow(
                            icon: Icons.verified_user_outlined,
                            iconBg: const Color(0xFFFFF3DC),
                            iconColor: const Color(0xFFC08A1E),
                            title: 'Privacy & data architecture',
                            subtitle: 'On-device first · zero telemetry',
                            badgeText: 'Active',
                            badgeColor: const Color(0xFFEBF7EB),
                            badgeTextColor: const Color(0xFF3F823B),
                            onTap: () => _showPrivacySheet(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // SECTION: CRISIS SUPPORT (Warm coral card)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'SUPPORT',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: Color(0xFFBCAC8E),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SupportResourcesPage(
                            safetyController: safetyController,
                            assessment:
                                safetyController.activeAssessment ??
                                const SafetyAssessment.clear(),
                            regionCode:
                                Localizations.localeOf(context).countryCode ??
                                'GLOBAL',
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFFF4EE), Color(0xFFFFEEE5)],
                          ),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: const Color(0xFFFFDAC8)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33FF7F50),
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE4D6),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.support_agent_rounded,
                                size: 22,
                                color: Color(0xFFD2603A),
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
                                      fontSize: 15.2,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFB4522C),
                                      letterSpacing: -0.15,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Free, confidential crisis lines available 24/7.',
                                    style: TextStyle(
                                      fontSize: 12.2,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFC08060),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: Color(0xFFE8A98C),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // SECTION: YOUR SPACE & PRACTICES
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'YOUR SPACE & PRACTICES',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: Color(0xFFBCAC8E),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0xFFF7F2E6)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x18785C28),
                            blurRadius: 22,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Baseline reflections row & progress
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3DC),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.assignment_outlined,
                                        size: 20,
                                        color: Color(0xFFC08A1E),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Baseline reflections',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF3B3327),
                                              letterSpacing: -0.15,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            profile.baselineComplete
                                                ? 'Starting point complete · Revisit anytime'
                                                : '$completeCount of 4 sections complete',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF93887A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (profile.baselineComplete)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEBF7EB),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'Done',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF3F823B),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: completeCount / 4,
                                    minHeight: 6,
                                    backgroundColor: const Color(0xFFFFF0D4),
                                    valueColor: const AlwaysStoppedAnimation(
                                      Color(0xFFFFB534),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 42,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFF6E2),
                                      foregroundColor: const Color(0xFFB57A12),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        side: const BorderSide(
                                          color: Color(0xFFF6E2BC),
                                        ),
                                      ),
                                    ),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => BaselineQuizPage(
                                          profileController: profileController,
                                          safetyController: safetyController,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      profile.baselineComplete
                                          ? 'Review baseline'
                                          : 'Continue baseline',
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF2ECDD),
                          ),

                          // Activity library
                          _menuRow(
                            icon: Icons.local_library_outlined,
                            iconBg: const Color(0xFFFFF3DC),
                            iconColor: const Color(0xFFC08A1E),
                            title: 'Activity library',
                            subtitle: 'Browse reviewed lifestyle starter set',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ActivityLibraryPage(),
                              ),
                            ),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF2ECDD),
                          ),

                          // Gentle ideas
                          _menuRow(
                            icon: Icons.auto_awesome_rounded,
                            iconBg: const Color(0xFFFFF3DC),
                            iconColor: const Color(0xFFC08A1E),
                            title: 'Try a gentle idea',
                            subtitle: 'Personalized practices & quick suggestions',
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
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF2ECDD),
                          ),

                          // App Settings row
                          _menuRow(
                            icon: Icons.settings_outlined,
                            iconBg: const Color(0xFFFFF3DC),
                            iconColor: const Color(0xFFC08A1E),
                            title: 'App settings',
                            subtitle: 'Theme, sounds, notifications & language',
                            onTap: () => _showAppSettingsSheet(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // App Disclaimer & Version footer
                    const Text(
                      'Solace is a reflection space, not a medical or clinical provider.\nSolace v0.1.0 · Local-first & Private',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB5A98F),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _dot(bool active, bool isToday) {
    return Container(
      width: isToday ? 9 : 7,
      height: isToday ? 9 : 7,
      decoration: BoxDecoration(
        color: isToday
            ? const Color(0xFFFF7F50)
            : active
                ? const Color(0xFFFFB534)
                : const Color(0xFFEFE6D2),
        shape: BoxShape.circle,
      ),
    );
  }

  static Widget _menuRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    String? badgeText,
    Color? badgeColor,
    Color? badgeTextColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3B3327),
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.2,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF93887A),
                    ),
                  ),
                ],
              ),
            ),
            if (badgeText != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeColor ?? const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: badgeTextColor ?? const Color(0xFFB57A12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: Color(0xFFD3C8B2),
            ),
          ],
        ),
      ),
    );
  }

  static void _showModalSheet({
    required BuildContext context,
    required Widget child,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFFDF8),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x33684B20),
                blurRadius: 32,
                offset: Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 26,
            top: 12,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2D6C0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        );
      },
    );
  }

  // 1. Habit & Medication Sheet
  static void _showHabitsSheet(BuildContext context) {
    _showModalSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  size: 20,
                  color: Color(0xFFB57A12),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Habit & medication tracking',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    Text(
                      'Gentle anchors · Zero punishment for rest days',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93887A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _habitItem('Morning sunlight & hydration', '8:00 AM', true),
          _habitItem('Midday 3-minute breath pause', '1:30 PM', true),
          _habitItem('Evening emotional reflection', '8:30 PM', true),
          _habitItem('Gentle medication reminder', '9:15 PM', false),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9EE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF7EBCE)),
            ),
            child: const Row(
              children: [
                Icon(Icons.spa_outlined, size: 16, color: Color(0xFFB57A12)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No broken streak counters. Resting is an essential part of gentle care.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A6E5D),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _habitItem(String title, String time, bool completed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: completed ? const Color(0xFF8DCB8A) : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: completed
                    ? const Color(0xFF8DCB8A)
                    : const Color(0xFFD6C8AF),
                width: 1.5,
              ),
            ),
            child: completed
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: completed
                    ? const Color(0xFF3B3327)
                    : const Color(0xFF706454),
              ),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA2988A),
            ),
          ),
        ],
      ),
    );
  }

  // 2. Export reflections & data
  static void _showExportSheet(BuildContext context) {
    _showModalSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.file_download_outlined,
                  size: 20,
                  color: Color(0xFFB57A12),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export reflections & data',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    Text(
                      'Encrypted on-device · Your notes belong to you',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93887A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _exportOptionCard(
            title: 'Formatted Reflection Journal (PDF)',
            desc: 'Clean, printable layout with emotion cadence & baseline history.',
            icon: Icons.picture_as_pdf_outlined,
            isSelected: true,
          ),
          const SizedBox(height: 10),
          _exportOptionCard(
            title: 'Encrypted Full Backup (JSON)',
            desc: 'Complete database export for offline archival or migration.',
            icon: Icons.data_object_rounded,
            isSelected: false,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _rangeChip('Last 7 days', false),
              const SizedBox(width: 8),
              _rangeChip('Last 30 days', true),
              const SizedBox(width: 8),
              _rangeChip('All time', false),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Export generated: solace_reflections_maya.pdf'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text(
                'Generate Export File',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _exportOptionCard({
    required String title,
    required String desc,
    required IconData icon,
    required bool isSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFFF9EE) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFFFFB534) : const Color(0xFFF2ECDD),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: isSelected ? const Color(0xFFB57A12) : const Color(0xFFA2988A),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3B3327),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF93887A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _rangeChip(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFF0D4) : const Color(0xFFF6F1E5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFFFFB534) : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: active ? const Color(0xFFB57A12) : const Color(0xFF887D6E),
        ),
      ),
    );
  }

  // 3. Therapist Collaboration Sheet
  static void _showTherapistSheet(BuildContext context) {
    _showModalSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  size: 20,
                  color: Color(0xFFB57A12),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Therapist collaboration',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    Text(
                      'High-level overview · Private entries remain locked',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93887A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF2ECDD)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFFFE8D1),
                  child: const Text(
                    'AR',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFD2603A),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dr. Amara Reid, PhD',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3B3327),
                        ),
                      ),
                      Text(
                        'Mindful Care Associates · Licensed Clinical',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF93887A),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF7EB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F823B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'SHARED SCOPE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xFFBCAC8E),
            ),
          ),
          const SizedBox(height: 8),
          _scopeItem(Icons.check_circle_outline, 'Weekly emotion rhythm & energy cadence', true),
          _scopeItem(Icons.check_circle_outline, 'GAD-7 & PHQ-9 baseline summaries', true),
          _scopeItem(Icons.lock_outline, 'Private verbatim journal text (Always confidential to you)', false),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Clinician 1-Page Brief prepared for Dr. Reid'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text(
                'Send 1-Page Summary Brief',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _scopeItem(IconData icon, String text, bool shared) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: shared ? const Color(0xFF3F823B) : const Color(0xFFB4522C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: shared ? const Color(0xFF4A4133) : const Color(0xFFB4522C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 4. Privacy & Data Architecture Sheet
  static void _showPrivacySheet(BuildContext context) {
    _showModalSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: Color(0xFFB57A12),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy & data architecture',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    Text(
                      'Local-first by design · Zero external trackers',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93887A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _privacyPillar(
            title: 'AES-256 Local Enclave Encryption',
            desc: 'Reflections and audio metadata are encrypted locally. Keys never leave this hardware.',
            icon: Icons.lock_rounded,
          ),
          const SizedBox(height: 10),
          _privacyPillar(
            title: 'Zero Third-Party Telemetry',
            desc: 'No Google Analytics, advertising identifiers, or cloud tracking scripts.',
            icon: Icons.shield_rounded,
          ),
          const SizedBox(height: 10),
          _privacyPillar(
            title: 'Local Heuristics & Speech Models',
            desc: 'Safety classification and prompts are processed on-device whenever supported.',
            icon: Icons.memory_rounded,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4A4133),
                side: const BorderSide(color: Color(0xFFE2D6C0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _privacyPillar({
    required String title,
    required String desc,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2ECDD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF7EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF3F823B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3B3327),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF93887A),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 5. App Settings Sheet
  static void _showAppSettingsSheet(BuildContext context) {
    _showModalSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: Color(0xFFB57A12),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App settings',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    Text(
                      'Sensory & gentle interaction preferences',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93887A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _settingToggle(
            title: 'Gentle Haptics',
            subtitle: 'Subtle vibrational cues on taps and sliders',
            value: true,
          ),
          _settingToggle(
            title: 'Soft Ambient Breath Audio',
            subtitle: 'Calming chimes during grounding pauses',
            value: true,
          ),
          _settingToggle(
            title: 'Evening Reminder',
            subtitle: 'Gentle 8:30 PM notification (silent, no alarm)',
            value: true,
          ),
          const SizedBox(height: 14),
          const Text(
            'COLOR PALETTE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xFFBCAC8E),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _rangeChip('Warm Cream (Default)', true),
              const SizedBox(width: 8),
              _rangeChip('Soft Twilight', false),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Save Preferences',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _settingToggle({
    required String title,
    required String subtitle,
    required bool value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B3327),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF93887A),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFFFFB534),
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }

  // 6. Edit Profile Sheet
  static void _showEditProfileSheet(BuildContext context) {
    _showModalSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Profile & Identity',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3B3327),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'How Solace gently greets you in reflections.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF93887A),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: 'Maya Lin',
            decoration: InputDecoration(
              labelText: 'Preferred Name',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE2D6C0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE2D6C0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFFFB534), width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Save Profile',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _completedBlocks(UserProfile profile) {
    var completed = profile.preferencesCompleted ? 1 : 0;
    if (profile.erqSComplete || profile.erqSSkipped) completed++;
    if (profile.gad7Complete || profile.gad7Skipped) completed++;
    if (profile.phq9Complete || profile.phq9Skipped) completed++;
    return completed;
  }
}
