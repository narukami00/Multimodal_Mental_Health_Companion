import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/break_annotation.dart';
import 'package:solace_mobile/core/models/consent.dart';
import 'package:solace_mobile/core/models/daily_features.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/research/ablations.dart';
import 'package:solace_mobile/domain/export/data_export.dart';

final _at = DateTime(2026, 10, 20, 12);

ConsentLedger _ledger({bool phone = true}) => ConsentLedger([
  if (phone)
    ConsentEvent(
      key: ConsentKey.usageFootprint.key,
      status: ConsentStatus.granted,
      textVersion: '1.0',
      occurredAt: DateTime(2026, 10, 1),
    ),
]);

ExportSources _sources({bool phone = true, bool shuffled = false}) {
  final days = [
    const DailyFeatures(
      dayKey: '2026-10-18',
      sources: {'usage', 'usageFinal', 'inApp'},
      screenOnMinutes: 200,
      categoryMinutes: {'social': 90},
      topApps: [AppUsage(name: 'SecretChatApp', minutes: 90)],
      checkInCount: 2,
      journalWordCount: 40,
    ),
    const DailyFeatures(dayKey: '2026-10-19', sources: {'inApp'}, checkInCount: 1),
  ];
  final sessions = [
    SessionRecord(
      id: 's1',
      createdAt: DateTime(2026, 10, 18, 9),
      mode: CaptureMode.text,
      text: 'MY PRIVATE JOURNAL WORDS about a hard week',
      mood: 'Wobbly',
      emotionResults: [
        EmotionResult(
          sessionId: 's1',
          modality: EmotionModality.text,
          timestamp: DateTime(2026, 10, 18, 9),
          modelVersion: 'mock',
          labels: const [EmotionLabel(label: 'tense', score: 0.7)],
        ),
      ],
    ),
    SessionRecord(
      id: 's2',
      createdAt: DateTime(2026, 10, 19, 9),
      mode: CaptureMode.text,
      text: 'a calmer day',
      mood: 'Steady',
    ),
  ];
  final suggestions = [
    SuggestionRecord(
      id: 'g1',
      activityId: 'walk',
      shownAt: DateTime(2026, 10, 18, 10),
      contextTags: const ['work'],
      status: SuggestionStatus.completed,
      done: true,
      comment: 'PRIVATE COMMENT about the walk',
      moodBefore: 'Wobbly',
      moodAfter: 'Steady',
    ),
  ];
  final moments = [
    MemoryMoment(
      id: 'm1',
      text: 'PRIVATE MOMENT coffee with a friend',
      createdAt: DateTime(2026, 10, 19, 20),
      occurredOn: '2026-10-19',
      source: MomentSource.journal,
      state: MomentState.confirmed,
      moodWord: 'Steady',
      emotionClass: 'joy',
      emotionConfidence: 0.8,
    ),
  ];
  return ExportSources(
    consent: _ledger(phone: phone),
    dailyFeatures: shuffled ? days.reversed.toList() : days,
    sessions: shuffled ? sessions.reversed.toList() : sessions,
    suggestions: suggestions,
    moments: moments,
    momentTombstones: [MomentTombstone(id: 'gone1', deletedAt: DateTime(2026, 10, 20))],
    breakAnnotations: [
      BreakAnnotation(
        breakKey: '2026-10-15:screen+rhythm',
        status: BreakAnnotationStatus.answered,
        shownAt: DateTime(2026, 10, 16),
        decidedAt: DateTime(2026, 10, 16, 8),
        theme: 'work',
      ),
    ],
  );
}

Map<String, Object?> _build(
  ExportScope scope, {
  bool phone = true,
  bool shuffled = false,
  Ablations? arm,
}) => buildDataExport(
  sources: _sources(phone: phone, shuffled: shuffled),
  scope: scope,
  participantId: 'p-123',
  exportedAt: _at,
  arm: arm,
);

void main() {
  test('says what it is: version, scope, participant, time, and the study arm', () {
    final export = _build(ExportScope.research, arm: const Ablations(phoneSignals: false));

    expect(export['schemaVersion'], exportSchemaVersion);
    expect(export['scope'], 'research');
    expect(export['participantId'], 'p-123');
    expect(export['exportedAt'], _at.toIso8601String());
    expect(export['arm'], 'no-phone');
  });

  group('the research scope', () {
    test('contains no free text and no app names anywhere', () {
      final text = jsonEncode(_build(ExportScope.research));

      for (final needle in [
        'MY PRIVATE JOURNAL WORDS',
        'a calmer day',
        'PRIVATE COMMENT',
        'PRIVATE MOMENT',
        'SecretChatApp',
      ]) {
        expect(text, isNot(contains(needle)), reason: needle);
      }
    });

    test('keeps what an analysis needs: moods, outcomes, counts, and kinds of app', () {
      final export = _build(ExportScope.research);
      final checkIn = (export['checkIns']! as List).first as Map;
      final suggestion = (export['suggestions']! as List).single as Map;
      final day = (export['dailyFeatures']! as List).first as Map;

      expect(checkIn['mood'], 'Wobbly');
      expect(checkIn['wordCount'], 8);
      expect(suggestion['moodBefore'], 'Wobbly');
      expect(suggestion['moodAfter'], 'Steady');
      expect(day['screenOnMinutes'], 200);
      expect(day['categoryMinutes'], {'social': 90});
      expect(day.containsKey('topApps'), isFalse);
    });
  });

  group('the person scope', () {
    test('carries their own words, so the export is theirs complete', () {
      final text = jsonEncode(_build(ExportScope.person));

      expect(text, contains('MY PRIVATE JOURNAL WORDS'));
      expect(text, contains('PRIVATE COMMENT'));
      expect(text, contains('PRIVATE MOMENT'));
    });
  });

  group('whatever the scope', () {
    for (final scope in ExportScope.values) {
      test('${scope.name}: phone values need phone consent, and without it none appear', () {
        final export = _build(scope, phone: false);
        final days = export['dailyFeatures']! as List;

        expect(export['phoneSignalsIncluded'], isFalse);
        for (final day in days.cast<Map>()) {
          expect(day.containsKey('screenOnMinutes'), isFalse);
          expect(day.containsKey('categoryMinutes'), isFalse);
          expect(day.containsKey('topApps'), isFalse);
        }
        // What was made inside Solace is still the person's, and stays.
        expect((days.first as Map)['checkInCount'], 2);
      });

      test('${scope.name}: a model reading is labelled as one, apart from what the person said', () {
        final export = _build(scope);
        final checkIn = (export['checkIns']! as List).first as Map;
        final moment = (export['moments']! as List).single as Map;

        expect(checkIn['mood'], 'Wobbly');
        expect((checkIn['emotionResults']! as List).single, containsPair('modelVersion', 'mock'));
        expect(moment['moodWord'], 'Steady');
        expect(moment['emotionClass'], 'joy');
        expect(moment['emotionConfidence'], 0.8);
      });

      test('${scope.name}: a deleted moment is only an id and a time', () {
        final stone = (_build(scope)['momentTombstones']! as List).single as Map;

        expect(stone.keys.toSet(), {'id', 'deletedAt'});
      });

      test('${scope.name}: the same sources give the same file, in any input order', () {
        expect(
          jsonEncode(_build(scope, shuffled: true)),
          jsonEncode(_build(scope)),
        );
      });
    }
  });

  test('consent history and shift answers are included, as the person chose them', () {
    final export = _build(ExportScope.research);

    expect((export['consentEvents']! as List).single, containsPair('status', 'granted'));
    expect((export['shiftAnswers']! as List).single, containsPair('theme', 'work'));
  });

  test('an export is plain JSON', () {
    expect(() => jsonEncode(_build(ExportScope.person)), returnsNormally);
  });
}
