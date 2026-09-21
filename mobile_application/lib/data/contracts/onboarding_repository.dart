abstract interface class OnboardingRepository {
  bool get isComplete;

  bool? get usesMedia;

  Future<void> setMediaPreference({required bool enabled});

  Future<void> complete();
}
