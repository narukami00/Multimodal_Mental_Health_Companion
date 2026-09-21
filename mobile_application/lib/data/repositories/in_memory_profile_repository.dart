import '../../core/models/user_profile.dart';
import '../contracts/profile_repository.dart';

class InMemoryProfileRepository implements ProfileRepository {
  UserProfile _profile = const UserProfile();

  @override
  Future<UserProfile> load() async => _profile;

  @override
  Future<void> save(UserProfile profile) async {
    _profile = profile;
  }
}
