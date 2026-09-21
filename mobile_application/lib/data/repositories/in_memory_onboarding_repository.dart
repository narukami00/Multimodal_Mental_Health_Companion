import '../contracts/onboarding_repository.dart';

class InMemoryOnboardingRepository implements OnboardingRepository {
  bool _isComplete = false;
  bool? _usesMedia;

  @override
  bool get isComplete => _isComplete;

  @override
  bool? get usesMedia => _usesMedia;

  @override
  Future<void> complete() async {
    _isComplete = true;
  }

  @override
  Future<void> setMediaPreference({required bool enabled}) async {
    _usesMedia = enabled;
  }
}
