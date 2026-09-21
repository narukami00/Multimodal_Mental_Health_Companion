abstract interface class OnboardingRepository {
  bool get isComplete;

  int get currentPage;

  bool? get usesMedia;

  Future<void> setCurrentPage(int page);

  Future<void> setMediaPreference({required bool enabled});

  Future<void> complete();
}
