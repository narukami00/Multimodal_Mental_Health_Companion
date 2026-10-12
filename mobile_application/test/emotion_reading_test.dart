import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/constants/moods.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/features/journal/emotion_reading_card.dart';
import 'package:solace_mobile/services/journal_analysis_client.dart';

EmotionResult reading({String? mood = 'low or tired', String? tier = 'clear', String pattern = 'AT'}) => EmotionResult(
      sessionId: 's',
      modality: EmotionModality.voice,
      timestamp: DateTime(2026, 10, 12),
      modelVersion: 'test',
      valence: -0.6,
      arousal: -0.4,
      classes: const {'neutral': 0.2, 'happy': 0.05, 'sad': 0.45, 'angry': 0.1, 'fear': 0.1, 'disgust': 0.05, 'surprise': 0.05},
      valenceProbs: const {'negative': 0.7, 'neutral': 0.2, 'positive': 0.1},
      arousalProbs: const {'low': 0.6, 'mid': 0.3, 'high': 0.1},
      mood: mood,
      tier: tier,
      pattern: pattern,
    );

SessionRecord entry({List<EmotionResult> results = const [], String? mood}) => SessionRecord(
      id: '1',
      createdAt: DateTime(2026, 10, 12, 9),
      mode: CaptureMode.voice,
      text: 'words',
      mood: mood,
      emotionResults: results,
    );

void main() {
  group('the reading card', () {
    testWidgets('shows the real breakdown in plain words, hedged', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: EmotionReadingCard(reading: reading())))));
      expect(find.text('This entry sounded a bit low or tired'), findsOneWidget);
      expect(find.textContaining('A guess from your voice and your words'), findsOneWidget);
      expect(find.text('Heavy 70%'), findsOneWidget);
      expect(find.text('Even 20%'), findsOneWidget);
      expect(find.text('Low 60%'), findsOneWidget);
      expect(find.text('Sad'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.textContaining('alence'), findsNothing); // the numbers' technical names never reach the screen
    });

    test('an unsure reading says nothing strong stood out; a hint says might', () {
      expect(EmotionReadingCard.headline(reading(mood: null, tier: null)), 'Nothing strong stood out: mostly even');
      expect(EmotionReadingCard.headline(reading(tier: 'hint')), 'This entry might have sounded a bit low or tired');
      expect(EmotionReadingCard.headline(reading(pattern: 'T')), 'This entry read as a bit low or tired');
    });

    test('names the signals that were used', () {
      expect(EmotionReadingCard.basedOn('ATV'), 'your voice, your words and your face');
      expect(EmotionReadingCard.basedOn('T'), 'your words');
    });
  });

  group('mood derived from the model', () {
    test('a reading decides the mood; the word picked in the past is only a fallback', () {
      expect(entry(results: [reading(mood: 'tense or upset')], mood: 'bright').effectiveMood, 'Wobbly');
      expect(entry(results: [reading(mood: null, tier: null)], mood: 'bright').effectiveMood, 'Quiet');
      expect(entry(mood: 'tender').effectiveMood, 'Tender'); // older entry: unchanged, still counted by insights
      expect(entry().effectiveMood, isNull);
    });

    test('an entry whose result has no full reading (the old mock) counts as unread', () {
      final legacy = EmotionResult(sessionId: 's', modality: EmotionModality.text, timestamp: DateTime(2026), modelVersion: 'mock-v1', labels: const [EmotionLabel(label: 'steady', score: 0.68)]);
      expect(entry(results: [legacy]).reading, isNull);
    });

    test('people see plain words, never the internal ones', () {
      expect({for (final m in Moods.values) m: Moods.display(m)}, {'Steady': 'Calm', 'Bright': 'Upbeat', 'Tender': 'Low', 'Wobbly': 'Tense', 'Quiet': 'Even'});
    });

    test('an old entry is stored and read back unchanged, a new one keeps its full reading', () {
      final round = SessionRecord.fromMap(entry(results: [reading()], mood: 'quiet').toMap());
      expect(round.reading?.classes?['sad'], 0.45);
      expect(round.reading?.mood, 'low or tired');
      expect(round.mood, 'quiet');
      final old = SessionRecord.fromMap({'id': 'x', 'createdAt': '2026-01-01T00:00:00', 'mode': 'text', 'text': 'hi', 'mood': 'steady', 'emotionResults': []});
      expect(old.effectiveMood, 'Steady');
    });
  });

  group('the server answer', () {
    test('becomes a full reading', () {
      final a = JournalAnalysis.fromJson({
        'transcript': ' I feel tired. ',
        'safety': null,
        'duration_s': 4.2,
        'emotion': {
          'pattern': 'ATV',
          'mood': 'low or tired',
          'tier': 'hint',
          'valence': -0.5,
          'arousal': -0.3,
          'model_version': 'emotion-v0',
          'estimate': {
            'l7': {'sad': 0.5, 'neutral': 0.3, 'happy': 0.2},
            'lv': {'negative': 0.6, 'neutral': 0.3, 'positive': 0.1},
            'la': {'low': 0.5, 'mid': 0.3, 'high': 0.2},
          },
        },
      });
      expect(a.transcript, 'I feel tired.');
      final r = a.toResults(sessionId: 'abc').single;
      expect(r.pattern, 'ATV');
      expect(r.modality, EmotionModality.voice);
      expect(r.labels!.first.label, 'sad');
      expect(r.classes!['neutral'], 0.3);
      expect(r.confidence, 0.6);
    });

    test('without a model answer there is no reading (never an invented one)', () {
      expect(const JournalAnalysis(transcript: 'x').toResults(sessionId: 'a'), isEmpty);
      expect(JournalAnalysis.fromJson({'transcript': 'x', 'emotion': {'pattern': 'T'}}).toResults(sessionId: 'a'), isEmpty);
    });
  });
}
