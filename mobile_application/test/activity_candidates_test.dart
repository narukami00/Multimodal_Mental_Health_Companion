import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/domain/recommendations/activity_safety_policy.dart';

/// The activity candidates are drafts waiting for the project owner's review. They are not in the app, but they
/// must still follow the app's own rules, so approving one can never break the library.
void main() {
  final candidates = [
    for (final raw in (jsonDecode(File('tool/activity_candidates.json').readAsStringSync()) as Map<String, dynamic>)['activities'] as List)
      Activity.fromMap(raw as Map<String, dynamic>),
  ];
  final live = [
    for (final raw in (jsonDecode(File('assets/activity_library.json').readAsStringSync()) as Map<String, dynamic>)['activities'] as List)
      Activity.fromMap(raw as Map<String, dynamic>),
  ];
  const states = {'steady', 'quiet', 'bright', 'wobbly', 'tender'};
  const contexts = {'home', 'alone', 'short_break', 'outdoors', 'with_someone', 'low_energy', 'work', 'relationships', 'sleep', 'health', 'money'};

  test('every candidate is still pending, so none can reach the app unreviewed', () {
    expect(candidates, isNotEmpty);
    for (final a in candidates) {
      expect(a.review.status, ActivityReviewStatus.pending, reason: a.id);
      expect(a.review.isApprovedForPrototype, isFalse, reason: a.id);
    }
  });

  test('none uses a term the safety policy blocks', () {
    for (final a in candidates) {
      expect(ActivitySafetyPolicy.isAllowed(a), isTrue, reason: '${a.id} ${a.title}');
    }
  });

  test('ids and titles are unique, among the candidates and against the live library', () {
    final ids = <String>{for (final a in live) a.id};
    final titles = <String>{for (final a in live) a.title.toLowerCase()};
    for (final a in candidates) {
      expect(ids.add(a.id), isTrue, reason: 'duplicate id ${a.id}');
      expect(titles.add(a.title.toLowerCase()), isTrue, reason: 'duplicate title ${a.title}');
    }
  });

  test("tags come from the app's own vocabulary, and times and effort are sane", () {
    for (final a in candidates) {
      expect(a.contexts, isNotEmpty, reason: a.id);
      expect(a.targetStates, isNotEmpty, reason: a.id);
      expect(a.contexts.toSet().difference(contexts), isEmpty, reason: a.id);
      expect(a.targetStates.toSet().difference(states), isEmpty, reason: a.id);
      expect(a.durationMinutes, inInclusiveRange(1, 30), reason: a.id);
      expect(a.effort, anyOf(ActivityEffort.low, ActivityEffort.medium), reason: '${a.id} should be gentle');
      expect(a.title.trim(), isNotEmpty);
      expect(a.description.trim().endsWith('.') || a.description.trim().endsWith('?'), isTrue, reason: '${a.id} should read as a sentence');
    }
  });

  test('they widen the library: a good spread of kinds, efforts, moods and topics', () {
    final byType = <ActivityType, int>{};
    for (final a in candidates) {
      byType[a.type] = (byType[a.type] ?? 0) + 1;
    }
    for (final type in ActivityType.values) {
      expect(byType[type] ?? 0, greaterThanOrEqualTo(15), reason: '$type');
    }
    // Every mood is catered for, including the heavier ones the app is gentlest with.
    for (final state in states) {
      expect(candidates.where((a) => a.targetStates.contains(state)).length, greaterThanOrEqualTo(25), reason: state);
    }
    // The recommender matches these against what a person writes about, which the live library almost never does.
    for (final topic in ['work', 'relationships', 'sleep', 'health', 'money']) {
      expect(candidates.where((a) => a.contexts.contains(topic)), isNotEmpty, reason: topic);
    }
    expect(candidates.where((a) => a.effort == ActivityEffort.low).length / candidates.length, greaterThan(0.8));
  });

  test('the wording is gentle: no commands to fix yourself, no health claims', () {
    const harsh = ['you must', 'you should', 'you need to', 'fix ', 'cure', 'heal ', 'treat ', 'therapy', 'depress', 'anxiety', 'disorder', 'boost your', 'improve your'];
    for (final a in candidates) {
      final text = '${a.title} ${a.description}'.toLowerCase();
      for (final word in harsh) {
        expect(text, isNot(contains(word)), reason: '${a.id}: "$word"');
      }
    }
  });
}
