import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/domain/recommendations/activity_safety_policy.dart';

/// The ideas drafted for the project owner's review. The owner approved the whole first batch, so it now lives in the
/// library (reviewer role `project_owner`); anything still in the candidates file is a draft and must stay unapproved.
/// Both must follow the app's own rules, so no approval can break the library.
void main() {
  List<Activity> read(String path) => [
        for (final raw in (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)['activities'] as List)
          Activity.fromMap(raw as Map<String, dynamic>),
      ];
  final live = read('assets/activity_library.json');
  final drafts = read('tool/activity_candidates.json');
  final batch = [for (final a in live) if (a.review.reviewerRole == 'project_owner') a];
  const states = {'steady', 'quiet', 'bright', 'wobbly', 'tender'};
  const contexts = {'home', 'alone', 'short_break', 'outdoors', 'with_someone', 'low_energy', 'work', 'relationships', 'sleep', 'health', 'money'};

  test('the approved batch is in the library, and any draft left over is still pending', () {
    expect(batch.length, 112);
    for (final a in batch) {
      expect(a.review.isApprovedForPrototype, isTrue, reason: a.id);
    }
    for (final a in drafts) {
      expect(a.review.status, ActivityReviewStatus.pending, reason: a.id);
      expect(a.review.isApprovedForPrototype, isFalse, reason: a.id);
    }
  });

  test('none uses a term the safety policy blocks', () {
    for (final a in [...batch, ...drafts]) {
      expect(ActivitySafetyPolicy.isAllowed(a), isTrue, reason: '${a.id} ${a.title}');
    }
  });

  test('ids and titles are unique across the whole library and any drafts', () {
    final ids = <String>{};
    final titles = <String>{};
    for (final a in [...live, ...drafts]) {
      expect(ids.add(a.id), isTrue, reason: 'duplicate id ${a.id}');
      expect(titles.add(a.title.toLowerCase()), isTrue, reason: 'duplicate title ${a.title}');
    }
  });

  test("tags come from the app's own vocabulary, and times and effort are sane", () {
    for (final a in batch) {
      expect(a.contexts, isNotEmpty, reason: a.id);
      expect(a.targetStates, isNotEmpty, reason: a.id);
      expect(a.contexts.toSet().difference(contexts), isEmpty, reason: a.id);
      expect(a.targetStates.toSet().difference(states), isEmpty, reason: a.id);
      expect(a.durationMinutes, inInclusiveRange(1, 45), reason: a.id);
      expect(a.effort, anyOf(ActivityEffort.low, ActivityEffort.medium), reason: '${a.id} should be gentle');
      expect(a.title.trim(), isNotEmpty);
      expect(a.description.trim().endsWith('.') || a.description.trim().endsWith('?'), isTrue, reason: '${a.id} should read as a sentence');
    }
  });

  test('the library has a good spread of kinds, moods and topics', () {
    final byType = <ActivityType, int>{};
    for (final a in live) {
      byType[a.type] = (byType[a.type] ?? 0) + 1;
    }
    for (final type in ActivityType.values) {
      expect(byType[type] ?? 0, greaterThanOrEqualTo(15), reason: '$type');
    }
    // Every mood is catered for, including the heavier ones the app is gentlest with.
    for (final state in states) {
      expect(live.where((a) => a.targetStates.contains(state)).length, greaterThanOrEqualTo(25), reason: state);
    }
    // The recommender matches these against what a person writes about.
    for (final topic in ['work', 'relationships', 'sleep', 'health', 'money']) {
      expect(live.where((a) => a.contexts.contains(topic)), isNotEmpty, reason: topic);
    }
    expect(batch.where((a) => a.effort == ActivityEffort.low).length / batch.length, greaterThan(0.8));
  });

  test('the wording is gentle: no commands to fix yourself, no health claims', () {
    const harsh = ['you must', 'you should', 'you need to', 'fix ', 'cure', 'heal ', 'treat ', 'therapy', 'depress', 'anxiety', 'disorder', 'boost your', 'improve your'];
    for (final a in batch) {
      final text = '${a.title} ${a.description}'.toLowerCase();
      for (final word in harsh) {
        expect(text, isNot(contains(word)), reason: '${a.id}: "$word"');
      }
    }
  });
}
