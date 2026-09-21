import '../../core/models/user_profile.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> load();
  Future<void> save(UserProfile profile);
}
