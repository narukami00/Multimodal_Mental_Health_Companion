import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/forest/forest_card_scene.dart';
import 'package:solace_mobile/services/forest_widget_service.dart';

bool _isPng(Uint8List b) => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  testWidgets('the scene is drawn as a PNG at the widget size', (tester) async {
    final bytes = await tester.runAsync(
      () => ForestWidgetService.renderScene(palette: ForestPalette.day, species: 0, stage: 3.5, waterWaiting: false),
    );
    expect(_isPng(bytes!), isTrue);
    // PNG header: width and height are big-endian at bytes 16..23.
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(16), 680);
    expect(data.getUint32(20), 240);
  });

  testWidgets('every light and every stage draws, and they look different', (tester) async {
    final results = await tester.runAsync(() async {
      final out = <String, Uint8List>{};
      for (final p in [ForestPalette.day, ForestPalette.golden, ForestPalette.dusk, ForestPalette.night]) {
        out[p.name] = await ForestWidgetService.renderScene(palette: p, species: 1, stage: 5, waterWaiting: false);
      }
      out['young'] = await ForestWidgetService.renderScene(palette: ForestPalette.day, species: 1, stage: 1, waterWaiting: false);
      out['can'] = await ForestWidgetService.renderScene(palette: ForestPalette.day, species: 1, stage: 5, waterWaiting: true);
      return out;
    });
    final r = results!;
    expect(r.values.every(_isPng), isTrue);
    expect(_same(r['day']!, r['night']!), isFalse, reason: 'night is not day');
    expect(_same(r['day']!, r['young']!), isFalse, reason: 'a seedling is not a tree');
    expect(_same(r['day']!, r['can']!), isFalse, reason: 'the watering can shows');
  });

  test('the widget is only redrawn when something visible changed', () {
    String sig(ForestPalette p, double stage, {int species = 0, bool can = false}) =>
        ForestWidgetService.signature(palette: p, species: species, stage: stage, waterWaiting: can);
    expect(sig(ForestPalette.day, 3.0), sig(ForestPalette.day, 3.2), reason: 'a sliver of growth is not worth a redraw');
    expect(sig(ForestPalette.day, 3.0), isNot(sig(ForestPalette.day, 4.0)));
    expect(sig(ForestPalette.day, 3.0), isNot(sig(ForestPalette.golden, 3.0)));
    expect(sig(ForestPalette.day, 3.0), isNot(sig(ForestPalette.day, 3.0, species: 2)));
    expect(sig(ForestPalette.day, 3.0), isNot(sig(ForestPalette.day, 3.0, can: true)));
  });
}
