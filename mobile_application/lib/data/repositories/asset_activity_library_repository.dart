import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/models/activity.dart';
import '../../domain/library/activity_library_review.dart';
import '../contracts/activity_library_repository.dart';

class AssetActivityLibraryRepository implements ActivityLibraryRepository {
  AssetActivityLibraryRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/activity_library.json';
  final AssetBundle _bundle;

  @override
  Future<List<Activity>> load() async {
    final encoded = await _bundle.loadString(assetPath);
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Activity library must be a JSON object');
    }

    final rawActivities = decoded['activities'];
    if (rawActivities is! List<dynamic>) {
      throw const FormatException('Activity library is missing activities');
    }

    final activities = rawActivities
        .whereType<Map<String, dynamic>>()
        .map(Activity.fromMap)
        .toList();
    final review = ActivityLibraryReview.validate(activities);
    if (!review.isValid) {
      throw FormatException(
        'Activity library review failed:\n${review.summary}',
      );
    }
    return List.unmodifiable(activities);
  }
}
