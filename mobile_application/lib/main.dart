import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/solace_palette.dart';
import 'data/contracts/onboarding_repository.dart';
import 'data/repositories/asset_activity_library_repository.dart';
import 'data/repositories/in_memory_profile_repository.dart';
import 'data/repositories/in_memory_safety_event_repository.dart';
import 'data/repositories/in_memory_suggestion_repository.dart';
import 'data/repositories/shared_preferences_break_annotation_repository.dart';
import 'data/repositories/shared_preferences_consent_repository.dart';
import 'data/repositories/shared_preferences_daily_features_repository.dart';
import 'data/repositories/shared_preferences_onboarding_repository.dart';
import 'data/repositories/shared_preferences_profile_repository.dart';
import 'data/repositories/shared_preferences_safety_event_repository.dart';
import 'data/repositories/shared_preferences_session_repository.dart';
import 'data/repositories/shared_preferences_suggestion_repository.dart';
import 'domain/rhythm/reminder_lapse_policy.dart';
import 'features/chat/chat_controller.dart';
import 'features/checkin/check_in_mode_page.dart';
import 'features/consent/consent_controller.dart';
import 'features/footprint/in_app_feature_recorder.dart';
import 'features/footprint/break_prompt_controller.dart';
import 'features/footprint/phone_patterns_controller.dart';
import 'features/footprint/usage_collection_runner.dart';
import 'features/footprint/usage_recorder.dart';
import 'features/onboarding/onboarding_gate.dart';
import 'features/profile/profile_controller.dart';
import 'features/profile/therapist_controller.dart';
import 'features/profile/habit_controller.dart';
import 'features/safety/safety_controller.dart';
import 'features/sessions/session_controller.dart';
import 'features/suggestions/suggestion_controller.dart';
import 'providers/mock/mock_providers.dart';
import 'providers/safety/keyword_safety_screener.dart';
import 'services/check_in_reminder_service.dart';
import 'services/check_in_widget_service.dart';
import 'core/models/memory_moment.dart';
import 'data/repositories/shared_preferences_moment_repository.dart';
import 'domain/memory/moment_extractor.dart';
import 'domain/memory/server_moment_extractor.dart';
import 'features/memory/companion_memory_context.dart';
import 'features/memory/moments_controller.dart';
import 'services/companion_websocket_service.dart';
import 'services/usage_collector_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final sessionController = SessionController(
    repository: SharedPreferencesSessionRepository(preferences),
    emotionAnalyzer: const MockEmotionAnalyzer(),
  );
  await sessionController.load();
  final safetyController = SafetyController(
    screener: const KeywordSafetyScreener(),
    repository: SharedPreferencesSafetyEventRepository(preferences),
  );
  await safetyController.load();
  final profileController = ProfileController(
    repository: SharedPreferencesProfileRepository(preferences),
  );
  await profileController.load();
  await profileController.ensureFirstRun();

  final therapistController = TherapistController(preferences: preferences);
  await therapistController.load();

  final habitController = HabitController(preferences: preferences);
  await habitController.load();

  // Restore the daily reminder in case the OS dropped it (for example after a
  // reboot or an app update). If the user has been away a long time, stop
  // nudging them instead: the reminder only ever gets quieter, never louder.
  await CheckInReminderService.instance.initialize();
  final daysSinceLastCheckIn = ReminderLapsePolicy.daysSince(
    sessionController.lastCheckInAt,
  );
  if (ReminderLapsePolicy.shouldPauseReminder(daysSinceLastCheckIn)) {
    if (profileController.profile.reminderEnabled) {
      await profileController.setReminderEnabled(false);
    }
    await CheckInReminderService.instance.cancel();
  } else if (profileController.profile.reminderEnabled) {
    final result = await CheckInReminderService.instance.scheduleDaily(
      minutesPastMidnight: profileController.profile.reminderMinutes,
    );
    if (!result.isScheduled) {
      // Keep the stored preference honest rather than claiming a reminder that
      // is not actually registered with Android.
      await profileController.setReminderEnabled(false);
    }
  }
  final suggestionController = SuggestionController(
    libraryRepository: AssetActivityLibraryRepository(),
    suggestionRepository: SharedPreferencesSuggestionRepository(preferences),
  );
  await suggestionController.load();
  // Loaded at startup so Home can ask whether a suggestion is due without
  // waiting on an asset read during a rebuild.
  await suggestionController.warmUp();

  // Owned here so the daily-features recorder and the shell read one chat
  // history. The shell leaves a controller it was handed alone.
  final chatController = ChatController(preferences: preferences);
  await chatController.load();

  // Keeps the in-app part of each day's behavior row current, and drops rows
  // older than the retention the user chose. Reads only what the app already
  // holds; nothing here touches the device's usage data.
  final dailyFeatures = SharedPreferencesDailyFeaturesRepository(preferences);
  final featureRecorder = InAppFeatureRecorder(
    repository: dailyFeatures,
    sessions: () => sessionController.sessions,
    conversations: () => chatController.conversations,
    profile: () => profileController.profile,
  );
  await featureRecorder.recordRecent();
  await featureRecorder.prune();
  sessionController.addListener(featureRecorder.scheduleToday);
  chatController.addListener(featureRecorder.scheduleToday);

  // Phone patterns: off until the person turns it on, and reading anything
  // requires both their consent and Android's usage access.
  final consentController = ConsentController(
    repository: SharedPreferencesConsentRepository(preferences),
  );
  await consentController.load();
  final phonePatterns = PhonePatternsController(
    consent: consentController,
    collector: MethodChannelUsageCollector.instance,
    repository: dailyFeatures,
  );
  await phonePatterns.refresh();

  // Catches up on device usage when the app opens, returns to the foreground, or
  // phone patterns is switched on. Reads nothing unless both the person's
  // consent and Android's usage access are in place.
  final usageRunner = UsageCollectionRunner(
    patterns: phonePatterns,
    recorder: UsageRecorder(
      collector: MethodChannelUsageCollector.instance,
      repository: dailyFeatures,
      profile: () => profileController.profile,
      isCollecting: () => phonePatterns.isCollecting,
      keepsAppNames: () => phonePatterns.keepsAppNames,
    ),
  )..start();
  // Not awaited: the first screen should not wait on a week of events.
  unawaited(usageRunner.run());

  // Asks, once and gently, whether anything is going on when the person's days
  // look different from their own usual. It only ever asks about a shift across
  // more than one kind of pattern, never while safety support is active, and
  // never when they have turned it off.
  final breakPrompts = BreakPromptController(
    repository: SharedPreferencesBreakAnnotationRepository(preferences),
    rows: dailyFeatures.loadAll,
    sessions: () => sessionController.sessions,
    muted: () => profileController.profile.patternPromptsMuted,
    safetyActive: () => safetyController.hasActiveFlag,
  );
  phonePatterns.addListener(() => unawaited(breakPrompts.refresh()));
  sessionController.addListener(() => unawaited(breakPrompts.refresh()));
  profileController.addListener(() => unawaited(breakPrompts.refresh()));
  unawaited(breakPrompts.refresh());

  // Moments: good things the person wrote about, offered for keeping and kept
  // only on a yes. Looked at when an entry is saved or a message is sent, never
  // while safety support is active or when the person turned asking off.
  final moments = MomentsController(
    repository: SharedPreferencesMomentRepository(preferences),
    // Chat messages are read by the companion's model when it is connected;
    // everything else, and any miss, falls back to the offline reader.
    extractor: ServerMomentExtractor(
      requesterProvider: () => CompanionWebSocketService.liveMomentRequester,
    ),
  );
  await moments.load();
  void offerMoment(MomentCandidate candidate) {
    if (profileController.profile.momentPromptsMuted) return;
    if (safetyController.hasActiveFlag) return;
    unawaited(moments.consider(candidate).catchError((Object _) => null));
  }

  sessionController.onSaved = (session) {
    final text = session.text;
    if (text == null || text.trim().isEmpty) return;
    offerMoment(
      MomentCandidate(
        text: text,
        source: text.length > 80 ? MomentSource.journal : MomentSource.checkIn,
        createdAt: session.createdAt,
        sourceRef: session.id,
        moodWord: session.mood,
      ),
    );
  };
  // Deleting a conversation deletes the moments that came from it.
  chatController.onConversationDeleted = (messageIds) => unawaited(
    moments.deleteForSources([for (final id in messageIds) 'chat:$id']),
  );
  // Deleting an entry deletes the moments that came from it.
  sessionController.onDeleted = (session) =>
      unawaited(moments.deleteForSource(session.id));
  chatController.onUserMessage = (message) => offerMoment(
    MomentCandidate(
      text: message.text,
      source: MomentSource.chat,
      createdAt: message.timestamp,
      sourceRef: 'chat:${message.id}',
    ),
  );

  final memory = CompanionMemoryContext(
    consent: consentController,
    profile: profileController,
    moments: moments,
    sessions: () => sessionController.sessions,
    themes: breakPrompts.activeThemes,
  );

  // Every connection to the companion carries exactly what the person agreed to
  // share, and the same object feeds the "What Sol remembers" preview.
  CompanionWebSocketService.memoryProvider = memory.payload;
  CompanionWebSocketService.countryProvider = () =>
      profileController.profile.countryCode;

  final navigatorKey = GlobalKey<NavigatorState>();

  void openCheckInFromWidget(Uri? uri) {
    if (uri == null || uri.host != 'checkin') return;
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => CheckInModePage(
          sessionController: sessionController,
          safetyController: safetyController,
          profileController: profileController,
        ),
      ),
    );
  }

  // Keep the home-screen widget in step, but only when the line it shows
  // actually changes, so unrelated settings edits do not redraw it.
  String? lastWidgetPrompt;

  Future<void> refreshCheckInWidget() async {
    final prompt = CheckInWidgetService.promptFor(
      checkedInToday: CheckInWidgetService.checkedInToday(
        sessionController.sessions,
      ),
      restingToday: CheckInWidgetService.restingToday(
        profileController.restDays,
      ),
    );
    if (prompt == lastWidgetPrompt) return;
    lastWidgetPrompt = prompt;
    await CheckInWidgetService.instance.push(prompt);
  }

  sessionController.addListener(refreshCheckInWidget);
  profileController.addListener(refreshCheckInWidget);
  await refreshCheckInWidget();

  // Tapping the widget opens the check-in flow, whether the app was cold
  // started by the tap or is already running.
  HomeWidget.widgetClicked.listen(openCheckInFromWidget);
  final launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
  if (launchUri != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => openCheckInFromWidget(launchUri),
    );
  }

  runApp(
    SolaceApp(
      onboardingRepository: SharedPreferencesOnboardingRepository(preferences),
      sessionController: sessionController,
      safetyController: safetyController,
      profileController: profileController,
      therapistController: therapistController,
      habitController: habitController,
      suggestionController: suggestionController,
      chatController: chatController,
      phonePatterns: phonePatterns,
      breakPrompts: breakPrompts,
      moments: moments,
      memory: memory,
      navigatorKey: navigatorKey,
    ),
  );
}

class SolaceApp extends StatelessWidget {
  SolaceApp({
    required this.onboardingRepository,
    required this.sessionController,
    SafetyController? safetyController,
    ProfileController? profileController,
    SuggestionController? suggestionController,
    this.chatController,
    this.therapistController,
    this.habitController,
    this.phonePatterns,
    this.breakPrompts,
    this.moments,
    this.memory,
    this.navigatorKey,
    super.key,
  }) : safetyController =
           safetyController ??
           SafetyController(
             screener: const KeywordSafetyScreener(),
             repository: InMemorySafetyEventRepository(),
           ),
       profileController =
           profileController ??
           ProfileController(repository: InMemoryProfileRepository()),
       suggestionController = suggestionController ??
           SuggestionController(
             libraryRepository: AssetActivityLibraryRepository(),
             suggestionRepository: InMemorySuggestionRepository(),
           );

  final OnboardingRepository onboardingRepository;
  final SessionController sessionController;
  final SafetyController safetyController;
  final ProfileController profileController;
  final SuggestionController suggestionController;

  /// Shared with whatever else needs the chat history. When null the shell
  /// creates its own, as it always did.
  final ChatController? chatController;

  /// The user's stored therapist contact. Null in tests that do not need it.
  final TherapistController? therapistController;

  /// The user's habit reminders. Null in tests that do not need it.
  final HabitController? habitController;

  /// The opt-in phone patterns control. Null in tests that do not need it.
  final PhonePatternsController? phonePatterns;

  /// The "anything going on?" question. Null in tests that do not need it.
  final BreakPromptController? breakPrompts;
  final MomentsController? moments;
  final CompanionMemoryContext? memory;

  /// Lets the home-screen widget push the check-in flow from outside the tree.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    // Rebuild the theme whenever the user switches palette.
    return AnimatedBuilder(
      animation: profileController,
      builder: (context, _) {
        final palette = SolaceColors.of(
          SolacePaletteId.fromId(profileController.profile.paletteId),
        );
        return MaterialApp(
          title: 'Solace',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(palette: palette),
          home: OnboardingGate(
            repository: onboardingRepository,
            sessionController: sessionController,
            safetyController: safetyController,
            profileController: profileController,
            suggestionController: suggestionController,
            chatController: chatController,
            therapistController: therapistController,
            habitController: habitController,
            phonePatterns: phonePatterns,
            breakPrompts: breakPrompts,
            moments: moments,
            memory: memory,
          ),
        );
      },
    );
  }
}

// Kept as an alias while early integrations migrate to the product name.
typedef MainApp = SolaceApp;
