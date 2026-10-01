import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/emotion/emotion_taxonomy.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/providers/mock/configurable_mock_emotion_analyzer.dart';

const _input = SessionInput(sessionId: 's', mode: CaptureMode.text, text: 'hi');

Future<List<EmotionResult>> _run(
  ConfigurableMockEmotionAnalyzer analyzer,
  int calls,
) async => [
  for (var i = 0; i < calls; i++) ...await analyzer.analyze(_input),
];

AffectGroup _group(EmotionResult result, EmotionTaxonomy taxonomy) {
  final top = result.labels!.reduce(
    (a, b) => (a.score ?? 0) >= (b.score ?? 0) ? a : b,
  );
  return taxonomy.affectGroupOf(top.label);
}

void main() {
  test('emits classes with a confidence and no valence or arousal', () async {
    final result = (await ConfigurableMockEmotionAnalyzer(
      seed: 1,
    ).analyze(_input)).single;

    expect(result.valence, isNull);
    expect(result.arousal, isNull);
    expect(result.labels, isNotEmpty);
    expect(result.confidence, isNotNull);
    final total = result.labels!.fold<double>(0, (a, b) => a + (b.score ?? 0));
    expect(total, closeTo(1, 1e-9));
  });

  test('is reproducible for a seed and different across seeds', () async {
    final a = await _run(ConfigurableMockEmotionAnalyzer(seed: 5), 6);
    final b = await _run(ConfigurableMockEmotionAnalyzer(seed: 5), 6);
    final c = await _run(ConfigurableMockEmotionAnalyzer(seed: 6), 6);

    List<String> signature(List<EmotionResult> results) => [
      for (final r in results)
        '${r.labels!.first.label}:${r.labels!.first.score!.toStringAsFixed(6)}',
    ];
    expect(signature(a), signature(b));
    expect(signature(a), isNot(signature(c)));
  });

  test('a positive scenario reads positive and a negative one negative', () async {
    const taxonomy = EmotionTaxonomy.placeholder;
    final positive = await _run(
      ConfigurableMockEmotionAnalyzer(scenario: MockEmotionScenario.positive),
      12,
    );
    final negative = await _run(
      ConfigurableMockEmotionAnalyzer(scenario: MockEmotionScenario.negative),
      12,
    );

    expect(
      positive.every((r) => _group(r, taxonomy) == AffectGroup.positive),
      isTrue,
    );
    expect(
      negative.every((r) => _group(r, taxonomy) == AffectGroup.negative),
      isTrue,
    );
  });

  test('a decline turns from positive to negative over its calls', () async {
    const taxonomy = EmotionTaxonomy.placeholder;
    final results = await _run(
      ConfigurableMockEmotionAnalyzer(
        scenario: MockEmotionScenario.decline,
        driftCalls: 10,
      ),
      10,
    );

    expect(
      results.take(5).every((r) => _group(r, taxonomy) == AffectGroup.positive),
      isTrue,
    );
    expect(
      results.skip(5).every((r) => _group(r, taxonomy) == AffectGroup.negative),
      isTrue,
    );
  });

  test('an uplift turns from negative to positive', () async {
    const taxonomy = EmotionTaxonomy.placeholder;
    final results = await _run(
      ConfigurableMockEmotionAnalyzer(
        scenario: MockEmotionScenario.uplift,
        driftCalls: 6,
      ),
      6,
    );

    expect(_group(results.first, taxonomy), AffectGroup.negative);
    expect(_group(results.last, taxonomy), AffectGroup.positive);
  });

  test('draws from whatever taxonomy it is given', () async {
    final taxonomy = EmotionTaxonomy.fromMap({
      'version': 'v-next',
      'classes': [
        {'label': 'hopeful', 'affectGroup': 'positive'},
        {'label': 'drained', 'affectGroup': 'negative'},
      ],
    });
    final results = await _run(
      ConfigurableMockEmotionAnalyzer(
        taxonomy: taxonomy,
        scenario: MockEmotionScenario.negative,
      ),
      5,
    );

    for (final result in results) {
      expect(result.labels!.map((l) => l.label).toSet(), {
        'hopeful',
        'drained',
      });
      expect(result.labels!.first.label, 'drained');
      expect(result.modelVersion, endsWith('+v-next'));
    }
  });

  test('falls back to any class when the taxonomy has none in the group', () async {
    final taxonomy = EmotionTaxonomy.fromMap({
      'classes': [
        {'label': 'only', 'affectGroup': 'positive'},
      ],
    });

    final result = (await ConfigurableMockEmotionAnalyzer(
      taxonomy: taxonomy,
      scenario: MockEmotionScenario.negative,
    ).analyze(_input)).single;

    expect(result.labels!.single.label, 'only');
  });

  test('an empty taxonomy yields no reading instead of throwing', () async {
    final result = (await ConfigurableMockEmotionAnalyzer(
      taxonomy: const EmotionTaxonomy(version: 'empty', classes: []),
    ).analyze(_input)).single;

    expect(result.labels, isNull);
    expect(result.confidence, isNull);
  });

  test('stamps the origin and the injected clock', () async {
    final at = DateTime(2026, 10, 2, 8, 15);
    final result = (await ConfigurableMockEmotionAnalyzer(
      origin: EmotionOrigin.journal,
      clock: () => at,
    ).analyze(_input)).single;

    expect(result.origin, EmotionOrigin.journal);
    expect(result.timestamp, at);
  });
}
