import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/emotion/emotion_taxonomy.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/domain/emotion/emotion_daily.dart';
import 'package:solace_mobile/domain/emotion/incongruence.dart';

EmotionResult _result(
  Map<String, double?> scores, {
  double? confidence,
  double? valence,
  double? arousal,
  DateTime? at,
  EmotionOrigin origin = EmotionOrigin.checkIn,
}) {
  return EmotionResult(
    sessionId: 's',
    modality: EmotionModality.text,
    origin: origin,
    timestamp: at ?? DateTime(2026, 10, 1, 9),
    modelVersion: 'test',
    confidence: confidence,
    valence: valence,
    arousal: arousal,
    labels: [
      for (final entry in scores.entries)
        EmotionLabel(label: entry.key, score: entry.value),
    ],
  );
}

const _taxonomy = EmotionTaxonomy.placeholder;

void main() {
  group('EmotionDaily.aggregate', () {
    test('no results, or none with labels, is no aggregate', () {
      expect(EmotionDaily.aggregate(const [], taxonomy: _taxonomy), isNull);
      expect(
        EmotionDaily.aggregate([
          EmotionResult(
            sessionId: 's',
            modality: EmotionModality.text,
            timestamp: DateTime(2026, 10, 1),
            modelVersion: 'x',
            valence: 0.4,
          ),
        ], taxonomy: _taxonomy),
        isNull,
      );
    });

    test('a single result gives its own distribution', () {
      final daily = EmotionDaily.aggregate([
        _result({'sadness': 0.7, 'calm': 0.3}, confidence: 0.7),
      ], taxonomy: _taxonomy)!;

      expect(daily.coverage, 1);
      expect(daily.dominantLabel, 'sadness');
      expect(daily.distribution['sadness'], closeTo(0.7, 1e-9));
      expect(daily.meanConfidence, closeTo(0.7, 1e-9));
      expect(daily.affectShare[AffectGroup.negative], closeTo(0.7, 1e-9));
      expect(daily.affectShare[AffectGroup.positive], closeTo(0.3, 1e-9));
    });

    test('the distribution always sums to one', () {
      final daily = EmotionDaily.aggregate([
        _result({'joy': 0.6, 'calm': 0.4}, confidence: 0.9),
        _result({'anger': 0.8, 'sadness': 0.2}, confidence: 0.3),
        _result({'neutral': 1.0}, confidence: 0.5),
      ], taxonomy: _taxonomy)!;

      final total = daily.distribution.values.fold<double>(0, (a, b) => a + b);
      expect(total, closeTo(1, 1e-9));
      final groupTotal = daily.affectShare.values.fold<double>(
        0,
        (a, b) => a + b,
      );
      expect(groupTotal, closeTo(1, 1e-9));
    });

    test('a confident result outweighs a hesitant one', () {
      final daily = EmotionDaily.aggregate([
        _result({'joy': 1.0}, confidence: 0.9),
        _result({'sadness': 1.0}, confidence: 0.1),
      ], taxonomy: _taxonomy)!;

      expect(daily.dominantLabel, 'joy');
      expect(daily.distribution['joy'], closeTo(0.9, 1e-9));
    });

    test('a result with no confidence counts at half weight, not full', () {
      final daily = EmotionDaily.aggregate([
        _result({'joy': 1.0}, confidence: 1.0),
        _result({'sadness': 1.0}),
      ], taxonomy: _taxonomy)!;

      expect(daily.distribution['joy'], closeTo(1 / 1.5, 1e-9));
      expect(daily.distribution['sadness'], closeTo(0.5 / 1.5, 1e-9));
    });

    test('zero-confidence results contribute nothing', () {
      final daily = EmotionDaily.aggregate([
        _result({'joy': 1.0}, confidence: 0.8),
        _result({'anger': 1.0}, confidence: 0.0),
      ], taxonomy: _taxonomy)!;

      expect(daily.coverage, 1);
      expect(daily.distribution.containsKey('anger'), isFalse);
    });

    test('labels without scores split the result evenly', () {
      final daily = EmotionDaily.aggregate([
        _result({'joy': null, 'calm': null}, confidence: 0.8),
      ], taxonomy: _taxonomy)!;

      expect(daily.distribution['joy'], closeTo(0.5, 1e-9));
      expect(daily.distribution['calm'], closeTo(0.5, 1e-9));
    });

    test('label case and padding do not split a class', () {
      final daily = EmotionDaily.aggregate([
        _result({'Calm': 1.0}, confidence: 0.7),
        _result({' calm ': 1.0}, confidence: 0.7),
      ], taxonomy: _taxonomy)!;

      expect(daily.distribution.keys, ['calm']);
    });

    test('ties go to the alphabetically first label, every time', () {
      final daily = EmotionDaily.aggregate([
        _result({'sadness': 0.5, 'anger': 0.5}, confidence: 0.8),
      ], taxonomy: _taxonomy)!;

      expect(daily.dominantLabel, 'anger');
    });

    test('entropy is 0 for one label and 1 for an even spread', () {
      final single = EmotionDaily.aggregate([
        _result({'joy': 1.0}, confidence: 0.8),
      ], taxonomy: _taxonomy)!;
      final even = EmotionDaily.aggregate([
        _result({
          for (final label in _taxonomy.labels) label: 1.0,
        }, confidence: 0.8),
      ], taxonomy: _taxonomy)!;

      expect(single.entropy, 0);
      expect(even.entropy, closeTo(1, 1e-9));
    });

    test('valence and arousal are optional and only averaged if present', () {
      final without = EmotionDaily.aggregate([
        _result({'joy': 1.0}, confidence: 0.8),
      ], taxonomy: _taxonomy)!;
      final withValues = EmotionDaily.aggregate([
        _result({'joy': 1.0}, confidence: 0.8, valence: 0.6, arousal: 0.2),
        _result({'joy': 1.0}, confidence: 0.8),
      ], taxonomy: _taxonomy)!;

      expect(without.meanValence, isNull);
      expect(without.meanArousal, isNull);
      expect(withValues.meanValence, closeTo(0.6, 1e-9));
      expect(withValues.meanArousal, closeTo(0.2, 1e-9));
    });
  });

  group('taxonomy independence', () {
    final results = [
      _result({'hopeful': 0.6, 'drained': 0.4}, confidence: 0.8),
    ];

    test('an unknown class set still aggregates, as unmapped', () {
      final daily = EmotionDaily.aggregate(results, taxonomy: _taxonomy)!;

      expect(daily.dominantLabel, 'hopeful');
      expect(daily.affectShare[AffectGroup.unmapped], closeTo(1, 1e-9));
      expect(daily.entropy, inInclusiveRange(0, 1));
    });

    test('supplying the new taxonomy only changes the grouping', () {
      final custom = EmotionTaxonomy.fromMap({
        'version': 'model-next',
        'classes': [
          {'label': 'hopeful', 'affectGroup': 'positive'},
          {'label': 'drained', 'affectGroup': 'negative'},
        ],
      });

      final before = EmotionDaily.aggregate(results, taxonomy: _taxonomy)!;
      final after = EmotionDaily.aggregate(results, taxonomy: custom)!;

      expect(after.distribution, before.distribution);
      expect(after.dominantLabel, before.dominantLabel);
      expect(after.affectShare[AffectGroup.positive], closeTo(0.6, 1e-9));
      expect(after.affectShare[AffectGroup.negative], closeTo(0.4, 1e-9));
    });
  });

  group('EmotionDaily.byDay', () {
    test('groups by local day and can limit to some origins', () {
      final byDay = EmotionDaily.byDay([
        _result({'joy': 1.0}, confidence: 0.8, at: DateTime(2026, 10, 1, 9)),
        _result(
          {'sadness': 1.0},
          confidence: 0.8,
          at: DateTime(2026, 10, 1, 23, 50),
        ),
        _result(
          {'anger': 1.0},
          confidence: 0.8,
          at: DateTime(2026, 10, 2, 0, 10),
          origin: EmotionOrigin.chat,
        ),
      ], taxonomy: _taxonomy);

      expect(byDay.keys.toSet(), {'2026-10-01', '2026-10-02'});
      expect(byDay['2026-10-01']!.coverage, 2);

      final checkInsOnly = EmotionDaily.byDay([
        _result({'joy': 1.0}, confidence: 0.8),
        _result({'anger': 1.0}, confidence: 0.8, origin: EmotionOrigin.chat),
      ], taxonomy: _taxonomy, origins: {EmotionOrigin.checkIn});

      expect(checkInsOnly['2026-10-01']!.dominantLabel, 'joy');
      expect(checkInsOnly['2026-10-01']!.coverage, 1);
    });
  });

  group('detectIncongruence', () {
    EmotionDaily negativeReading({double confidence = 0.8}) =>
        EmotionDaily.aggregate([
          _result({'sadness': 0.8, 'calm': 0.2}, confidence: confidence),
        ], taxonomy: _taxonomy)!;

    test('flags a bright self-report against a clearly negative reading', () {
      final flag = detectIncongruence(
        selfMood: 'Bright',
        emotion: negativeReading(),
      );

      expect(flag, isNotNull);
      expect(flag!.selfGroup, AffectGroup.positive);
      expect(flag.predictedGroup, AffectGroup.negative);
      expect(flag.predictedShare, closeTo(0.8, 1e-9));
    });

    test('flags the opposite mismatch too', () {
      final positive = EmotionDaily.aggregate([
        _result({'joy': 0.9, 'neutral': 0.1}, confidence: 0.9),
      ], taxonomy: _taxonomy)!;

      expect(
        detectIncongruence(
          selfMood: 'Wobbly',
          emotion: positive,
        )?.predictedGroup,
        AffectGroup.positive,
      );
    });

    test('ambiguous mood words never count as a mismatch', () {
      for (final mood in ['Steady', 'Quiet', 'Tender', null, 'unknown']) {
        expect(
          detectIncongruence(selfMood: mood, emotion: negativeReading()),
          isNull,
          reason: '$mood is ambiguous',
        );
      }
    });

    test('a low-confidence reading is never trusted to contradict anyone', () {
      expect(
        detectIncongruence(
          selfMood: 'Bright',
          emotion: negativeReading(confidence: 0.4),
        ),
        isNull,
      );
    });

    test('a mixed reading is not a clear mismatch', () {
      final mixed = EmotionDaily.aggregate([
        _result({'sadness': 0.5, 'joy': 0.5}, confidence: 0.9),
      ], taxonomy: _taxonomy)!;

      expect(detectIncongruence(selfMood: 'Bright', emotion: mixed), isNull);
    });

    test('unmapped labels and a missing reading are never a mismatch', () {
      final unmapped = EmotionDaily.aggregate([
        _result({'wistful': 1.0}, confidence: 0.9),
      ], taxonomy: _taxonomy)!;

      expect(detectIncongruence(selfMood: 'Bright', emotion: unmapped), isNull);
      expect(detectIncongruence(selfMood: 'Bright', emotion: null), isNull);
    });

    test('works from classes and confidence alone, with no valence', () {
      final emotion = negativeReading();

      expect(emotion.meanValence, isNull);
      expect(
        detectIncongruence(selfMood: 'Bright', emotion: emotion),
        isNotNull,
      );
    });
  });
}
