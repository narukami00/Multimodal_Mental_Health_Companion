import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/emergency_contact.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/theme/solace_palette.dart';
import '../../domain/home/baseline_progress.dart';
import '../../domain/profile/behavioral_profile.dart';
import '../../domain/rhythm/reminder_schedule.dart';
import '../../services/ambient_audio_service.dart';
import '../../services/check_in_reminder_service.dart';
import '../../services/dialer_service.dart';
import '../library/activity_library_page.dart';
import '../safety/care_contacts_page.dart';
import '../safety/safety_controller.dart';
import '../safety/support_resources_page.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_context.dart';
import '../suggestions/suggestion_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import 'about_pages.dart';
import 'baseline_quiz_page.dart';
import 'permissions_page.dart';
import 'phone_patterns_page.dart';
import 'profile_controller.dart';
import 'profile_insights_page.dart';
import 'sleep_hours_settings.dart';

/// The baseline reflections entry, which carries its own progress and button.
///
/// Split out rather than inlined because it is the one row that is not a row.
/// It has a progress bar, a count and a full-width action, so forcing it into
/// the same one-line shape as its neighbours is what made the old card look
/// like two screens stitched together. It leads its own group instead, where
/// being different is the point.
class _BaselineRow extends StatelessWidget {
  const _BaselineRow({
    required this.completeCount,
    required this.isComplete,
    required this.onTap,
  });

  final int completeCount;
  final bool isComplete;
  final VoidCallback onTap;

  static const _total = 4;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  size: 17,
                  color: Color(0xFFC08A1E),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Baseline reflections',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: Color(0xFF3B3327),
                  ),
                ),
              ),
              if (isComplete)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F823B),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          // Four discrete segments rather than a progress bar.
          //
          // A continuous bar asks the reader to estimate a fraction; four
          // segments say "two of four, two to go" without reading a number. It
          // also stops the bar from being the only thing on the card that is not
          // the same shape as the rows around it.
          Row(
            children: [
              for (var i = 0; i < _total; i++) ...[
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < completeCount
                          ? const Color(0xFFFFB534)
                          : const Color(0xFFF3E7CE),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                if (i < _total - 1) const SizedBox(width: 5),
              ],
            ],
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
                  side: const BorderSide(color: Color(0xFFF6E2BC)),
                ),
              ),
              onPressed: onTap,
              child: Text(
                isComplete ? 'Review baseline' : 'Continue baseline',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.profileController,
    required this.safetyController,
    required this.suggestionController,
    required this.sessionController,
    this.phonePatterns,
    super.key,
  });

  final ProfileController profileController;
  final SafetyController safetyController;
  final SuggestionController suggestionController;
  final SessionController sessionController;

  /// The opt-in phone patterns control, shown on the permissions page.
  final PhonePatternsController? phonePatterns;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([profileController, sessionController]),
      builder: (context, _) {
        final profile = profileController.profile;
        final completeCount = BaselineProgress.of(profile).completed;
        final emergencyContacts = profile.emergencyContacts;
        final iceContact = profileController.iceContact;
        final displayName = profile.displayName?.trim().isNotEmpty == true
            ? profile.displayName!.trim()
            : 'Add your name';

        return Scaffold(
          backgroundColor: SolaceColors.from(context).background,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: ListView(
                  // Room for the floating pill, which overlays the page.
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
                  children: [
                    // Only the settings control. The brandmark and the SOLACE
                    // wordmark that used to sit opposite it are gone: they named
                    // the app three inches above a name that was already on
                    // screen, so they were decoration repeating what the page
                    // said anyway. The gear stays, because it is the one thing
                    // the header exists for — and it is the only route to app
                    // settings now that the duplicate row is gone.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () => _showAppSettingsSheet(
                            context,
                            profileController,
                          ),
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
                                child: GestureDetector(
                                  onTap: () => _pickAvatar(context),
                                  child: Container(
                                    color: const Color(0xFFFFF6E4),
                                    child: _AvatarContent(
                                      avatarPath: profile.avatarPath,
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
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF332C21),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => _showEditProfileSheet(
                                      context,
                                      profileController,
                                    ),
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
                              Text(
                                _memberSinceLabel(profile.firstRunAt),
                                style: const TextStyle(
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

// SECTION: SUPPORT.
                    //
                    // First, not third. It used to sit below a five-row block of
                    // care settings, which meant the one row on this page that
                    // someone might need urgently was the hardest to reach.
                    _group(
                      label: 'Support',
                      rows: [
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SupportResourcesPage(
                                safetyController: safetyController,
                                profileController: profileController,
                                assessment:
                                    safetyController.activeAssessment ??
                                    const SafetyAssessment.clear(),
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFFF4EE),
                                  Color(0xFFFFEEE5),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(color: const Color(0xFFFFDAC8)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x2BFF7F50),
                                  blurRadius: 18,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE4D6),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Icon(
                                    Icons.support_agent_rounded,
                                    size: 21,
                                    color: Color(0xFFD2603A),
                                  ),
                                ),
                                const SizedBox(width: 13),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Crisis support',
                                        style: TextStyle(
                                          fontSize: 15.2,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFB4522C),
                                          letterSpacing: -0.15,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Free, confidential lines · 24/7',
                                        style: TextStyle(
                                          fontSize: 12.2,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFC08060),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (iceContact != null) ...[
                                  _IceCallButton(
                                    contact: iceContact,
                                    onCall: () =>
                                        _callIceContact(context, iceContact),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 13,
                                  color: Color(0xFFE8A98C),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SECTION: CARE CIRCLE.
                    //
                    // Not "Your care". The old name sat above a list that also
                    // contained permissions, data export and a therapist, so it
                    // described none of them. This group holds only people.
                    _group(
                      label: 'Care circle',
                      trailingLabel: emergencyContacts.isEmpty
                          ? null
                          : '${emergencyContacts.length} saved',
                      rows: [
                        _row(
                          icon: Icons.people_outline_rounded,
                          title: 'Emergency contacts',
                          value: emergencyContacts.isEmpty
                              ? 'None yet'
                              : '${emergencyContacts.length}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CareContactsPage(
                                profileController: profileController,
                              ),
                            ),
                          ),
                        ),
                        _row(
                          icon: Icons.groups_outlined,
                          title: 'Therapist collaboration',
                          value: 'On',
                          onTap: () => _showTherapistSheet(context),
                        ),
                        _row(
                          icon: Icons.checklist_rounded,
                          title: 'Habit & medication',
                          value: '3 of 4',
                          onTap: () => _showHabitsSheet(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SECTION: YOUR DATA.
                    _group(
                      label: 'Your data',
                      trailingLabel: 'on this device',
                      rows: [
                        _row(
                          icon: Icons.verified_user_outlined,
                          title: 'Permissions & privacy',
                          tint: const Color(0xFFE4F2E9),
                          onTint: const Color(0xFF3F823B),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PermissionsPage(phonePatterns: phonePatterns),
                            ),
                          ),
                        ),
                        if (phonePatterns != null)
                          _row(
                            icon: Icons.phone_android_rounded,
                            title: 'My phone patterns',
                            tint: const Color(0xFFE4F2E9),
                            onTint: const Color(0xFF3F823B),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PhonePatternsPage(
                                  phonePatterns: phonePatterns!,
                                  profileController: profileController,
                                ),
                              ),
                            ),
                          ),
                        _row(
                          icon: Icons.file_download_outlined,
                          title: 'Export reflections & data',
                          tint: const Color(0xFFE4F2E9),
                          onTint: const Color(0xFF3F823B),
                          onTap: () => _showExportSheet(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SECTION: PRACTICE.
                    //
                    // The baseline block keeps its progress and its button. Both
                    // used to live inside a card of plain rows, and the
                    // full-width button inside a list is what made that card read
                    // as a different app bolted on. Here it leads its own group,
                    // so being different is what the group is for.
                    _group(
                      label: 'Practice',
                      trailingLabel: profile.baselineComplete
                          ? 'Baseline complete'
                          : '$completeCount of 4',
                      rows: [
                        _BaselineRow(
                          completeCount: completeCount,
                          isComplete: profile.baselineComplete,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => BaselineQuizPage(
                                profileController: profileController,
                                safetyController: safetyController,
                              ),
                            ),
                          ),
                        ),
                        _row(
                          icon: Icons.local_library_outlined,
                          title: 'Activity library',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ActivityLibraryPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SECTION: HOW IT WORKS.
                    //
                    // Its own group rather than another row. "How Solace decides"
                    // is the thing that makes this app different from a mood
                    // tracker with a checklist, and it explains why a particular
                    // suggestion is on screen right now — which is a question
                    // people bring to this page. Buried between the baseline and
                    // the activity library it read as one more entry.
                    _group(
                      label: 'How it works',
                      rows: [
                        _row(
                          icon: Icons.insights_outlined,
                          title: 'How Solace decides',
                          value:
                              '${suggestionController.history.length} shown',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ProfileInsightsPage(
                                profile: BehavioralProfile.compute(
                                  profile: profileController.profile,
                                  sessions: sessionController.sessions,
                                  suggestionHistory:
                                      suggestionController.history,
                                  library: suggestionController.library,
                                  context: buildRecommendationContext(
                                    profile: profileController.profile,
                                    sessions: sessionController.sessions,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SECTION: ABOUT.
                    //
                    // Separate from the groups above and visually quieter, on
                    // purpose. A legal page wearing the same card as "Permissions
                    // & privacy" would make both feel like neither. No tinted
                    // icons, no trailing values: nothing here is state.
                    _group(
                      label: 'About',
                      rows: [
                        _row(
                          icon: Icons.info_outline_rounded,
                          title: 'About Solace',
                          value: AboutSolacePage.version,
                          tint: Colors.transparent,
                          onTint: const Color(0xFFA2988A),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AboutSolacePage(),
                            ),
                          ),
                        ),
                        _row(
                          icon: Icons.description_outlined,
                          title: 'Terms & privacy',
                          tint: Colors.transparent,
                          onTint: const Color(0xFFA2988A),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const TermsAndPrivacyPage(),
                            ),
                          ),
                        ),
                        _row(
                          icon: Icons.help_outline_rounded,
                          title: 'Frequently asked',
                          tint: Colors.transparent,
                          onTint: const Color(0xFFA2988A),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const FaqPage(),
                            ),
                          ),
                        ),
                      ],
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

  /// A section heading: small, tracked-out, and deliberately quiet.
  ///
  /// The group beneath it carries the meaning, so this only has to say what kind
  /// of group it is.
  static const _sectionLabelStyle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.3,
    color: Color(0xFFBCAC8E),
  );

  /// A grouped list of rows: one quiet surface, dividers inset to the label.
  ///
  /// Replaces the old arrangement of large rounded cards each holding its own
  /// stack of rows. Three identical cards told the reader nothing about what was
  /// in them, and every card's shadow had to compete with every other card's
  /// shadow. One surface per group, and the heading above it does the labelling,
  /// is both calmer and shorter.
  static Widget _group({
    required String label,
    required List<Widget> rows,
    String? trailingLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label.toUpperCase(), style: _sectionLabelStyle),
              if (trailingLabel != null)
                Text(
                  trailingLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFA79B87),
                  ),
                ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF5EFE1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D785C28),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  // Inset past the icon, so the rule groups the labels instead
                  // of slicing the surface into bands.
                  const Padding(
                    padding: EdgeInsets.only(left: 59),
                    child: SizedBox(
                      height: 1,
                      child: ColoredBox(color: Color(0xFFF4EEE1)),
                    ),
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// A single row in a [_group].
  ///
  /// Takes a [value] rather than a subtitle. A subtitle is only worth its height
  /// when it says something the title does not, and most of the old ones did
  /// not: "Activity library" followed by "Browse reviewed lifestyle starter
  /// set" is the same sentence twice. A trailing value — "2 saved", "3 of 4" —
  /// reads unambiguously as state, which is what most of them were trying to be.
  static Widget _row({
    required IconData icon,
    required String title,
    String? value,
    VoidCallback? onTap,
    Color tint = const Color(0xFFFFF3DC),
    Color onTint = const Color(0xFFC08A1E),
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: onTint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: Color(0xFF3B3327),
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9C9083),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
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
          decoration: BoxDecoration(
            color: SolaceColors.from(ctx).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [
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

  // 4. Permissions & data now lives on its own page, because it reports real
  // platform state rather than decoration. See PermissionsPage.

  // 5. App Settings Sheet
  static void _showAppSettingsSheet(
    BuildContext context,
    ProfileController controller,
  ) {
    _showModalSheet(
      context: context,
      child: _AppSettingsForm(controller: controller),
    );
  }

  // 6. Edit Profile Sheet
  static void _showEditProfileSheet(
    BuildContext context,
    ProfileController controller,
  ) {
    _showModalSheet(
      context: context,
      child: _EditProfileForm(controller: controller),
    );
  }

  /// Hands the call-first contact to the platform dialer.
  ///
  /// The dialer is pre-filled only; the user still confirms the call.
  Future<void> _callIceContact(
    BuildContext context,
    EmergencyContact contact,
  ) async {
    final opened = await const DialerService().openDialer(contact.phone);
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('No dialer available on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Formats the first-run date as a gentle membership line.
  static String _memberSinceLabel(DateTime? firstRunAt) {
    if (firstRunAt == null) return 'Welcome to Solace';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return 'Member since ${months[firstRunAt.month - 1]} ${firstRunAt.year}';
  }

  /// Opens the system photo picker and stores the chosen image.
  ///
  /// The picked file is copied into app-private storage so it survives the
  /// picker's temporary cache being cleared.
  Future<void> _pickAvatar(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      final saved = await _persistAvatar(File(picked.path));
      await profileController.saveIdentity(avatarPath: saved);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that photo. Try again.')),
      );
    }
  }

  /// Copies the picked image into app-private storage and returns its path.
  static Future<String> _persistAvatar(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = File(
      '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}'
      '${_extensionOf(source.path)}',
    );
    await source.copy(target.path);
    return target.path;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '.jpg';
    return path.substring(dot);
  }
}

/// Name editor that persists through the profile controller.
class _EditProfileForm extends StatefulWidget {
  const _EditProfileForm({required this.controller});

  final ProfileController controller;

  @override
  State<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<_EditProfileForm> {
  late final TextEditingController _name;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.controller.profile.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final name = _name.text.trim();
    await widget.controller.saveIdentity(
      displayName: name.isEmpty ? null : name,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Preferred Name',
            hintText: 'Leave blank to stay anonymous',
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
            onPressed: _saving ? null : _save,
            child: const Text(
              'Save Profile',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

/// Real app settings: haptics, ambient audio and palette, all persisted.
class _AppSettingsForm extends StatefulWidget {
  const _AppSettingsForm({required this.controller});

  final ProfileController controller;

  @override
  State<_AppSettingsForm> createState() => _AppSettingsFormState();
}

class _AppSettingsFormState extends State<_AppSettingsForm> {
  ProfileController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // This sheet is pushed on the root navigator, so it is not rebuilt by the
    // ProfilePage's AnimatedBuilder. Subscribe directly so every control shows
    // its new value immediately instead of only after the sheet is reopened.
    _controller.addListener(_onProfileChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyReminder());
  }

  @override
  void dispose() {
    _controller.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setHaptics(bool enabled) async {
    // Persist first so the preference always applies, then preview the change
    // when switching on. Turning haptics off stays silent by definition.
    await _controller.setHapticsEnabled(enabled);
    if (enabled) {
      unawaited(_previewHaptic());
    }
  }

  Future<void> _setAmbientAudio(bool enabled) async {
    await _controller.setAmbientAudioEnabled(enabled);
    if (enabled) {
      await AmbientAudioService.instance.play(SoundscapeMode.solfeggio);
    } else {
      await AmbientAudioService.instance.stop();
    }
  }

  Future<void> _setPalette(SolacePaletteId palette) async {
    await _controller.setPaletteId(palette.id);
    unawaited(_previewHaptic());
  }

  /// Enables the daily reminder, requesting the permissions it needs.
  ///
  /// The switch only stays on when a notification is genuinely registered, and
  /// an inexact schedule is disclosed rather than presented as on time.
  Future<void> _setReminder(bool enabled) async {
    final service = CheckInReminderService.instance;

    if (!enabled) {
      await _controller.setReminderEnabled(false);
      await service.cancel();
      return;
    }

    final granted = await service.requestPermission();
    if (!granted) {
      await _controller.setReminderEnabled(false);
      await service.cancel();
      if (!mounted) return;
      _notify(
        'Notifications are off for Solace. You can allow them in '
        'system settings.',
      );
      return;
    }

    // Ask for notifications, then schedule. No exact-alarm request: this is a
    // gentle nudge, so a few minutes of drift is fine.
    final result = await service.scheduleDaily(
      minutesPastMidnight: _controller.profile.reminderMinutes,
    );
    final scheduled = result.isScheduled;
    await _controller.setReminderEnabled(scheduled);

    if (!mounted || scheduled) return;
    _notify(
      result.outcome == ReminderScheduleOutcome.notificationsDisabled
          ? 'Notifications are off for Solace, so no reminder was set.'
          : 'The reminder could not be set. ${result.error ?? ''}'.trim(),
    );
  }

  /// Confirms delivery on the spot, without waiting for the chosen time.
  Future<void> _sendTestReminder() async {
    final sent = await CheckInReminderService.instance.showTestNotification();
    if (!mounted) return;
    _notify(
      sent
          ? 'Test reminder sent.'
          : 'Notifications are off for Solace, so nothing was sent.',
    );
  }

  /// Re-asserts the schedule on open, so the row can state the truth rather
  /// than trusting a stored preference Android may have quietly dropped.
  Future<void> _verifyReminder() async {
    if (!_controller.profile.reminderEnabled) return;

    final result = await CheckInReminderService.instance.scheduleDaily(
      minutesPastMidnight: _controller.profile.reminderMinutes,
    );
    if (!result.isScheduled) {
      // Could not be re-registered, so stop claiming it is set.
      await _controller.setReminderEnabled(false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Lets the user pick the reminder time and reschedules if it is on.
  Future<void> _pickReminderTime() async {
    final profile = _controller.profile;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (profile.reminderMinutes ~/ 60) % 24,
        minute: profile.reminderMinutes % 60,
      ),
      helpText: 'Check-in reminder time',
    );
    if (picked == null) return;

    final minutes = picked.hour * 60 + picked.minute;
    await _controller.setReminderMinutes(minutes);
    if (!_controller.profile.reminderEnabled) return;

    await CheckInReminderService.instance.scheduleDaily(
      minutesPastMidnight: minutes,
    );
  }

  /// Turns idea nudges on, asking for notification permission first. The switch
  /// only stays on if Android actually allows them. Scheduling follows from the
  /// profile change, so there is nothing to schedule here.
  Future<void> _setIdeaPush(bool enabled) async {
    if (enabled && !await CheckInReminderService.instance.requestPermission()) {
      await _controller.setIdeaPushEnabled(false);
      if (!mounted) return;
      _notify(
        'Notifications are off for Solace. You can allow them in system '
        'settings.',
      );
      return;
    }
    await _controller.setIdeaPushEnabled(enabled);
  }

  Future<void> _pickQuietTime({required bool start}) async {
    final profile = _controller.profile;
    final current = start ? profile.quietStartMinutes : profile.quietEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: start ? 'Quiet hours begin' : 'Quiet hours end',
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await _controller.setQuietHours(
      startMinutes: start ? minutes : null,
      endMinutes: start ? null : minutes,
    );
  }

  /// Plays a short haptic cue, ignoring platforms that do not support it.
  ///
  /// Haptics are best effort: a missing or slow channel must never block a
  /// real setting change, so callers do not await this.
  static Future<void> _previewHaptic() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Haptics are unavailable here; the preference still applies.
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _controller.profile;
    final activePalette = SolacePaletteId.fromId(profile.paletteId);
    final reminderTimeLabel = TimeOfDay(
      hour: (profile.reminderMinutes ~/ 60) % 24,
      minute: profile.reminderMinutes % 60,
    ).format(context);
    // The next time it will actually fire, computed rather than guessed.
    final nextFireDate = MaterialLocalizations.of(
      context,
    ).formatMediumDate(ReminderSchedule.nextOccurrence(profile.reminderMinutes));
    final nextFireLabel = '$nextFireDate at $reminderTimeLabel';

    return Column(
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
        _SettingToggle(
          key: const ValueKey('toggle-haptics'),
          title: 'Gentle Haptics',
          subtitle: 'Subtle vibrational cues on taps and sliders',
          value: profile.hapticsEnabled,
          onChanged: _setHaptics,
        ),
        _SettingToggle(
          key: const ValueKey('toggle-ambient-audio'),
          title: 'Soft Ambient Breath Audio',
          subtitle: 'Plays a calm soundscape during grounding pauses',
          value: profile.ambientAudioEnabled,
          onChanged: _setAmbientAudio,
        ),
        _ReminderSetting(
          key: const ValueKey('setting-reminder'),
          enabled: profile.reminderEnabled,
          timeLabel: reminderTimeLabel,
          nextFireLabel: nextFireLabel,
          onToggle: _setReminder,
          onPickTime: _pickReminderTime,
          onSendTest: _sendTestReminder,
        ),
        _SettingToggle(
          key: const ValueKey('toggle-idea-push'),
          title: 'Nudge me about ideas',
          subtitle: 'A quiet note that a gentle idea is waiting',
          value: profile.ideaPushEnabled,
          onChanged: _setIdeaPush,
        ),
        if (profile.ideaPushEnabled) ...[
          _SettingToggle(
            key: const ValueKey('toggle-quiet-hours'),
            title: 'Quiet hours',
            subtitle: 'No idea nudges while you sleep. Your check-in reminder '
                'still arrives when you set it.',
            value: profile.quietHoursEnabled,
            onChanged: (on) => _controller.setQuietHours(enabled: on),
          ),
          if (profile.quietHoursEnabled)
            Row(
              children: [
                TextButton(
                  key: const ValueKey('quiet-start'),
                  onPressed: () => _pickQuietTime(start: true),
                  child: Text(
                    'From ${TimeOfDay(hour: profile.quietStartMinutes ~/ 60, minute: profile.quietStartMinutes % 60).format(context)}',
                  ),
                ),
                TextButton(
                  key: const ValueKey('quiet-end'),
                  onPressed: () => _pickQuietTime(start: false),
                  child: Text(
                    'Until ${TimeOfDay(hour: profile.quietEndMinutes ~/ 60, minute: profile.quietEndMinutes % 60).format(context)}',
                  ),
                ),
              ],
            ),
        ],
        SleepHoursSettings(controller: _controller),
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
            for (final palette in SolacePaletteId.values) ...[
              if (palette != SolacePaletteId.values.first)
                const SizedBox(width: 8),
              _PaletteChip(
                key: ValueKey('palette-${palette.id}'),
                palette: palette,
                selected: palette == activePalette,
                onTap: () => _setPalette(palette),
              ),
            ],
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
              'Done',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

/// Settings row with a working switch.
class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
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
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Daily check-in reminder: a switch, a tappable time, and an honest status.
///
/// The status line states the real next fire time and offers a way to confirm
/// delivery immediately.
class _ReminderSetting extends StatelessWidget {
  const _ReminderSetting({
    required this.enabled,
    required this.timeLabel,
    required this.nextFireLabel,
    required this.onToggle,
    required this.onPickTime,
    required this.onSendTest,
    super.key,
  });

  final bool enabled;
  final String timeLabel;
  final String nextFireLabel;

  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;
  final VoidCallback onSendTest;

  @override
  Widget build(BuildContext context) {
    final accent = enabled
        ? const Color(0xFFB57A12)
        : const Color(0xFF887D6E);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Daily check-in reminder',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B3327),
                  ),
                ),
              ),
              Switch(
                value: enabled,
                activeColor: const Color(0xFFFFB534),
                onChanged: onToggle,
              ),
            ],
          ),
          GestureDetector(
            onTap: onPickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFFFFF9EE)
                    : const Color(0xFFF4F1E7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: enabled
                      ? const Color(0xFFFFB534)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 15, color: accent),
                  const SizedBox(width: 7),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            enabled ? 'Next reminder: $nextFireLabel.' : _offCopy,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: Color(0xFF93887A),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 2),
            TextButton(
              key: const ValueKey('send-test-reminder'),
              onPressed: onSendTest,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF96620C),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Send a test reminder',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _offCopy = 'Turn on for a single gentle reminder each day.';
}

/// Selectable palette chip showing a swatch of the palette itself.
class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.palette,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final SolacePaletteId palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.of(palette);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF9EE) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFB534)
                  : const Color(0xFFF2ECDD),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.amber, colors.coral],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  palette.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? const Color(0xFFB57A12)
                        : const Color(0xFF887D6E),
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

/// Compact one-tap call button for the call-first contact.
class _IceCallButton extends StatelessWidget {
  const _IceCallButton({required this.contact, required this.onCall});

  final EmergencyContact contact;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCall,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE4D6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.call_rounded, size: 15, color: Color(0xFFD2603A)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                contact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB4522C),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the user's chosen profile photo, falling back to the default icon.
class _AvatarContent extends StatelessWidget {
  const _AvatarContent({required this.avatarPath});

  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    final path = avatarPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  static Widget _fallback() {
    return const Center(
      child: Icon(
        Icons.face_3_rounded,
        size: 42,
        color: Color(0xFF7A5832),
      ),
    );
  }
}
