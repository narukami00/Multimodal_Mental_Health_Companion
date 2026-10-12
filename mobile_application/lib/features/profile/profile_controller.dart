import 'package:flutter/foundation.dart';

import '../../core/day_key.dart';
import '../../core/models/emergency_contact.dart';
import '../../core/models/user_profile.dart';
import '../../data/contracts/profile_repository.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({required ProfileRepository repository})
    : _repository = repository;

  final ProfileRepository _repository;
  UserProfile _profile = const UserProfile();
  bool _isLoaded = false;

  UserProfile get profile => _profile;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _profile = await _repository.load();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> savePreferences({
    required List<String> preferredActivities,
    required List<String> constraints,
    required List<String> interactionPreferences,
    required List<String> neverSuggest,
  }) async {
    _profile = _profile.copyWith(
      preferredActivities: List.unmodifiable(preferredActivities),
      constraints: List.unmodifiable(constraints),
      interactionPreferences: List.unmodifiable(interactionPreferences),
      neverSuggest: List.unmodifiable(neverSuggest),
      preferencesCompleted: true,
    );
    await _persist();
  }

  Future<void> saveAnswer({
    required QuizBlock block,
    required String questionId,
    required int value,
  }) async {
    final answers = switch (block) {
      QuizBlock.erqS => {..._profile.erqSAnswers, questionId: value},
      QuizBlock.gad7 => {..._profile.gad7Answers, questionId: value},
      QuizBlock.phq9 => {..._profile.phq9Answers, questionId: value},
    };
    final skippedBlocks = _profile.skippedBlocks
        .where((item) => item != block.name)
        .toList();
    _profile = switch (block) {
      QuizBlock.erqS => _profile.copyWith(
        erqSAnswers: answers,
        skippedBlocks: skippedBlocks,
      ),
      QuizBlock.gad7 => _profile.copyWith(
        gad7Answers: answers,
        skippedBlocks: skippedBlocks,
      ),
      QuizBlock.phq9 => _profile.copyWith(
        phq9Answers: answers,
        skippedBlocks: skippedBlocks,
      ),
    };
    await _persist();
  }

  Future<void> markBlockSkipped(QuizBlock block) async {
    final skippedBlocks = {..._profile.skippedBlocks, block.name}.toList();
    _profile = _profile.copyWith(skippedBlocks: skippedBlocks);
    await _persist();
  }

  Future<void> markBaselineComplete() async {
    if (!_profile.baselineComplete) return;
    _profile = _profile.copyWith(baselineCompletedAt: DateTime.now());
    await _persist();
  }

  /// Records the first launch time once, so the You tab can show a real
  /// "member since" date instead of a hardcoded one.
  Future<void> ensureFirstRun() async {
    if (_profile.firstRunAt != null) return;
    _profile = _profile.copyWith(firstRunAt: DateTime.now());
    await _persist();
  }

  /// Stores the user's display name and/or chosen profile photo.
  Future<void> saveIdentity({String? displayName, String? avatarPath}) async {
    _profile = _profile.copyWith(
      displayName: displayName,
      avatarPath: avatarPath,
    );
    await _persist();
  }

  /// Enables or disables gentle haptic feedback across the app.
  Future<void> setHapticsEnabled(bool enabled) async {
    _profile = _profile.copyWith(hapticsEnabled: enabled);
    await _persist();
  }

  /// Enables or disables ambient breath audio during pause moments.
  Future<void> setAmbientAudioEnabled(bool enabled) async {
    _profile = _profile.copyWith(ambientAudioEnabled: enabled);
    await _persist();
  }

  /// Switches the active colour palette.
  Future<void> setPaletteId(String paletteId) async {
    _profile = _profile.copyWith(paletteId: paletteId);
    await _persist();
  }

  /// Turns the daily check-in reminder on or off.
  Future<void> setReminderEnabled(bool enabled) async {
    _profile = _profile.copyWith(reminderEnabled: enabled);
    await _persist();
  }

  /// Updates the daily reminder time, in minutes past midnight.
  Future<void> setReminderMinutes(int minutes) async {
    _profile = _profile.copyWith(
      reminderMinutes: minutes.clamp(0, 24 * 60 - 1),
    );
    await _persist();
  }

  Future<void> setIdeaPushEnabled(bool enabled) async {
    _profile = _profile.copyWith(ideaPushEnabled: enabled);
    await _persist();
  }

  /// Sets the sleep window idea pushes are held back in. Minutes past midnight;
  /// the window may cross midnight.
  Future<void> setQuietHours({
    bool? enabled,
    int? startMinutes,
    int? endMinutes,
  }) async {
    _profile = _profile.copyWith(
      quietHoursEnabled: enabled,
      quietStartMinutes: startMinutes?.clamp(0, 24 * 60 - 1),
      quietEndMinutes: endMinutes?.clamp(0, 24 * 60 - 1),
    );
    await _persist();
  }

  /// Saves the user's usual sleep hours, as minutes past midnight. The window
  /// may cross midnight. Giving hours supersedes an earlier skip.
  Future<void> setSleepHours({
    required int startMinutes,
    required int endMinutes,
  }) async {
    _profile = _profile.copyWith(
      sleepStartMinutes: _minuteOfDay(startMinutes),
      sleepEndMinutes: _minuteOfDay(endMinutes),
      sleepHoursSkipped: false,
    );
    await _persist();
  }

  /// Saves where the person is based; Support then shows that country's resources.
  Future<void> setCountry(String code) async {
    _profile = _profile.copyWith(countryCode: code.trim().toUpperCase());
    await _persist();
  }

  /// Records that the user chose not to give sleep hours. That is an answer,
  /// not a gap, so the setup meter counts it as done.
  Future<void> skipSleepHours() async {
    _profile = _profile.copyWith(sleepHoursSkipped: true);
    await _persist();
  }

  /// Turns the separate weekend sleep hours on or off. The weekend pair is kept
  /// while off, so switching back on restores what was chosen.
  Future<void> setWeekendsDiffer(bool differ) async {
    _profile = _profile.copyWith(weekendSleepDiffers: differ);
    await _persist();
  }

  /// Saves the weekend sleep hours, as minutes past midnight.
  Future<void> setWeekendSleepHours({
    required int startMinutes,
    required int endMinutes,
  }) async {
    _profile = _profile.copyWith(
      weekendSleepStartMinutes: _minuteOfDay(startMinutes),
      weekendSleepEndMinutes: _minuteOfDay(endMinutes),
    );
    await _persist();
  }

  /// Copies the usual sleep hours into quiet hours and switches them on.
  ///
  /// A one-off copy the user asks for: the two settings stay independent
  /// afterwards. Returns false, changing nothing, when there are no sleep hours
  /// to copy.
  Future<bool> useSleepHoursAsQuietHours() async {
    if (!_profile.sleepHoursSet) return false;
    _profile = _profile.copyWith(
      quietHoursEnabled: true,
      quietStartMinutes: _profile.sleepStartMinutes,
      quietEndMinutes: _profile.sleepEndMinutes,
    );
    await _persist();
    return true;
  }

  /// How many days of derived daily features are kept before pruning.
  Future<void> setFeatureRetentionDays(int days) async {
    _profile = _profile.copyWith(
      featureRetentionDays: days.clamp(minRetentionDays, maxRetentionDays),
    );
    await _persist();
  }

  /// Turns the "anything going on?" questions about shifting patterns off or on.
  Future<void> setPatternPromptsMuted(bool muted) async {
    _profile = _profile.copyWith(patternPromptsMuted: muted);
    await _persist();
  }

  /// Turns "Want me to remember this?" off or on.
  Future<void> setMomentPromptsMuted(bool muted) async {
    _profile = _profile.copyWith(momentPromptsMuted: muted);
    await _persist();
  }

  static const minRetentionDays = 30;
  static const maxRetentionDays = 365;

  static int _minuteOfDay(int minutes) => minutes.clamp(0, 24 * 60 - 1);

  /// The contact the user has marked as the person to call first, if any.
  EmergencyContact? get iceContact {
    for (final contact in _profile.emergencyContacts) {
      if (contact.isIce) return contact;
    }
    return null;
  }

  /// Adds or replaces a support contact.
  ///
  /// Marking one contact as ICE clears the flag on every other contact, so
  /// there is never more than one "call first" number.
  Future<void> saveEmergencyContact(EmergencyContact contact) async {
    final others = _profile.emergencyContacts
        .where((item) => item.id != contact.id)
        .map(
          (item) => contact.isIce && item.isIce
              ? item.copyWith(isIce: false)
              : item,
        )
        .toList();

    _profile = _profile.copyWith(
      emergencyContacts: List.unmodifiable([...others, contact]),
    );
    await _persist();
  }

  /// Removes a support contact. Missing ids are ignored.
  Future<void> removeEmergencyContact(String id) async {
    final remaining = _profile.emergencyContacts
        .where((contact) => contact.id != id)
        .toList();
    if (remaining.length == _profile.emergencyContacts.length) return;

    _profile = _profile.copyWith(
      emergencyContacts: List.unmodifiable(remaining),
    );
    await _persist();
  }

  /// The days the user has declared as rest.
  Set<String> get restDays => _profile.restDays.toSet();

  /// Records a day as rest. One tap, no reason, never capped.
  Future<void> declareRestDay(DateTime day) async {
    final key = dayKey(day);
    if (_profile.restDays.contains(key)) return;

    _profile = _profile.copyWith(
      restDays: List.unmodifiable([..._profile.restDays, key]),
    );
    await _persist();
  }

  /// Undoes a rest declaration, for a mis-tap.
  Future<void> removeRestDay(DateTime day) async {
    final key = dayKey(day);
    if (!_profile.restDays.contains(key)) return;

    _profile = _profile.copyWith(
      restDays: List.unmodifiable(
        _profile.restDays.where((item) => item != key),
      ),
    );
    await _persist();
  }

  /// Marks the welcome-back line as shown, so a lapse surfaces it once.
  Future<void> markWelcomeBackShown() async {
    _profile = _profile.copyWith(welcomeBackShownAt: DateTime.now());
    await _persist();
  }

  Future<void> _persist() async {
    await _repository.save(_profile);
    notifyListeners();
  }
}
