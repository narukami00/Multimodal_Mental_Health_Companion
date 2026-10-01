import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/emotion/emotion_taxonomy.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';

void main() {
  group('EmotionTaxonomy', () {
    test('looks labels up ignoring case and padding', () {
      const taxonomy = EmotionTaxonomy.placeholder;

      expect(taxonomy.affectGroupOf('Sadness'), AffectGroup.negative);
      expect(taxonomy.affectGroupOf('  JOY '), AffectGroup.positive);
      expect(taxonomy.arousalBandOf('anger'), ArousalBand.high);
    });

    test('a label it does not know is unmapped, never an error', () {
      const taxonomy = EmotionTaxonomy.placeholder;

      expect(taxonomy.lookup('wistful'), isNull);
      expect(taxonomy.affectGroupOf('wistful'), AffectGroup.unmapped);
      expect(taxonomy.arousalBandOf('wistful'), isNull);
      expect(taxonomy.affectGroupOf(''), AffectGroup.unmapped);
    });

    test('a class with no arousal band reports none, not a guess', () {
      expect(
        EmotionTaxonomy.placeholder.arousalBandOf('neutral'),
        isNull,
      );
    });

    test('the placeholder is six classes and says it is provisional', () {
      expect(EmotionTaxonomy.placeholder.classes, hasLength(6));
      expect(EmotionTaxonomy.placeholder.version, startsWith('placeholder'));
    });

    test('a different class set works with no other change', () {
      final taxonomy = EmotionTaxonomy.fromMap({
        'version': 'model-2027-01',
        'classes': [
          {'label': 'Hopeful', 'affectGroup': 'positive'},
          {'label': 'Drained', 'affectGroup': 'negative', 'arousalBand': 'low'},
        ],
      });

      expect(taxonomy.version, 'model-2027-01');
      expect(taxonomy.labels, ['hopeful', 'drained']);
      expect(taxonomy.affectGroupOf('hopeful'), AffectGroup.positive);
      // The old placeholder labels are simply unknown now.
      expect(taxonomy.affectGroupOf('joy'), AffectGroup.unmapped);
    });

    test('round-trips through toMap/fromMap', () {
      final restored = EmotionTaxonomy.fromMap(
        EmotionTaxonomy.placeholder.toMap(),
      );

      expect(restored.version, EmotionTaxonomy.placeholder.version);
      expect(restored.labels, EmotionTaxonomy.placeholder.labels);
      expect(restored.arousalBandOf('anxiety'), ArousalBand.high);
    });

    test('malformed entries are skipped and the first duplicate wins', () {
      final taxonomy = EmotionTaxonomy.fromMap({
        'classes': [
          {'label': 'joy', 'affectGroup': 'positive'},
          {'label': 'JOY', 'affectGroup': 'negative'},
          'not a map',
          {'affectGroup': 'positive'},
          {'label': '   '},
          {'label': 'odd', 'affectGroup': 'sparkly', 'arousalBand': 'extreme'},
        ],
      });

      expect(taxonomy.version, 'unknown');
      expect(taxonomy.labels, ['joy', 'odd']);
      expect(taxonomy.affectGroupOf('joy'), AffectGroup.positive);
      // Unknown enum names degrade to unmapped / no band.
      expect(taxonomy.affectGroupOf('odd'), AffectGroup.unmapped);
      expect(taxonomy.arousalBandOf('odd'), isNull);
    });
  });

  group('EmotionResult origin', () {
    test('round-trips and stays separate from modality', () {
      final result = EmotionResult(
        sessionId: 's1',
        modality: EmotionModality.text,
        origin: EmotionOrigin.taskReview,
        timestamp: DateTime(2026, 10, 2, 9),
        modelVersion: 'mock-v1',
        labels: const [EmotionLabel(label: 'calm', score: 0.7)],
        confidence: 0.7,
      );

      final restored = EmotionResult.fromMap(result.toMap());

      expect(restored.origin, EmotionOrigin.taskReview);
      expect(restored.modality, EmotionModality.text);
      expect(restored.valence, isNull);
      expect(restored.arousal, isNull);
    });

    test('results written before origins existed read as check-ins', () {
      final legacy = EmotionResult.fromMap({
        'sessionId': 's0',
        'modality': 'voice',
        'timestamp': '2026-09-01T08:00:00.000',
        'modelVersion': 'mock-v1',
      });

      expect(legacy.origin, EmotionOrigin.checkIn);
      expect(legacy.modality, EmotionModality.voice);
    });

    test('an unrecognised origin falls back to a check-in', () {
      final result = EmotionResult.fromMap({
        'sessionId': 's2',
        'modality': 'text',
        'origin': 'dream',
        'timestamp': '2026-09-01T08:00:00.000',
        'modelVersion': 'm',
      });

      expect(result.origin, EmotionOrigin.checkIn);
    });
  });
}
