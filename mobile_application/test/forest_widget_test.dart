import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/tree_geometry.dart';
import 'package:solace_mobile/services/forest_widget_service.dart';

void main() {
  testWidgets(
    'a transparent sprite fits every species at seed, sapling and maturity',
    (tester) async {
      await tester.runAsync(() async {
        for (var species = 0; species < treeSpecies.length; species++) {
          for (final stage in [0.0, 2.5, 7.0]) {
            final png = await ForestWidgetService.renderTree(
              species: species,
              stage: stage,
            );
            final codec = await ui.instantiateImageCodec(png);
            final image = (await codec.getNextFrame()).image;
            codec.dispose();
            try {
              expect((image.width, image.height), (320, 320));
              final rgba = (await image.toByteData())!.buffer.asUint8List();
              int alpha(int x, int y) => rgba[(y * image.width + x) * 4 + 3];
              expect(rgba.indexWhere((byte) => byte > 0), isNonNegative);
              for (var i = 0; i < image.width; i++) {
                expect(
                  alpha(i, 0),
                  0,
                  reason: 'top of species $species at stage $stage',
                );
                expect(
                  alpha(i, 319),
                  0,
                  reason: 'bottom of species $species at stage $stage',
                );
                expect(
                  alpha(0, i),
                  0,
                  reason: 'left of species $species at stage $stage',
                );
                expect(
                  alpha(319, i),
                  0,
                  reason: 'right of species $species at stage $stage',
                );
              }
            } finally {
              image.dispose();
            }
          }
        }
      });
    },
  );

  test('only visible growth and species changes invalidate the sprite', () {
    String sig(double stage, {int species = 0}) =>
        ForestWidgetService.signature(species: species, stage: stage);
    expect(sig(3.0), sig(3.1));
    expect(sig(3.0), isNot(sig(3.3)));
    expect(sig(3.0), isNot(sig(3.0, species: 2)));
  });
}
