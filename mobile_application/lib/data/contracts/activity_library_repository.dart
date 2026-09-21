import '../../core/models/activity.dart';

abstract interface class ActivityLibraryRepository {
  Future<List<Activity>> load();
}
