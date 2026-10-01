import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/emotion/emotion_taxonomy.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/contracts/provider_contracts.dart';
import 'package:solace_mobile/domain/emotion/emotion_daily.dart';
import 'package:solace_mobile/providers/mock/configurable_mock_emotion_analyzer.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

/// The behavior every [EmotionAnalyzer] must have, the mock or the real model.
///
/// When the real analyzer lands, add one line at the bottom of `main` and this
/// whole contract runs against it.
void emotionAnalyzerContract(String name, EmotionAnalyzer Function() create) {
  group('EmotionAnalyzer contract: $name', () {
    for (final mode in CaptureMode.values) {
      test('handles $mode input, with or without text', () async {
        final analyzer = create();

        for (final text in [null, '', 'I felt okay today']) {
          final results = await analyzer.analyze(
            SessionInput(sessionId: 'abc', mode: mode, text: text),
          );

          for (final result in results) {
            expect(result.sessionId, 'abc');
            expect(result.modelVersion, isNotEmpty);
          }
        }
      });
    }

    test('maps the capture mode to the right modality', () async {
      final analyzer = create();
      final expected = {
        CaptureMode.text: EmotionModality.text,
        CaptureMode.voice: EmotionModality.voice,
        CaptureMode.video: EmotionModality.face,
      };

      for (final entry in expected.entries) {
        final results = await analyzer.analyze(
          SessionInput(sessionId: 's', mode: entry.key, text: 'hello'),
        );
        expect(results, isNotEmpty);
        expect(results.every((r) => r.modality == entry.value), isTrue);
      }
    });

    test('keeps every number in its valid range', () async {
      final analyzer = create();

      for (var i = 0; i < 20; i++) {
        final results = await analyzer.analyze(
          SessionInput(sessionId: 's$i', mode: CaptureMode.text, text: 'x'),
        );
        for (final result in results) {
          if (result.confidence != null) {
            expect(result.confidence, inInclusiveRange(0, 1));
          }
          if (result.valence != null) {
            expect(result.valence, inInclusiveRange(-1, 1));
          }
          if (result.arousal != null) {
            expect(result.arousal, inInclusiveRange(-1, 1));
          }
          for (final label in result.labels ?? const <EmotionLabel>[]) {
            expect(label.label.trim(), isNotEmpty);
            if (label.score != null) {
              expect(label.score, inInclusiveRange(0, 1));
            }
          }
        }
      }
    });

    test('its output feeds the daily aggregate without special cases', () async {
      final analyzer = create();
      final results = <EmotionResult>[];
      for (var i = 0; i < 5; i++) {
        results.addAll(
          await analyzer.analyze(
            SessionInput(sessionId: 's$i', mode: CaptureMode.text, text: 'x'),
          ),
        );
      }

      final daily = EmotionDaily.aggregate(
        results,
        taxonomy: EmotionTaxonomy.placeholder,
      );

      expect(daily, isNotNull);
      expect(daily!.coverage, greaterThan(0));
      expect(
        daily.distribution.values.fold<double>(0, (a, b) => a + b),
        closeTo(1, 1e-9),
      );
    });
  });
}

void main() {
  emotionAnalyzerContract(
    'MockEmotionAnalyzer',
    () => const MockEmotionAnalyzer(),
  );
  emotionAnalyzerContract(
    'ConfigurableMockEmotionAnalyzer',
    () => ConfigurableMockEmotionAnalyzer(seed: 7),
  );
  emotionAnalyzerContract(
    'ConfigurableMockEmotionAnalyzer with another taxonomy',
    () => ConfigurableMockEmotionAnalyzer(
      taxonomy: EmotionTaxonomy.fromMap({
        'version': 'other',
        'classes': [
          {'label': 'hopeful', 'affectGroup': 'positive'},
          {'label': 'drained', 'affectGroup': 'negative'},
          {'label': 'flat', 'affectGroup': 'neutral'},
        ],
      }),
      seed: 3,
    ),
  );
}
