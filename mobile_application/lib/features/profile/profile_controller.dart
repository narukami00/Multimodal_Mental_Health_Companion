import 'package:flutter/foundation.dart';

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

  Future<void> _persist() async {
    await _repository.save(_profile);
    notifyListeners();
  }
}
