import 'dart:convert';
import 'dart:io';

import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/domain/library/activity_library_review.dart';

void main() {
  final file = File('assets/activity_library.json');
  if (!file.existsSync()) {
    stderr.writeln('Activity library not found: ${file.path}');
    exitCode = 1;
    return;
  }

  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic> ||
      decoded['activities'] is! List<dynamic>) {
    stderr.writeln('Activity library must contain an activities list.');
    exitCode = 1;
    return;
  }

  final activities = (decoded['activities'] as List<dynamic>)
      .whereType<Map<String, dynamic>>()
      .map(Activity.fromMap)
      .toList();
  final review = ActivityLibraryReview.validate(activities);
  if (!review.isValid) {
    stderr.writeln('Activity library review failed:');
    stderr.writeln(review.summary);
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Activity library passed review: ${activities.length} approved entries.',
  );
}
