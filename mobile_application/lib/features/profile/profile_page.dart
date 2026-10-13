import '../chat/chat_controller.dart';
import '../memory/companion_memory_context.dart';
import 'everything_kept_page.dart';
import '../memory/moments_controller.dart';
import '../memory/what_sol_remembers_page.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/emergency_contact.dart';
import '../../core/models/safety_assessment.dart';
import '../../core/models/therapist_contact.dart';
import '../../core/models/habit_reminder.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
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
import 'country_picker.dart';
import 'sleep_hours_settings.dart';
import 'therapist_controller.dart';
import 'habit_controller.dart';

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
    this.moments,
    this.memory,
    this.chatController,
    this.therapistController,
    this.habitController,
    this.extraEventTags,
    super.key,
  });

  final ProfileController profileController;
  final SafetyController safetyController;
  final SuggestionController suggestionController;
  final SessionController sessionController;

  /// The opt-in phone patterns control, shown on the permissions page.
  final PhonePatternsController? phonePatterns;

  /// With [memory], gives the "What Sol remembers" row.
  final MomentsController? moments;
  final CompanionMemoryContext? memory;
  final ChatController? chatController;

  /// The user's stored therapist contact, if any.
  final TherapistController? therapistController;

  /// The user's habit reminders, if configured.
  final HabitController? habitController;

  /// Themes the person chose recently, so the engine's described state matches
  /// what it is actually being fed.
  final List<String> Function()? extraEventTags;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        profileController,
        sessionController,
        if (therapistController != null) therapistController!,
        if (habitController != null) habitController!,
      ]),
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
            child: ListView(
              // Room for the floating pill, which overlays the page.
              // Horizontal inset matches the Today page so cards line up
              // across the app's pages.
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 120),
              children: [
                _identityHeader(
                  context,
                  displayName: displayName,
                  avatarPath: profile.avatarPath,
                  firstRunAt: profile.firstRunAt,
                ),

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
                            colors: [Color(0xFFFFF4EE), Color(0xFFFFEEE5)],
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                      value: therapistController?.contact?.name ?? 'None yet',
                      onTap: () =>
                          _showTherapistSheet(context, therapistController),
                    ),
                    _row(
                      icon: Icons.checklist_rounded,
                      title: 'Habits & hobbies',
                      value:
                          habitController == null ||
                              habitController!.reminders.isEmpty
                          ? 'None set'
                          : '${habitController!.reminders.length}',
                      onTap: () => _showHabitsSheet(context, habitController),
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
                          builder: (_) =>
                              PermissionsPage(phonePatterns: phonePatterns),
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
                      icon: Icons.inventory_2_outlined,
                      title: 'Everything Solace keeps',
                      tint: const Color(0xFFE4F2E9),
                      onTint: const Color(0xFF3F823B),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EverythingKeptPage(
                            sessionController: sessionController,
                            profileController: profileController,
                            chatController: chatController,
                            moments: moments,
                            memory: memory,
                            phonePatterns: phonePatterns,
                          ),
                        ),
                      ),
                    ),
                    if (moments != null && memory != null)
                      _row(
                        icon: Icons.bookmark_added_outlined,
                        title: 'What Sol remembers',
                        tint: const Color(0xFFE4F2E9),
                        onTint: const Color(0xFF3F823B),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WhatSolRemembersPage(
                              moments: moments!,
                              memory: memory!,
                              consent: memory!.consent,
                              profileController: profileController,
                              chat: chatController,
                            ),
                          ),
                        ),
                      ),
                    _row(
                      icon: Icons.file_download_outlined,
                      title: 'Export reflections & data',
                      value: 'Coming soon',
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
                          builder: (_) => ActivityLibraryPage(
                            suggestionController: suggestionController,
                          ),
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
                      value: '${suggestionController.history.length} shown',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfileInsightsPage(
                            signals: DecisionSignals(
                              phonePatterns: switch (phonePatterns?.status) {
                                PhonePatternsStatus.on => PhoneSignal.on,
                                PhonePatternsStatus.needsAndroidAccess =>
                                  PhoneSignal.needsAccess,
                                _ => PhoneSignal.off,
                              },
                              keptMoments: moments?.confirmed.length ?? 0,
                              snippetShared: memory?.snippetOn ?? false,
                              momentsShared: memory?.momentsOn ?? false,
                            ),
                            profile: BehavioralProfile.compute(
                              profile: profileController.profile,
                              sessions: sessionController.sessions,
                              suggestionHistory: suggestionController.history,
                              library: suggestionController.library,
                              context: buildRecommendationContext(
                                profile: profileController.profile,
                                sessions: sessionController.sessions,
                                extraTags: extraEventTags?.call() ?? const [],
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
              // Scrolls: a taller form (more settings) must never overflow a phone-sized sheet.
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        );
      },
    );
  }

  // 1. Habits & Hobbies Sheet
  static void _showHabitsSheet(
    BuildContext context,
    HabitController? controller,
  ) {
    if (controller == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HabitsSheetContent(controller: controller),
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
            title: 'Formatted Reflection Journal',
            desc:
                'Clean, printable layout with emotion cadence & baseline history.',
            icon: Icons.picture_as_pdf_outlined,
            format: 'PDF',
          ),
          const SizedBox(height: 10),
          _exportOptionCard(
            title: 'Structured Local Archive',
            desc:
                'Complete database export for offline archival, analysis, or migration.',
            icon: Icons.data_object_rounded,
            format: 'JSON',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9EE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF7EBCE)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Color(0xFFB57A12)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Direct PDF and JSON file generation is in active development. Your entries remain safely encrypted on this device.',
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
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8E0D0),
                foregroundColor: const Color(0xFF93887A),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: null,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text(
                'Generate Export File · Coming soon',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF93887A),
                ),
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
    required String format,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2ECDD), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: const Color(0xFFB57A12)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3B3327),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F1E5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        format,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF887D6E),
                        ),
                      ),
                    ),
                  ],
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

  // 3. Therapist Collaboration Sheet
  static void _showTherapistSheet(
    BuildContext context,
    TherapistController? controller,
  ) {
    if (controller == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TherapistSheetContent(controller: controller),
    );
  }

  // 4. Permissions & data now lives on its own page, because it reports real
  // platform state rather than decoration. See PermissionsPage.

  /// The identity header: a cover banner, the portrait breaking its lower
  /// edge and the name beneath — the shape a social profile page uses,
  /// because that is where a person's own details are expected to live.
  ///
  /// The settings gear rides the cover, where a profile page keeps its
  /// actions, and it is still the only route to app settings.
  Widget _identityHeader(
    BuildContext context, {
    required String displayName,
    required String? avatarPath,
    required DateTime? firstRunAt,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 124,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFEFD6),
                        Color(0xFFFEE0B4),
                        Color(0xFFFFCF96),
                      ],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2ED69628),
                        blurRadius: 22,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  // The discs inside are clipped to the cover's corners.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Stack(
                      children: [
                        Positioned(
                          top: -52,
                          right: -30,
                          child: Container(
                            width: 146,
                            height: 146,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.30),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -66,
                          left: 78,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0x26FF9A6A),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 22,
                          right: 86,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                // Its own Material so the splash lands on the cover, not on
                // the page underneath it.
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        _showAppSettingsSheet(context, profileController),
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xFFF2ECDD)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A78501E),
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
                ),
              ),
              // Portrait: white ring, warm gradient rim, photo inside. It
              // sits on the cover's edge the way a profile picture does.
              Positioned(
                left: 16,
                bottom: -36,
                child: GestureDetector(
                  onTap: () => _pickAvatar(context),
                  child: Container(
                    width: 90,
                    height: 90,
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x3378501E),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFD88A),
                            Color(0xFFFFB534),
                            Color(0xFFFF9A6A),
                          ],
                        ),
                      ),
                      child: ClipOval(
                        child: Container(
                          color: const Color(0xFFFFF6E4),
                          child: _AvatarContent(avatarPath: avatarPath),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Room for the portrait hanging below the cover.
        const SizedBox(height: 46),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF332C21),
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showEditProfileSheet(context, profileController),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFEFE7D6)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1278501E),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: Color(0xFF8E8272),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6E6152),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8EA),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: const Color(0x33FFB534)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                firstRunAt == null
                    ? Icons.waving_hand_rounded
                    : Icons.event_available_rounded,
                size: 13,
                color: const Color(0xFFB98A2E),
              ),
              const SizedBox(width: 6),
              Text(
                _memberSinceLabel(firstRunAt),
                style: const TextStyle(
                  fontSize: 12.3,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A7355),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

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
              borderSide: const BorderSide(
                color: Color(0xFFFFB534),
                width: 1.8,
              ),
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
    final nextFireDate = MaterialLocalizations.of(context).formatMediumDate(
      ReminderSchedule.nextOccurrence(profile.reminderMinutes),
    );
    final nextFireLabel = '$nextFireDate at $reminderTimeLabel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconTile(icon: Icons.tune_rounded, color: kitAmber, size: 44),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: kitInk,
                    ),
                  ),
                  Text(
                    'Make Solace feel like yours',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: kitMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const KitLabel('FEEL'),
        _SettingsGroup(
          children: [
            _SettingToggle(
              key: const ValueKey('toggle-haptics'),
              icon: Icons.vibration_rounded,
              color: kitAmber,
              title: 'Gentle Haptics',
              subtitle: 'Subtle vibrational cues on taps and sliders',
              value: profile.hapticsEnabled,
              onChanged: _setHaptics,
            ),
            _SettingToggle(
              key: const ValueKey('toggle-ambient-audio'),
              icon: Icons.graphic_eq_rounded,
              color: const Color(0xFF6E73C8),
              title: 'Soft Ambient Breath Audio',
              subtitle: 'A calm soundscape during grounding pauses',
              value: profile.ambientAudioEnabled,
              onChanged: _setAmbientAudio,
            ),
          ],
        ),
        const KitLabel('REMINDERS'),
        _SettingsGroup(
          children: [
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
              icon: Icons.notifications_none_rounded,
              color: const Color(0xFF4F9D76),
              title: 'Nudge me about ideas',
              subtitle: 'A quiet note that a gentle idea is waiting',
              value: profile.ideaPushEnabled,
              onChanged: _setIdeaPush,
            ),
            if (profile.ideaPushEnabled) ...[
              _SettingToggle(
                key: const ValueKey('toggle-quiet-hours'),
                icon: Icons.bedtime_outlined,
                color: const Color(0xFF6E73C8),
                title: 'Quiet hours',
                subtitle:
                    'No idea nudges while you sleep. Your check-in reminder '
                    'still arrives when you set it.',
                value: profile.quietHoursEnabled,
                onChanged: (on) => _controller.setQuietHours(enabled: on),
              ),
              if (profile.quietHoursEnabled)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TimePill(
                      key: const ValueKey('quiet-start'),
                      label:
                          'From ${TimeOfDay(hour: profile.quietStartMinutes ~/ 60, minute: profile.quietStartMinutes % 60).format(context)}',
                      onTap: () => _pickQuietTime(start: true),
                    ),
                    _TimePill(
                      key: const ValueKey('quiet-end'),
                      label:
                          'Until ${TimeOfDay(hour: profile.quietEndMinutes ~/ 60, minute: profile.quietEndMinutes % 60).format(context)}',
                      onTap: () => _pickQuietTime(start: false),
                    ),
                  ],
                ),
            ],
          ],
        ),
        const KitLabel('YOUR DAY'),
        _SettingsGroup(children: [SleepHoursSettings(controller: _controller)]),
        const KitLabel('WHERE YOU ARE BASED'),
        _SettingsGroup(children: [CountryPicker(controller: _controller)]),
        const KitLabel('LOOK'),
        _SettingsGroup(
          children: [
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
          ],
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB534),
              foregroundColor: const Color(0xFF3D2E14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

/// A white card that groups related settings, with hairlines between rows.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return KitCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: kitLine),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small tappable time chip.
class _TimePill extends StatelessWidget {
  const _TimePill({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF3DC),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: kitAmber),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A6A1C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings row with an icon tile and a working switch.
class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconTile(icon: icon, color: color, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kitInk,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: kitMuted,
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
    final accent = enabled ? const Color(0xFFB57A12) : const Color(0xFF887D6E);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(
                icon: Icons.alarm_rounded,
                color: enabled ? kitAmber : kitMuted,
                size: 38,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Daily check-in reminder',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: kitInk,
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
          Padding(
            padding: const EdgeInsets.only(left: 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onPickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
      child: Semantics(
        button: true,
        selected: selected,
        label: palette.label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFFF9EE) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? const Color(0xFFFFB534) : kitLine,
                width: selected ? 1.8 : 1,
              ),
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colors.amber, colors.coral],
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  palette.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? kitInk : kitMuted,
                  ),
                ),
              ],
            ),
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
      // A 512px photo squeezed into a 68px box was resampled with the default
      // low-quality filter, so its pixels shifted at every sub-pixel scroll
      // offset. High-quality filtering keeps the downscale stable, and the
      // boundary lets the page scroll without re-rasterising the photo.
      return RepaintBoundary(
        child: Image.file(
          File(path),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  static Widget _fallback() {
    return const Center(
      child: Icon(Icons.face_3_rounded, size: 42, color: Color(0xFF7A5832)),
    );
  }
}

// ---------------------------------------------------------------------------
// Therapist Collaboration — real sheet with contact CRUD, call, email
// ---------------------------------------------------------------------------

class _TherapistSheetContent extends StatefulWidget {
  const _TherapistSheetContent({required this.controller});

  final TherapistController controller;

  @override
  State<_TherapistSheetContent> createState() => _TherapistSheetContentState();
}

class _TherapistSheetContentState extends State<_TherapistSheetContent> {
  bool _editing = false;
  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final contact = widget.controller.contact;
    _name = TextEditingController(text: contact?.name ?? '');
    _phone = TextEditingController(text: contact?.phone ?? '');
    _email = TextEditingController(text: contact?.email ?? '');
    // Open in edit mode if no contact exists yet.
    _editing = contact == null;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (_saving) return;
    setState(() => _saving = true);

    await widget.controller.save(
      TherapistContact(
        name: name,
        phone: _phone.text.trim(),
        email: _email.text.trim(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
  }

  Future<void> _remove() async {
    await widget.controller.remove();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _call(String phone) {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    launchUrl(Uri(scheme: 'tel', path: number));
  }

  void _sendEmail(String email) {
    if (email.isEmpty) return;
    launchUrl(Uri(scheme: 'mailto', path: email));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SolaceColors.from(context).surface,
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
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
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
          // Header
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
                      'Store your therapist\u2019s contact for quick access',
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
          if (_editing) _buildForm() else _buildContactCard(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(_name, 'Name', TextInputType.name, TextCapitalization.words),
        const SizedBox(height: 12),
        _field(
          _phone,
          'Phone number',
          TextInputType.phone,
          TextCapitalization.none,
        ),
        const SizedBox(height: 12),
        _field(
          _email,
          'Email address',
          TextInputType.emailAddress,
          TextCapitalization.none,
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
            child: Text(
              widget.controller.hasContact ? 'Update Contact' : 'Save Contact',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        if (widget.controller.hasContact) ...[
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _editing = false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF93887A),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    TextInputType keyboard,
    TextCapitalization capitalization,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: capitalization,
      decoration: InputDecoration(
        labelText: label,
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
    );
  }

  Widget _buildContactCard() {
    final contact = widget.controller.contact;
    if (contact == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contact card
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
                child: Text(
                  contact.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD2603A),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    if (contact.hasPhone || contact.hasEmail)
                      Text(
                        [
                          if (contact.hasPhone) contact.phone,
                          if (contact.hasEmail) contact.email,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF93887A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: const Color(0xFFB57A12),
                onPressed: () => setState(() => _editing = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Action buttons
        Row(
          children: [
            if (contact.hasPhone)
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3F823B),
                      side: const BorderSide(color: Color(0xFFD4E8D4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _call(contact.phone),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text(
                      'Call',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            if (contact.hasPhone && contact.hasEmail) const SizedBox(width: 10),
            if (contact.hasEmail)
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB57A12),
                      side: const BorderSide(color: Color(0xFFF2ECDD)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _sendEmail(contact.email),
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text(
                      'Email',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Send summary — coming soon
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE8E0D0),
              foregroundColor: const Color(0xFF93887A),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: null,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text(
              'Send 1-Page Summary Brief · Coming soon',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Remove contact
        Center(
          child: TextButton(
            onPressed: _remove,
            child: const Text(
              'Remove therapist',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB4522C),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Habits & Hobbies — real sheet with custom reminders & notification scheduling
// ---------------------------------------------------------------------------

class _HabitsSheetContent extends StatefulWidget {
  const _HabitsSheetContent({required this.controller});

  final HabitController controller;

  @override
  State<_HabitsSheetContent> createState() => _HabitsSheetContentState();
}

class _HabitsSheetContentState extends State<_HabitsSheetContent> {
  bool _editing = false;
  String? _editingId;
  late TextEditingController _title;
  late TextEditingController _description;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  Set<int> _selectedDays = {1, 2, 3, 4, 5, 6, 7};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _description = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _startAdd() {
    setState(() {
      _editingId = null;
      _title.text = '';
      _description.text = '';
      _selectedTime = const TimeOfDay(hour: 8, minute: 0);
      _selectedDays = {1, 2, 3, 4, 5, 6, 7};
      _editing = true;
    });
  }

  void _startEdit(HabitReminder reminder) {
    setState(() {
      _editingId = reminder.id;
      _title.text = reminder.title;
      _description.text = reminder.description;
      _selectedTime = TimeOfDay(hour: reminder.hour, minute: reminder.minute);
      _selectedDays = Set<int>.from(reminder.days);
      _editing = true;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editingId = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    if (_selectedDays.isEmpty) return;
    if (_saving) return;

    setState(() => _saving = true);

    if (_editingId != null) {
      final existing = widget.controller.reminders
          .where((r) => r.id == _editingId)
          .firstOrNull;
      final updated = HabitReminder(
        id: _editingId!,
        title: title,
        description: _description.text.trim(),
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        days: _selectedDays,
        enabled: existing?.enabled ?? true,
      );
      await widget.controller.update(updated);
    } else {
      final newReminder = HabitReminder(
        id: 'habit_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        description: _description.text.trim(),
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        days: _selectedDays,
        enabled: true,
      );
      await widget.controller.add(newReminder);
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
      _editingId = null;
    });
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final m = time.minute.toString().padLeft(2, '0');
    final ampm = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final reminders = widget.controller.reminders;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: SolaceColors.from(context).surface,
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
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 12,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
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
                // Header
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
                            'Habits & hobbies',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF3B3327),
                            ),
                          ),
                          Text(
                            'Gentle anchors · Set your own rhythm',
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
                const SizedBox(height: 14),

                // Philosophy banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9EE),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF7EBCE)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.spa_outlined,
                        size: 16,
                        color: Color(0xFFB57A12),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No streak counters or penalties. Solace simply sends a gentle nudge at the time you choose.',
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
                const SizedBox(height: 16),

                if (_editing)
                  _buildForm()
                else ...[
                  if (reminders.isEmpty)
                    _buildEmptyState()
                  else
                    ...reminders.map((r) => _buildReminderCard(r)),

                  const SizedBox(height: 14),
                  if (!_editing && widget.controller.canAddMore)
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB57A12),
                          side: const BorderSide(color: Color(0xFFF2ECDD)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _startAdd,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(
                          'Add habit or hobby',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF2ECDD)),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9EE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Color(0xFFB57A12),
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No reminders set yet',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3B3327),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add a gentle reminder for walking, reading, stretching, or any personal practice.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF93887A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(HabitReminder reminder) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: reminder.enabled
              ? const Color(0xFFF2ECDD)
              : const Color(0xFFECE7DB).withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: reminder.enabled
                        ? const Color(0xFF3B3327)
                        : const Color(0xFF93887A),
                  ),
                ),
                if (reminder.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    reminder.description,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: reminder.enabled
                          ? const Color(0xFF706454)
                          : const Color(0xFFAFA79D),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: reminder.enabled
                            ? const Color(0xFFFFF0D4)
                            : const Color(0xFFF5EFE3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        reminder.timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: reminder.enabled
                              ? const Color(0xFFB57A12)
                              : const Color(0xFF93887A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reminder.daysLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: reminder.enabled
                              ? const Color(0xFF93887A)
                              : const Color(0xFFB0A79B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: reminder.enabled,
            activeColor: const Color(0xFFFFB534),
            onChanged: (_) => widget.controller.toggleEnabled(reminder.id),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              size: 18,
              color: Color(0xFF93887A),
            ),
            onSelected: (val) {
              if (val == 'edit') {
                _startEdit(reminder);
              } else if (val == 'delete') {
                widget.controller.remove(reminder.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit', style: TextStyle(fontSize: 13)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete',
                  style: TextStyle(fontSize: 13, color: Color(0xFFB4522C)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _editingId != null ? 'Edit Reminder' : 'New Reminder',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF3B3327),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'What would you like to do?',
            hintText: 'e.g., Morning walk, evening reading',
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
              borderSide: const BorderSide(
                color: Color(0xFFFFB534),
                width: 1.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Notes or description (optional)',
            hintText: 'e.g., 15 minutes, leave phone in room',
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
              borderSide: const BorderSide(
                color: Color(0xFFFFB534),
                width: 1.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Time selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2D6C0)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 20,
                color: Color(0xFFB57A12),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reminder time',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93887A),
                      ),
                    ),
                    Text(
                      _formatTime(_selectedTime),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB57A12),
                  side: const BorderSide(color: Color(0xFFE2D6C0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _pickTime,
                child: const Text(
                  'Change',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Days of week selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'REPEAT DAYS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: Color(0xFFBCAC8E),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedDays.length == 7) {
                    _selectedDays = {};
                  } else {
                    _selectedDays = {1, 2, 3, 4, 5, 6, 7};
                  }
                });
              },
              child: Text(
                _selectedDays.length == 7 ? 'Clear all' : 'Every day',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB57A12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            final dayNumber = i + 1;
            final isSelected = _selectedDays.contains(dayNumber);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedDays.remove(dayNumber);
                  } else {
                    _selectedDays.add(dayNumber);
                  }
                });
              },
              child: Container(
                width: 42,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFB534) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFFB534)
                        : const Color(0xFFE2D6C0),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  dayNames[i],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? const Color(0xFF3D2E14)
                        : const Color(0xFF706454),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),

        // Action buttons
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
            onPressed: _selectedDays.isEmpty || _saving ? null : _save,
            child: Text(
              _editingId != null ? 'Update Reminder' : 'Set Reminder',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _cancelEdit,
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF93887A),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
