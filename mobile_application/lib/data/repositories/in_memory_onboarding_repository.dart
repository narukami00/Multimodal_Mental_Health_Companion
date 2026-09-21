import '../contracts/onboarding_repository.dart';

class InMemoryOnboardingRepository implements OnboardingRepository {
  bool _isComplete = false;
  int _currentPage = 0;
  bool? _usesMedia;

  @override
  bool get isComplete => _isComplete;

  @override
  int get currentPage => _currentPage;

  @override
  bool? get usesMedia => _usesMedia;

  @override
  Future<void> setCurrentPage(int page) async {
    _currentPage = page;
  }

  @override
  Future<void> complete() async {
    _isComplete = true;
  }

  @override
  Future<void> setMediaPreference({required bool enabled}) async {
    _usesMedia = enabled;
  }
}
